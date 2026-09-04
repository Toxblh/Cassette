package space.rirusha.cassette;

import android.content.Context;

/**
 * JNI bootstrap. The native side (src/android/android-jni.c) keeps the
 * application Context and this class's class loader so it can resolve the
 * bridge classes from GTK's native thread, where FindClass only sees the
 * system loader.
 */
public final class Native {
	private static boolean inited = false;

	private Native() {}

	public static synchronized void init(Context context) {
		if (inited) return;
		inited = true;
		NativeContext.set(context);
		nativeInit(context.getApplicationContext());
	}

	private static native void nativeInit(Context context);
}
