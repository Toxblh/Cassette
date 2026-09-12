package space.rirusha.cassette;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.net.Uri;
import android.os.ParcelFileDescriptor;

import java.io.File;
import java.io.FileOutputStream;
import java.io.FileNotFoundException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.List;

/**
 * Serves cover art and built-in icons to Android Auto. The car does not
 * render an http icon URI on a MediaItem, so the browse tree points at
 * content:// URIs here and the car fetches them itself.
 *
 *   content://space.rirusha.cassette.images/url/<encoded https url>
 *   content://space.rirusha.cassette.images/builtin/<drawable name>
 *
 * Only Yandex image hosts are allowed for remote URLs.
 */
public class CassetteImageProvider extends ContentProvider {
	public static final String AUTHORITY = "space.rirusha.cassette.images";

	@Override
	public boolean onCreate() {
		return true;
	}

	@Override
	public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
		List<String> segments = uri.getPathSegments();
		if (segments.size() < 2) {
			throw new FileNotFoundException("bad path");
		}
		File file;
		if ("builtin".equals(segments.get(0))) {
			file = builtinFile(segments.get(1));
		} else {
			String url = segments.get(1);
			if (!allowed(url)) {
				throw new FileNotFoundException("host not allowed");
			}
			file = new File(getContext().getCacheDir(), cacheName(url));
			if (!file.exists() || file.length() == 0) {
				download(url, file);
			}
		}
		return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
	}

	@Override
	public String getType(Uri uri) {
		List<String> segments = uri.getPathSegments();
		return segments.size() > 0 && "builtin".equals(segments.get(0)) ? "image/png" : "image/jpeg";
	}

	/** Rasterise one of the app's vector drawables (built-in tab icons). */
	private File builtinFile(String name) throws FileNotFoundException {
		File file = new File(getContext().getCacheDir(), "builtin-" + name + ".png");
		if (file.exists() && file.length() > 0) {
			return file;
		}
		int id = getContext().getResources().getIdentifier(name, "drawable", getContext().getPackageName());
		Drawable drawable = id == 0 ? null : getContext().getDrawable(id);
		if (drawable == null) {
			throw new FileNotFoundException("no drawable " + name);
		}
		int size = 128;
		Bitmap bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
		Canvas canvas = new Canvas(bitmap);
		drawable.setBounds(0, 0, size, size);
		drawable.draw(canvas);
		try (FileOutputStream out = new FileOutputStream(file)) {
			bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
		} catch (Exception e) {
			throw new FileNotFoundException("drawable write failed: " + e);
		}
		return file;
	}

	private static boolean allowed(String url) {
		if (url == null || !url.startsWith("https://")) {
			return false;
		}
		String host;
		try {
			host = new URL(url).getHost();
		} catch (Exception e) {
			return false;
		}
		return host != null && (host.endsWith(".yandex.net") || host.endsWith(".yandex.ru")
				|| host.endsWith(".yandex.com") || host.endsWith(".yandex.net.ru"));
	}

	private static String cacheName(String url) {
		try {
			MessageDigest digest = MessageDigest.getInstance("SHA-1");
			byte[] hash = digest.digest(url.getBytes("UTF-8"));
			StringBuilder builder = new StringBuilder();
			for (byte b : hash) {
				builder.append(String.format("%02x", b));
			}
			return builder.toString() + ".img";
		} catch (Exception e) {
			return Integer.toHexString(url.hashCode()) + ".img";
		}
	}

	private void download(String url, File file) throws FileNotFoundException {
		try {
			HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
			connection.setConnectTimeout(5000);
			connection.setReadTimeout(5000);
			int code = connection.getResponseCode();
			if (code != 200) {
				connection.disconnect();
				throw new Exception("http " + code);
			}
			File temp = new File(file.getParentFile(), file.getName() + ".part");
			try (InputStream in = connection.getInputStream();
			     FileOutputStream out = new FileOutputStream(temp)) {
				byte[] buffer = new byte[8192];
				int n;
				while ((n = in.read(buffer)) > 0) {
					out.write(buffer, 0, n);
				}
			}
			connection.disconnect();
			if (!temp.renameTo(file)) {
				throw new Exception("rename failed");
			}
		} catch (Exception e) {
			throw new FileNotFoundException("cover failed: " + e);
		}
	}

	// Not a database: nothing else to implement.

	@Override public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) { return null; }
	@Override public Uri insert(Uri uri, ContentValues values) { return null; }
	@Override public int delete(Uri uri, String selection, String[] selectionArgs) { return 0; }
	@Override public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) { return 0; }
}
