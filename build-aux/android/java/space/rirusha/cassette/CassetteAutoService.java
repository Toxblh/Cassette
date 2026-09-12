package space.rirusha.cassette;

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
 * Cover art is an icon URI to CassetteImageProvider (the car will not render
 * an http icon URI, and ignores a bitmap).
 *
 * The MediaSession itself is the one SessionBridge already keeps for the lock
 * screen and notification; this service just publishes it to Android Auto.
 */
public class CassetteAutoService extends MediaBrowserService {
	private static final String TAG = "CassetteAuto";

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
		final List<String> covers = new ArrayList<>();
		try {
			JSONArray array = new JSONArray(json);
			for (int i = 0; i < array.length(); i++) {
				JSONObject o = array.getJSONObject(i);
				MediaDescription.Builder d = new MediaDescription.Builder()
						.setMediaId(o.getString("id"))
						.setTitle(o.optString("title"))
						.setSubtitle(o.optString("subtitle"));
				String icon = o.optString("icon", "");
				if (!icon.isEmpty()) {
					String path;
					if (icon.startsWith("builtin:")) {
						path = "builtin/" + icon.substring("builtin:".length());
					} else {
						path = "url/" + Uri.encode(icon);
						covers.add(icon);
					}
					d.setIconUri(Uri.parse("content://" + CassetteImageProvider.AUTHORITY + "/" + path));
				}
				int flags = o.optBoolean("playable", false)
						? MediaBrowser.MediaItem.FLAG_PLAYABLE
						: MediaBrowser.MediaItem.FLAG_BROWSABLE;
				items.add(new MediaBrowser.MediaItem(d.build(), flags));
			}
		} catch (Exception e) {
			Log.w(TAG, "browse json failed", e);
		}

		main.post(() -> result.sendResult(items));

		// Warm the cover cache in the background so scrolling the list does
		// not wait for a download per row.
		if (!covers.isEmpty()) {
			final android.content.Context context = NativeContext.get();
			new Thread(() -> {
				for (String url : covers) {
					CassetteImageProvider.prefetch(context, url);
				}
			}, "cassette-covers").start();
		}
	}

	/** Called from SessionBridge's MediaSession callback (main thread). */
	static void playMediaId(String mediaId) { nativePlayMediaId(mediaId); }
	static void playFromSearch(String query) { nativePlayFromSearch(query); }
}
