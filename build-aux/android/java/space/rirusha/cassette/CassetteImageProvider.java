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
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Serves cover art and built-in icons to Android Auto. The car does not
 * render an http icon URI on a MediaItem, so the browse tree points at
 * content:// URIs here.
 *
 *   content://space.rirusha.cassette.images/url/<encoded https url>
 *   content://space.rirusha.cassette.images/builtin/<drawable name>
 *
 * An uncached cover is streamed through a pipe and downloaded on a worker
 * thread, so openFile() returns at once and a fast scroll never waits on the
 * network (the same idea as the iOS cover loader). The bytes are cached on
 * the way through, so the next request is a plain file.
 *
 * Only Yandex image hosts are allowed.
 */
public class CassetteImageProvider extends ContentProvider {
	public static final String AUTHORITY = "space.rirusha.cassette.images";

	// A fast fling can ask for a hundred covers at once; a bounded pool keeps
	// the downloads from spawning a thread each and starving the device.
	private static final ExecutorService POOL = Executors.newFixedThreadPool(5);

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

		if ("builtin".equals(segments.get(0))) {
			return ParcelFileDescriptor.open(builtinFile(segments.get(1)),
					ParcelFileDescriptor.MODE_READ_ONLY);
		}

		String url = segments.get(1);
		if (!allowed(url)) {
			throw new FileNotFoundException("host not allowed");
		}
		File file = new File(getContext().getCacheDir(), cacheName(url));
		if (file.exists() && file.length() > 0) {
			return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
		}
		return stream(url, file);
	}

	@Override
	public String getType(Uri uri) {
		List<String> segments = uri.getPathSegments();
		return segments.size() > 0 && "builtin".equals(segments.get(0)) ? "image/png" : "image/jpeg";
	}

	/** Download to the reader as it arrives, caching the bytes on the way. */
	private ParcelFileDescriptor stream(String url, File file) throws FileNotFoundException {
		try {
			ParcelFileDescriptor[] pipe = ParcelFileDescriptor.createPipe();
			ParcelFileDescriptor read = pipe[0];
			ParcelFileDescriptor write = pipe[1];

			POOL.execute(() -> {
				File temp = new File(file.getParentFile(), file.getName() + ".part");
				boolean complete = false;
				try (ParcelFileDescriptor.AutoCloseOutputStream out =
						     new ParcelFileDescriptor.AutoCloseOutputStream(write);
				     FileOutputStream cache = new FileOutputStream(temp)) {
					HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
					connection.setConnectTimeout(8000);
					connection.setReadTimeout(15000);
					int code = connection.getResponseCode();
					if (code == 200) {
						try (InputStream in = connection.getInputStream()) {
							byte[] buffer = new byte[8192];
							int n;
							while ((n = in.read(buffer)) > 0) {
								out.write(buffer, 0, n);
								cache.write(buffer, 0, n);
							}
						}
						complete = true;
					}
					connection.disconnect();
				} catch (Exception ignored) {
					// the reader just sees a short/empty stream
				} finally {
					if (complete) {
						temp.renameTo(file);
					} else {
						temp.delete();
					}
				}
			});

			return read;
		} catch (IOException e) {
			throw new FileNotFoundException("pipe failed: " + e);
		}
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

	// Not a database: nothing else to implement.

	@Override public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) { return null; }
	@Override public Uri insert(Uri uri, ContentValues values) { return null; }
	@Override public int delete(Uri uri, String selection, String[] selectionArgs) { return 0; }
	@Override public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) { return 0; }
}
