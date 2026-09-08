package space.rirusha.cassette;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;

/**
 * Debug aid (CASSETTE_DEBUG_STALLS): a heartbeat on the UI thread and a
 * watcher that logs the UI thread's stack when the heartbeat is more than
 * 80 ms late. GTK's frame clock waits for this thread's Choreographer, so a
 * busy UI thread freezes the GTK side too.
 */
final class UiThreadWatchdog {
	private static final String TAG = "CassetteStallUi";
	private static volatile long beat = System.nanoTime();

	static void start() {
		final Handler main = new Handler(Looper.getMainLooper());
		final Runnable tick = new Runnable() {
			@Override public void run() {
				beat = System.nanoTime();
				main.postDelayed(this, 5);
			}
		};
		main.post(tick);
		Thread watcher = new Thread(() -> {
			long reported = 0;
			for (;;) {
				try { Thread.sleep(20); } catch (InterruptedException e) { return; }
				long age = (System.nanoTime() - beat) / 1_000_000L;
				if (age > 80 && beat != reported) {
					reported = beat;
					StringBuilder sb = new StringBuilder("UI thread busy for " + age + " ms:\n");
					for (StackTraceElement e : Looper.getMainLooper().getThread().getStackTrace())
						sb.append("  at ").append(e).append('\n');
					Log.w(TAG, sb.toString());
				}
			}
		}, "cassette-ui-watchdog");
		watcher.setDaemon(true);
		watcher.start();
		Log.i(TAG, "UI thread watchdog armed");
	}
}
