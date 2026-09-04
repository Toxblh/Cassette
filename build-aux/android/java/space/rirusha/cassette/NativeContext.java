package space.rirusha.cassette;

import android.content.Context;

/** Application Context handed over by CassetteApplication for the bridges. */
final class NativeContext {
	private static Context context;

	private NativeContext() {}

	static void set(Context ctx) {
		context = ctx.getApplicationContext();
	}

	static Context get() {
		if (context == null) throw new IllegalStateException("NativeContext not set");
		return context;
	}
}
