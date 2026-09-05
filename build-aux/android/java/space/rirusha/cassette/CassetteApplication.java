package space.rirusha.cassette;

import android.app.Activity;
import android.os.Bundle;

import org.gtk.android.RuntimeApplication;

/**
 * Loads libcassette.so through System.loadLibrary before the GTK runtime
 * dlopen()s it, so that the JNI resolver can find the Java_* native methods
 * of PlayerBridge and SessionBridge; then hands the Context to native code.
 * Referenced from AndroidManifest.xml (patched in android.mk).
 */
public class CassetteApplication extends RuntimeApplication {
	static {
		System.loadLibrary("cassette");
	}

	private static Activity resumedActivity = null;

	/** The activity in front, if any: dialogs (sign-in) attach to it. */
	static Activity getResumedActivity() {
		return resumedActivity;
	}

	@Override
	public void onCreate() {
		Native.init(this);
		super.onCreate();
		registerActivityLifecycleCallbacks(new ActivityLifecycleCallbacks() {
			@Override public void onActivityResumed(Activity a) { resumedActivity = a; }
			@Override public void onActivityPaused(Activity a) { if (resumedActivity == a) resumedActivity = null; }
			@Override public void onActivityCreated(Activity a, Bundle b) {}
			@Override public void onActivityStarted(Activity a) {}
			@Override public void onActivityStopped(Activity a) {}
			@Override public void onActivitySaveInstanceState(Activity a, Bundle b) {}
			@Override public void onActivityDestroyed(Activity a) {}
		});
	}
}
