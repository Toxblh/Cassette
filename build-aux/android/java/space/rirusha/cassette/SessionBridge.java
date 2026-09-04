package space.rirusha.cassette;

import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.MediaMetadata;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

/**
 * MediaSession behind the contract of src/android/android-now-playing.c:
 * the same init/update/update_state/clear the macOS adapter uses. The
 * session feeds the lock screen, headset buttons and the notification that
 * PlaybackService keeps in the foreground.
 */
public final class SessionBridge {
	private static final String TAG = "Cassette";

	// Must match CMD_* in android-now-playing.c
	static final int CMD_PLAY = 0;
	static final int CMD_PAUSE = 1;
	static final int CMD_PLAY_PAUSE = 2;
	static final int CMD_NEXT = 3;
	static final int CMD_PREV = 4;
	static final int CMD_STOP = 5;

	private static final long ACTIONS =
			PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PAUSE | PlaybackState.ACTION_PLAY_PAUSE
			| PlaybackState.ACTION_SKIP_TO_NEXT | PlaybackState.ACTION_SKIP_TO_PREVIOUS
			| PlaybackState.ACTION_SEEK_TO | PlaybackState.ACTION_STOP;

	private static final Handler main = new Handler(Looper.getMainLooper());

	private static MediaSession session;
	private static MediaMetadata.Builder metadata;
	private static long durationMs;
	private static boolean playing;
	private static String artworkUrl;
	private static Bitmap artwork;
	private static long generation = 0;
	private static boolean serviceStarted = false;

	private SessionBridge() {}

	static native void nativeCommand(int cmd);
	static native void nativeSeek(double positionSec);

	static MediaSession.Token token() {
		return session == null ? null : session.getSessionToken();
	}

	static String currentTitle() {
		MediaMetadata m = session == null ? null : session.getController().getMetadata();
		return m == null ? "" : m.getString(MediaMetadata.METADATA_KEY_TITLE);
	}

	static String currentArtist() {
		MediaMetadata m = session == null ? null : session.getController().getMetadata();
		return m == null ? "" : m.getString(MediaMetadata.METADATA_KEY_ARTIST);
	}

	static Bitmap currentArtwork() {
		return artwork;
	}

	static boolean isPlaying() {
		return playing;
	}

	// ── contract ──────────────────────────────────────────────────────────

	public static void init() {
		main.post(() -> {
			if (session != null) return;
			Context ctx = NativeContext.get();
			session = new MediaSession(ctx, "Cassette");
			session.setCallback(new MediaSession.Callback() {
				@Override public void onPlay() { nativeCommand(CMD_PLAY); }
				@Override public void onPause() { nativeCommand(CMD_PAUSE); }
				@Override public void onSkipToNext() { nativeCommand(CMD_NEXT); }
				@Override public void onSkipToPrevious() { nativeCommand(CMD_PREV); }
				@Override public void onStop() { nativeCommand(CMD_STOP); }
				@Override public void onSeekTo(long pos) { nativeSeek(pos / 1000.0); }
			}, main);
			session.setPlaybackState(state(PlaybackState.STATE_NONE, 0));
		});
	}

	public static void update(final String title, final String artist, final String album,
	                          final double durationSec, final double elapsedSec,
	                          final boolean isPlaying, final String artUrl) {
		main.post(() -> {
			if (session == null) return;
			final long gen = ++generation;

			durationMs = (long) (durationSec * 1000);
			playing = isPlaying;

			metadata = new MediaMetadata.Builder()
					.putString(MediaMetadata.METADATA_KEY_TITLE, title)
					.putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
					.putString(MediaMetadata.METADATA_KEY_ALBUM, album)
					.putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs);

			boolean sameArt = artUrl != null && artUrl.equals(artworkUrl) && artwork != null;
			if (sameArt) {
				metadata.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, artwork);
			} else {
				artwork = null;
				artworkUrl = artUrl;
			}
			if (artUrl != null) {
				metadata.putString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI, artUrl);
			}

			session.setMetadata(metadata.build());
			session.setPlaybackState(state(isPlaying ? PlaybackState.STATE_PLAYING : PlaybackState.STATE_PAUSED,
					(long) (elapsedSec * 1000)));
			session.setActive(true);
			startService();
			PlaybackService.refresh(NativeContext.get());

			if (!sameArt && artUrl != null) fetchArtwork(artUrl, gen);
		});
	}

	public static void updateState(final double elapsedSec, final boolean isPlaying) {
		main.post(() -> {
			if (session == null || !session.isActive()) return;
			boolean changed = playing != isPlaying;
			playing = isPlaying;
			session.setPlaybackState(state(isPlaying ? PlaybackState.STATE_PLAYING : PlaybackState.STATE_PAUSED,
					(long) (elapsedSec * 1000)));
			if (changed) PlaybackService.refresh(NativeContext.get());
		});
	}

	public static void clear() {
		main.post(() -> {
			generation++;
			playing = false;
			if (session != null) {
				session.setPlaybackState(state(PlaybackState.STATE_STOPPED, 0));
				session.setActive(false);
			}
			stopService();
		});
	}

	// ── helpers ───────────────────────────────────────────────────────────

	private static PlaybackState state(int st, long positionMs) {
		return new PlaybackState.Builder()
				.setActions(ACTIONS)
				.setState(st, positionMs, st == PlaybackState.STATE_PLAYING ? 1f : 0f, SystemClock.elapsedRealtime())
				.build();
	}

	private static void startService() {
		if (serviceStarted) return;
		Context ctx = NativeContext.get();
		try {
			ctx.startForegroundService(new Intent(ctx, PlaybackService.class));
			serviceStarted = true;
		} catch (Exception e) {
			Log.w(TAG, "startForegroundService failed", e);
		}
	}

	/**
	 * Never stopService(): between two tracks the session is cleared and
	 * refilled within milliseconds, and a service stopped before its
	 * startForeground() ran throws ForegroundServiceDidNotStartInTimeException
	 * and kills the process. The service stays; it just leaves the foreground.
	 */
	private static void stopService() {
		serviceStarted = false;
		PlaybackService.detach();
	}

	private static void fetchArtwork(final String url, final long gen) {
		Thread t = new Thread(() -> {
			Bitmap bmp = null;
			try {
				HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
				c.setConnectTimeout(10000);
				c.setReadTimeout(15000);
				try (InputStream in = c.getInputStream()) {
					bmp = BitmapFactory.decodeStream(in);
				}
				c.disconnect();
			} catch (Exception e) {
				Log.w(TAG, "artwork fetch failed: " + e.getMessage());
			}
			final Bitmap result = bmp;
			if (result == null) return;
			main.post(() -> {
				if (gen != generation || session == null || metadata == null) return;
				artwork = result;
				metadata.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, result);
				session.setMetadata(metadata.build());
				PlaybackService.refresh(NativeContext.get());
			});
		}, "cassette-artwork");
		t.setDaemon(true);
		t.start();
	}
}
