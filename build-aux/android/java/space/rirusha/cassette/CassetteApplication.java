package space.rirusha.cassette;

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

	@Override
	public void onCreate() {
		Native.init(this);
		super.onCreate();
	}
}
