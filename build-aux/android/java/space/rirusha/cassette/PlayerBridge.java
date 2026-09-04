package space.rirusha.cassette;

import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.os.PowerManager;
import android.util.Log;

import java.io.File;

/**
 * One android.media.MediaPlayer for the whole process, driven from native
 * code (src/android/android-player.c). Commands arrive on GTK's thread and
 * are posted to the Java main looper; MediaPlayer callbacks fire there too
 * and go back to native, which hops onto the GLib main loop.
 */
public final class PlayerBridge {
	private static final String TAG = "Cassette";

	// Must match CassettePlayerEventType in android-player.h
	static final int EVENT_EOS = 0;
	static final int EVENT_FOCUS_LOST = 1;
	static final int EVENT_FOCUS_GAINED = 2;

	private static final Handler main = new Handler(Looper.getMainLooper());

	private static Context context;
	private static MediaPlayer player;
	private static boolean prepared = false;
	private static boolean playWhenReady = false;
	private static long pendingSeekMs = -1;
	private static float volume = 1f;
	private static boolean mute = false;
	private static boolean ducked = false;

	private static AudioManager audioManager;
	private static AudioFocusRequest focusRequest;
	private static boolean hasFocus = false;
	private static boolean pausedByFocus = false;

	private PlayerBridge() {}

	static native void nativeEvent(int event);
	static native void nativeError(String message);

	private static Context ctx() {
		if (context == null) context = NativeContext.get();
		return context;
	}

	// ── commands (called from native, any thread) ─────────────────────────

	/**
	 * Local files are opened right here, on the caller's thread: Cassette
	 * deletes its temporary track file right after handing it over, which is
	 * fine for GStreamer (it opens synchronously) and fatal for a MediaPlayer
	 * that opens later on the main looper. An open descriptor survives unlink.
	 */
	public static void setUri(final String uri) {
		ParcelFileDescriptor pfd = null;
		String path = localPath(uri);
		if (path != null) {
			try {
				pfd = ParcelFileDescriptor.open(new File(path), ParcelFileDescriptor.MODE_READ_ONLY);
			} catch (Exception e) {
				Log.w(TAG, "cannot open " + path + ": " + e.getMessage());
			}
		}
		final ParcelFileDescriptor fd = pfd;
		main.post(() -> doSetUri(uri, fd));
	}

	private static String localPath(String uri) {
		if (uri == null) return null;
		if (uri.startsWith("/")) return uri;
		if (uri.startsWith("file://")) return Uri.parse(uri).getPath();
		return null;
	}

	public static void play() {
		main.post(PlayerBridge::doPlay);
	}

	public static void pause() {
		main.post(() -> {
			// The echo of our own focus-loss event: Player.pause() called us
			// back. Keep the focus request and the flag so GAIN can resume.
			if (pausedByFocus) return;
			doPause(false);
		});
	}

	public static void stop() {
		main.post(PlayerBridge::doStop);
	}

	public static void seek(final long ms) {
		main.post(() -> doSeek(ms));
	}

	public static long position() {
		MediaPlayer p = player;
		if (p == null || !prepared) return 0;
		try {
			return p.getCurrentPosition();
		} catch (IllegalStateException e) {
			return 0;
		}
	}

	public static void setVolume(final float vol, final boolean muted) {
		main.post(() -> {
			volume = vol;
			mute = muted;
			applyVolume();
		});
	}

	// ── main-thread implementation ────────────────────────────────────────

	private static void release() {
		if (player != null) {
			try {
				player.reset();
			} catch (Exception ignored) {}
			player.release();
			player = null;
		}
		prepared = false;
		pendingSeekMs = -1;
	}

	private static void doSetUri(String uri, ParcelFileDescriptor fd) {
		release();
		if (uri == null || uri.isEmpty()) {
			closeQuietly(fd);
			return;
		}

		MediaPlayer p = new MediaPlayer();
		p.setAudioAttributes(new AudioAttributes.Builder()
				.setUsage(AudioAttributes.USAGE_MEDIA)
				.setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
				.build());
		p.setWakeMode(ctx(), PowerManager.PARTIAL_WAKE_LOCK);
		p.setOnPreparedListener(mp -> {
			if (mp != player) return;
			prepared = true;
			applyVolume();
			if (pendingSeekMs >= 0) {
				mp.seekTo(pendingSeekMs, MediaPlayer.SEEK_CLOSEST);
				pendingSeekMs = -1;
			}
			if (playWhenReady && requestFocus()) mp.start();
		});
		p.setOnCompletionListener(mp -> {
			if (mp != player) return;
			nativeEvent(EVENT_EOS);
		});
		p.setOnErrorListener((mp, what, extra) -> {
			if (mp == player) {
				nativeError("MediaPlayer error " + what + "/" + extra);
			}
			return true; // handled: no onCompletion afterwards
		});

		try {
			if (fd != null) {
				p.setDataSource(fd.getFileDescriptor());
			} else if (localPath(uri) != null) {
				throw new java.io.FileNotFoundException(uri);
			} else {
				p.setDataSource(ctx(), Uri.parse(uri));
			}
			player = p;
			p.prepareAsync();
		} catch (Exception e) {
			Log.w(TAG, "setDataSource failed", e);
			p.release();
			nativeError("Cannot open stream: " + e.getMessage());
		} finally {
			closeQuietly(fd);
		}
	}

	private static void closeQuietly(ParcelFileDescriptor fd) {
		if (fd == null) return;
		try {
			fd.close();
		} catch (Exception ignored) {}
	}

	private static void doPlay() {
		playWhenReady = true;
		pausedByFocus = false;
		if (player != null && prepared && requestFocus()) {
			player.start();
		}
	}

	private static void doPause(boolean byFocus) {
		playWhenReady = false;
		pausedByFocus = byFocus;
		if (player != null && prepared) {
			try {
				if (player.isPlaying()) player.pause();
			} catch (IllegalStateException ignored) {}
		}
		if (!byFocus) abandonFocus();
	}

	private static void doStop() {
		playWhenReady = false;
		pausedByFocus = false;
		release();
		abandonFocus();
	}

	private static void doSeek(long ms) {
		if (player != null && prepared) {
			player.seekTo(ms, MediaPlayer.SEEK_CLOSEST);
		} else {
			pendingSeekMs = ms;
		}
	}

	private static void applyVolume() {
		if (player == null) return;
		float v = mute ? 0f : volume;
		if (ducked) v *= 0.2f;
		try {
			player.setVolume(v, v);
		} catch (IllegalStateException ignored) {}
	}

	// ── audio focus ───────────────────────────────────────────────────────

	private static final AudioManager.OnAudioFocusChangeListener focusListener = change -> {
		switch (change) {
			case AudioManager.AUDIOFOCUS_LOSS:
				hasFocus = false;
				doPause(false);
				nativeEvent(EVENT_FOCUS_LOST);
				break;
			case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
				hasFocus = false;
				if (player != null && prepared && player.isPlaying()) {
					doPause(true);
					nativeEvent(EVENT_FOCUS_LOST);
				}
				break;
			case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:
				ducked = true;
				applyVolume();
				break;
			case AudioManager.AUDIOFOCUS_GAIN:
				hasFocus = true;
				ducked = false;
				applyVolume();
				if (pausedByFocus) {
					pausedByFocus = false;
					nativeEvent(EVENT_FOCUS_GAINED);
				}
				break;
		}
	};

	private static boolean requestFocus() {
		if (hasFocus) return true;
		if (audioManager == null) {
			audioManager = (AudioManager) ctx().getSystemService(Context.AUDIO_SERVICE);
		}
		if (focusRequest == null) {
			focusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
					.setAudioAttributes(new AudioAttributes.Builder()
							.setUsage(AudioAttributes.USAGE_MEDIA)
							.setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
							.build())
					.setOnAudioFocusChangeListener(focusListener, main)
					.setWillPauseWhenDucked(false)
					.build();
		}
		int rc = audioManager.requestAudioFocus(focusRequest);
		hasFocus = rc == AudioManager.AUDIOFOCUS_REQUEST_GRANTED;
		if (!hasFocus) Log.w(TAG, "audio focus not granted: " + rc);
		return hasFocus;
	}

	private static void abandonFocus() {
		if (hasFocus && audioManager != null && focusRequest != null) {
			audioManager.abandonAudioFocusRequest(focusRequest);
		}
		hasFocus = false;
	}
}
