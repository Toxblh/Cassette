package space.rirusha.cassette;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.CookieManager;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/**
 * Yandex OAuth (implicit flow) in a WebView. The authorize page redirects
 * to music.yandex.* with the token in the URL fragment; we intercept that
 * redirect, hand the token to native (src/android/android-auth.c) and
 * close. Closing without a token reports null.
 */
public class AuthActivity extends Activity {
	static final String EXTRA_URL = "url";
	private static final String REDIRECT_HOST = "music.yandex.";

	private WebView webView;
	private boolean fired = false;

	static native void nativeToken(String token);

	/** Called from native on GTK's thread. */
	public static void start(String url) {
		Context ctx = NativeContext.get();
		Intent intent = new Intent(ctx, AuthActivity.class);
		intent.putExtra(EXTRA_URL, url);
		intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
		ctx.startActivity(intent);
	}

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);

		webView = new WebView(this);
		WebSettings s = webView.getSettings();
		s.setJavaScriptEnabled(true);
		s.setDomStorageEnabled(true);
		CookieManager.getInstance().setAcceptCookie(true);

		webView.setWebViewClient(new WebViewClient() {
			@Override
			public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
				return intercept(request.getUrl());
			}

			@Override
			public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
				intercept(Uri.parse(url));
			}
		});

		setContentView(webView);

		String url = getIntent().getStringExtra(EXTRA_URL);
		if (url == null) {
			finish();
			return;
		}
		webView.loadUrl(url);
	}

	private boolean intercept(Uri uri) {
		if (uri == null || fired) return false;
		String host = uri.getHost();
		String fragment = uri.getFragment();
		if (host != null && host.contains(REDIRECT_HOST) && fragment != null && !fragment.isEmpty()) {
			String token = extractToken(fragment);
			if (token != null) {
				fired = true;
				nativeToken(token);
				finish();
				return true;
			}
		}
		return false;
	}

	private static String extractToken(String fragment) {
		for (String part : fragment.split("&")) {
			int eq = part.indexOf('=');
			if (eq > 0 && part.substring(0, eq).equals("access_token")) {
				return Uri.decode(part.substring(eq + 1));
			}
		}
		return null;
	}

	@Override
	protected void onDestroy() {
		if (webView != null) {
			webView.destroy();
			webView = null;
		}
		if (!fired) {
			fired = true;
			nativeToken(null);
		}
		super.onDestroy();
	}
}
