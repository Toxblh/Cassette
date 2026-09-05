package space.rirusha.cassette;

import android.app.Activity;
import android.app.Dialog;
import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Color;
import android.net.Uri;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowInsetsController;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.Toast;

/**
 * Yandex OAuth (implicit flow) in a WebView. The authorize page redirects
 * to music.yandex.* with the token in the URL fragment; the redirect is
 * intercepted, the token handed to native (src/android/android-auth.c)
 * and the view closed. Closing without a token reports null, once.
 *
 * Shown as a full-screen dialog on the running activity, so the GTK
 * activity is never paused or recreated by the sign-in (some vendors'
 * task management would otherwise leave the app on its loading page).
 * AuthActivity is the fallback when no activity is in front.
 */
final class AuthWebView {
	private static final String REDIRECT_HOST = "music.yandex.";

	interface Listener {
		/** Token, or null when closed without one. Called once. */
		void onResult(String token);
	}

	private final WebView webView;
	private final ProgressBar progress;
	private final LinearLayout root;
	private final Listener listener;
	private boolean fired = false;

	AuthWebView(Context ctx, String url, Listener listener) {
		this.listener = listener;

		root = new LinearLayout(ctx);
		root.setOrientation(LinearLayout.VERTICAL);
		root.setBackgroundColor(isNight(ctx) ? Color.rgb(0x1e, 0x1e, 0x22) : Color.WHITE);

		progress = new ProgressBar(ctx, null, android.R.attr.progressBarStyleHorizontal);
		progress.setMax(100);
		progress.setIndeterminate(false);
		root.addView(progress, new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

		webView = new WebView(ctx);
		WebSettings s = webView.getSettings();
		s.setJavaScriptEnabled(true);
		s.setDomStorageEnabled(true);
		CookieManager.getInstance().setAcceptCookie(true);
		root.addView(webView, new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

		webView.setWebChromeClient(new WebChromeClient() {
			@Override public void onProgressChanged(WebView view, int newProgress) {
				progress.setProgress(newProgress);
				progress.setVisibility(newProgress >= 100 ? View.GONE : View.VISIBLE);
			}
		});

		webView.setWebViewClient(new WebViewClient() {
			@Override
			public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
				return intercept(request.getUrl());
			}

			@Override
			public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
				intercept(Uri.parse(url));
			}

			// Fragment-only and history.pushState navigations skip the two
			// callbacks above; this one sees every URL change.
			@Override
			public void doUpdateVisitedHistory(WebView view, String url, boolean isReload) {
				intercept(Uri.parse(url));
			}

			@Override
			public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
				if (request.isForMainFrame()) {
					Toast.makeText(ctx, error.getDescription(), Toast.LENGTH_LONG).show();
					finish(null);
				}
			}
		});

		webView.loadUrl(url);
	}

	View getView() {
		return root;
	}

	private boolean intercept(Uri uri) {
		if (uri == null || fired) return false;
		String host = uri.getHost();
		String fragment = uri.getFragment();
		if (host != null && host.contains(REDIRECT_HOST) && fragment != null && !fragment.isEmpty()) {
			String token = extractToken(fragment);
			if (token != null) {
				finish(token);
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

	/** Reports the result once; safe to call from any close path. */
	void finish(String token) {
		if (fired) return;
		fired = true;
		listener.onResult(token);
	}

	void destroy() {
		finish(null);
		webView.destroy();
	}

	static boolean isNight(Context ctx) {
		int mode = ctx.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK;
		return mode == Configuration.UI_MODE_NIGHT_YES;
	}

	/**
	 * System bars in the page's own colours: Yandex ID follows the system
	 * theme, so dark bars with light icons at night, white with dark icons
	 * by day. Without this the runtime's grey bar showed light-on-light.
	 */
	static void styleWindow(Window window, Context ctx) {
		boolean night = isNight(ctx);
		int background = night ? Color.rgb(0x1e, 0x1e, 0x22) : Color.WHITE;
		window.setStatusBarColor(background);
		window.setNavigationBarColor(background);
		WindowInsetsController c = window.getInsetsController();
		if (c != null) {
			int light = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
			c.setSystemBarsAppearance(night ? 0 : light, light);
		}
	}

	/** Full-screen dialog over the given activity; back closes it without a token. */
	static Dialog showDialog(Activity activity, String url, Listener listener) {
		Dialog dialog = new Dialog(activity, isNight(activity)
				? android.R.style.Theme_DeviceDefault_NoActionBar
				: android.R.style.Theme_DeviceDefault_Light_NoActionBar);
		AuthWebView view = new AuthWebView(activity, url, token -> {
			listener.onResult(token);
			if (dialog.isShowing()) dialog.dismiss();
		});
		dialog.setContentView(view.getView());
		dialog.setOnDismissListener(d -> view.destroy());
		Window w = dialog.getWindow();
		if (w != null) {
			w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
			styleWindow(w, activity);
		}
		dialog.show();
		return dialog;
	}
}
