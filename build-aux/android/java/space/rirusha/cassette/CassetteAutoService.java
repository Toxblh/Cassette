package space.rirusha.cassette;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.media.MediaDescription;
import android.media.browse.MediaBrowser;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.service.media.MediaBrowserService;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Android Auto / Android Automotive media source. The browse tree and the
 * play commands come from native (android-auto.c -> auto-browser.vala): Java
 * turns the JSON into MediaItems, hands the session token to the car, and
 * forwards play commands.
 *
 * Cover art is an icon URI to CassetteImageProvider. Android Auto lists
 * (playable) rows load that URI, but the car's tab bar is drawn from the
 * description's bitmap, so browsable items (the root tabs) also carry the
 * icon as a Bitmap.
 *
 * The MediaSession itself is the one SessionBridge already keeps for the lock
 * screen and notification; this service just publishes it to Android Auto.
 */
public class CassetteAutoService extends MediaBrowserService {
	private static final String TAG = "CassetteAuto";
	private static Context appContext;

	private static final Handler main = new Handler(Looper.getMainLooper());
	private static final AtomicLong nextRequest = new AtomicLong();
	private static final Map<Long, Result<List<MediaBrowser.MediaItem>>> pending =
			new ConcurrentHashMap<>();

	private static native void nativeBrowse(String parentId, long requestId);
	private static native void nativePlayMediaId(String mediaId);
	private static native void nativePlayFromSearch(String query);

	@Override
	public void onCreate() {
		super.onCreate();
		appContext = getApplicationContext();
		SessionBridge.ensureSession();
		setSessionToken(SessionBridge.token());
	}

	@Override
	public BrowserRoot onGetRoot(String clientPackageName, int clientUid, Bundle rootHints) {
		// Any client may connect; the car is the only one in practice.
		return new BrowserRoot("root", null);
	}

	@Override
	public void onLoadChildren(String parentId, Result<List<MediaBrowser.MediaItem>> result) {
		long requestId = nextRequest.incrementAndGet();
		result.detach();
		pending.put(requestId, result);
		nativeBrowse(parentId == null ? "root" : parentId, requestId);
	}

	/** Called from native with a JSON array of items; may run off the UI thread. */
	static void deliverBrowse(final long requestId, final String json) {
		final Result<List<MediaBrowser.MediaItem>> result = pending.remove(requestId);
		if (result == null) {
			return;
		}

		final List<MediaBrowser.MediaItem> items = new ArrayList<>();
		try {
			JSONArray array = new JSONArray(json);
			for (int i = 0; i < array.length(); i++) {
				JSONObject o = array.getJSONObject(i);
				MediaDescription.Builder d = new MediaDescription.Builder()
						.setMediaId(o.getString("id"))
						.setTitle(o.optString("title"))
						.setSubtitle(o.optString("subtitle"));
				String icon = o.optString("icon", "");
				boolean playable = o.optBoolean("playable", false);
				if (!icon.isEmpty()) {
					String path;
					if (icon.startsWith("builtin:")) {
						path = "builtin/" + icon.substring("builtin:".length());
					} else {
						path = "url/" + Uri.encode(icon);
					}
					d.setIconUri(Uri.parse("content://" + CassetteImageProvider.AUTHORITY + "/" + path));
					// The car tab bar is drawn from the bitmap, not the URI.
					if (!playable && icon.startsWith("builtin:")) {
						Bitmap bitmap = builtinBitmap(icon.substring("builtin:".length()));
						if (bitmap != null) {
							d.setIconBitmap(bitmap);
						}
					}
				}
				int flags = playable
						? MediaBrowser.MediaItem.FLAG_PLAYABLE
						: MediaBrowser.MediaItem.FLAG_BROWSABLE;
				items.add(new MediaBrowser.MediaItem(d.build(), flags));
			}
		} catch (Exception e) {
			Log.w(TAG, "browse json failed", e);
		}

		main.post(() -> result.sendResult(items));
	}

	/** Called from SessionBridge's MediaSession callback (main thread). */
	static void playMediaId(String mediaId) { nativePlayMediaId(mediaId); }
	static void playFromSearch(String query) { nativePlayFromSearch(query); }

	/** Rasterise one of the app's vector drawables for the car tab bar. */
	private static Bitmap builtinBitmap(String name) {
		if (appContext == null) {
			return null;
		}
		String resource = name.replace('-', '_');
		int id = appContext.getResources().getIdentifier(resource, "drawable", appContext.getPackageName());
		Drawable drawable = id == 0 ? null : appContext.getDrawable(id);
		if (drawable == null) {
			return null;
		}
		int size = 128;
		int inset = size / 8;
		Bitmap bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
		Canvas canvas = new Canvas(bitmap);
		drawable.setBounds(inset, inset, size - inset, size - inset);
		drawable.draw(canvas);
		return bitmap;
	}
}
