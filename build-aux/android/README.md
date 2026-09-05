# Cassette on Android

Built with [pixiewood](https://github.com/sp1ritCS/gtk-android-builder) (GTK Android
Builder): one meson/ninja pass compiles the whole GTK stack plus Cassette into
`libcassette.so`, Gradle wraps it into an APK with the Java glue from GTK.

## What is platform-specific

| Piece | Desktop | Android |
|---|---|---|
| Stream playback | `GstPlayerBackend` (playbin) | `AndroidPlayerBackend` → `src/android/android-player.c` → `PlayerBridge.java` (MediaPlayer, audio focus) |
| External control | MPRIS (D-Bus) / macOS Now Playing | `src/android/now-playing.vala` → `android-now-playing.c` → `SessionBridge.java` (MediaSession) + `PlaybackService.java` (foreground service, notification) |
| Sign-in | WebKitGTK / WKWebView | `AuthWebView.java` (WebView as a dialog over the running activity; `AuthActivity` fallback) via `android-auth.c`, or manual token entry |
| TLS | GIO module | glib-networking (openssl) linked statically, registered in `main.vala` |

The Vala side is gated with `#if ANDROID`; `PlayerBackend` (`src/client/player/backend.vala`)
is the only contract the queue logic sees.

## Files

* `space.rirusha.Cassette.xml` — pixiewood manifest (dependencies, configure options, icon).
* `android.mk` — `prepare → generate → patch → build`, plus `android-sign`.
* `patch-android-project.py` — permissions, `CassetteApplication`, service and auth
  activity in the generated `AndroidManifest.xml`, and our Java sources; pixiewood has no
  hook for any of it.
* `java/space/rirusha/cassette/` — Java bridges, copied into the generated project.
* `subprojects/` — wraps pixiewood does not carry (libsoup, openssl, json-glib, libgee,
  sqlite3, glib-networking, libpsl, nghttp2). Copied into `subprojects/` at build time.
* `fonts/Inter/` — static Inter (SIL OFL), the UI font; installed to `share/fonts`, wired
  up by `android_setup_fonts` in `src/main.vala` (own fonts.conf via `FONTCONFIG_FILE`).
* `vapi/` — `libadwaita-1` and `libsoup-3.0` vapi snapshots: those come from the libraries,
  not from vala, and cannot be generated in a cross build.
* `Dockerfile` — build image on top of `matras-android-build` (adds valac 0.56.19 and
  blueprint-compiler).
* `docker-build.sh` — runs the whole thing in the container.

## Build

```sh
build-aux/android/docker-build.sh release=1
# unsigned APK in .pixiewood/android/app/build/outputs/apk/release/
apksigner sign --ks dev.keystore --ks-pass pass:... --in ...-release-unsigned.apk --out cassette.apk
adb install -r cassette.apk
adb logcat -s Cassette:V GLib:V Gtk:V
```

Only `arm64-v8a` is built. Translations (`i18n` install tag) are not packed yet.
