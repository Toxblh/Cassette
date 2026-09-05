package space.rirusha.cassette;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.view.Window;

/**
 * Entry point for the native side: shows the sign-in web view (AuthWebView)
 * as a dialog on the activity in front, or, when none is, as this activity.
 * The token (or null) comes back through nativeToken, once.
 */
public class AuthActivity extends Activity {
	static final String EXTRA_URL = "url";

	private AuthWebView view;

	static native void nativeToken(String token);

	/** Called from native on GTK's thread. */
	public static void start(String url) {
		Activity front = CassetteApplication.getResumedActivity();
		if (front != null) {
			front.runOnUiThread(() -> AuthWebView.showDialog(front, url, AuthActivity::nativeToken));
			return;
		}
		Context ctx = NativeContext.get();
		Intent intent = new Intent(ctx, AuthActivity.class);
		intent.putExtra(EXTRA_URL, url);
		intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
		ctx.startActivity(intent);
	}

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		// DayNight theme for the colours; the title bar is not wanted.
		requestWindowFeature(Window.FEATURE_NO_TITLE);
		String url = getIntent().getStringExtra(EXTRA_URL);
		if (url == null) {
			finish();
			return;
		}
		AuthWebView.styleWindow(getWindow(), this);
		view = new AuthWebView(this, url, token -> {
			nativeToken(token);
			finish();
		});
		setContentView(view.getView());
	}

	@Override
	protected void onDestroy() {
		if (view != null) {
			view.destroy();
			view = null;
		}
		super.onDestroy();
	}
}
