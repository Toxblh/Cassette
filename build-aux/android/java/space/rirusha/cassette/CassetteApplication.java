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

	/** True when <external files>/debug.env has KEY=... (the native side reads the same file). */
	private boolean debugFlag(String key) {
		java.io.File f = new java.io.File(getExternalFilesDir(null), "debug.env");
		if (!f.exists()) return false;
		try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f))) {
			String line;
			while ((line = r.readLine()) != null) if (line.trim().startsWith(key + "=")) return true;
		} catch (java.io.IOException e) { /* no flag */ }
		return false;
	}

	/** The activity in front, if any: dialogs (sign-in) attach to it. */
	static Activity getResumedActivity() {
		return resumedActivity;
	}

	@Override
	public void onCreate() {
		// gettext (proxy-libintl) picks the language from the environment;
		// nothing sets it on Android, so the UI stayed English.
		java.util.Locale locale = java.util.Locale.getDefault();
		String lang = locale.getLanguage();
		if (!locale.getCountry().isEmpty()) lang += "_" + locale.getCountry();
		try {
			android.system.Os.setenv("LANGUAGE", lang, true);
			android.system.Os.setenv("LC_MESSAGES", lang + ".UTF-8", true);
			// The Yandex API language (Utils.get_language) comes from LANG.
			android.system.Os.setenv("LANG", lang + ".UTF-8", true);
		} catch (android.system.ErrnoException e) {
			android.util.Log.w("Cassette", "setenv LANGUAGE failed", e);
		}
		Native.init(this);
		super.onCreate();
		if (debugFlag("CASSETTE_DEBUG_STALLS")) UiThreadWatchdog.start();
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
