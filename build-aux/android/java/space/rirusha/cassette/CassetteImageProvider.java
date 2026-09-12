package space.rirusha.cassette;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;

import java.io.File;
import java.io.FileOutputStream;
import java.io.FileNotFoundException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;

/**
 * Serves cover art to Android Auto. The car does not render an http icon URI
 * on a MediaItem, so the browse tree points at content:// URIs here and the
 * car fetches them itself. Only Yandex image hosts are allowed.
 */
public class CassetteImageProvider extends ContentProvider {
	public static final String AUTHORITY = "space.rirusha.cassette.images";

	@Override
	public boolean onCreate() {
		return true;
	}

	@Override
	public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
		String encoded = uri.getLastPathSegment();
		if (encoded == null) {
			throw new FileNotFoundException("no url");
		}
		String url = Uri.decode(encoded);
		if (!allowed(url)) {
			throw new FileNotFoundException("host not allowed");
		}
		try {
			File file = new File(getContext().getCacheDir(), cacheName(url));
			if (!file.exists() || file.length() == 0) {
				download(url, file);
			}
			return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
		} catch (Exception e) {
			throw new FileNotFoundException("cover failed: " + e);
		}
	}

	@Override
	public String getType(Uri uri) {
		return "image/jpeg";
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

	private static void download(String url, File file) throws Exception {
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
	}

	// Not a database: nothing else to implement.

	@Override public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) { return null; }
	@Override public Uri insert(Uri uri, ContentValues values) { return null; }
	@Override public int delete(Uri uri, String selection, String[] selectionArgs) { return 0; }
	@Override public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) { return 0; }
}
