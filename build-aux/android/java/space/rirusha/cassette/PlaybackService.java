package space.rirusha.cassette;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.Bitmap;
import android.media.session.MediaSession;
import android.os.IBinder;

/**
 * Foreground service that keeps the process alive while music plays and
 * owns the media notification. Started/stopped by SessionBridge. On
 * Android 13+ the system renders the controls itself from the
 * MediaSession's PlaybackState; the notification just has to exist and
 * carry the session token.
 */
public class PlaybackService extends Service {
	private static final String CHANNEL = "playback";
	private static final int NOTIFICATION_ID = 1;

	private static boolean running = false;
	private static PlaybackService instance = null;

	@Override
	public void onCreate() {
		super.onCreate();
		NotificationManager nm = getSystemService(NotificationManager.class);
		if (nm.getNotificationChannel(CHANNEL) == null) {
			NotificationChannel ch = new NotificationChannel(CHANNEL, "Playback", NotificationManager.IMPORTANCE_LOW);
			ch.setShowBadge(false);
			nm.createNotificationChannel(ch);
		}
	}

	@Override
	public int onStartCommand(Intent intent, int flags, int startId) {
		instance = this;
		running = true;
		startForeground(NOTIFICATION_ID, build(this), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
		return START_NOT_STICKY;
	}

	@Override
	public void onDestroy() {
		running = false;
		instance = null;
		stopForeground(STOP_FOREGROUND_REMOVE);
		super.onDestroy();
	}

	@Override
	public IBinder onBind(Intent intent) {
		return null;
	}

	/** Leaves the foreground (drops the notification) but keeps the service alive. */
	static void detach() {
		if (instance == null || !running) return;
		running = false;
		instance.stopForeground(STOP_FOREGROUND_REMOVE);
	}

	static void refresh(Context ctx) {
		if (!running) return;
		ctx.getSystemService(NotificationManager.class).notify(NOTIFICATION_ID, build(ctx));
	}

	private static Notification build(Context ctx) {
		Notification.Builder b = new Notification.Builder(ctx, CHANNEL)
				.setSmallIcon(android.R.drawable.ic_media_play)
				.setContentTitle(SessionBridge.currentTitle())
				.setContentText(SessionBridge.currentArtist())
				.setOngoing(SessionBridge.isPlaying())
				.setVisibility(Notification.VISIBILITY_PUBLIC)
				.setOnlyAlertOnce(true);

		Bitmap art = SessionBridge.currentArtwork();
		if (art != null) b.setLargeIcon(art);

		MediaSession.Token token = SessionBridge.token();
		if (token != null) {
			b.setStyle(new Notification.MediaStyle().setMediaSession(token));
		}

		Intent launch = ctx.getPackageManager().getLaunchIntentForPackage(ctx.getPackageName());
		if (launch != null) {
			b.setContentIntent(PendingIntent.getActivity(ctx, 0, launch, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT));
		}
		return b.build();
	}
}
