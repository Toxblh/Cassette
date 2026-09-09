# Cassette on iOS: experimental

GTK has no iOS backend, so this directory carries one plus the build flow
that gets a GTK 4 app into the iPhone simulator. State of things: Cassette
runs in the simulator with a signed-in session (stations, playlists,
artwork, search, playback through AVPlayer, Russian UI, on-screen
keyboard); the WKWebView sign-in opens but was not driven to the end.
Not done: real devices (signing), app icon, media keys/lock screen
(MPRemoteCommandCenter is wired but untested), background audio checks,
GL rendering, clipboard.

## Layout

- `ios-simulator-arm64.cross`: meson cross file (arm64 simulator, iOS 17+).
  Regenerate the SDK path with `xcrun --sdk iphonesimulator --show-sdk-path`.
- `setup-hello.sh`, `package-hello.sh`: configure/build the hello app,
  bundle it as `Hello.app` (binary, `libgtk-4.1.dylib`, Inter fonts,
  `fonts.conf`), install into the simulator.
- `hello/`: the app; `hello/subprojects` links to the repo's subprojects,
  so the same GTK/GLib checkouts serve Android and iOS.
- `patches/`: the GDK iOS backend as a patch against `subprojects/gtk`
  (branch `ios-backend` in that checkout) and a small GLib fix.

## The backend (`subprojects/gtk/gdk/ios`)

- UIKit owns the main thread; GTK runs on its own thread
  (`gdk_ios_main (argc, argv, app_main)`). GTK → UIKit work goes through
  `dispatch_sync/async` on the main queue; UIKit → GTK through
  `g_idle_add` (never `g_main_context_invoke`, which may run inline).
- Every `GdkSurface` is a `GdkIosSurfaceView`. Toplevels fill the root view;
  popups are subviews placed by `gdk_surface_layout_popup_helper`.
- Drawing: cairo renderer only. `GdkIosCairoContext` keeps a persistent
  image buffer in device pixels (no cairo device scale: GdkCairoContext
  applies `cairo_scale` itself); `end_frame` copies it into a `CGImage`
  set as the layer's contents on the main thread.
- Input: `touchesBegan/…` → `gdk_touch_event_new`; the first finger
  emulates the pointer. A GDK grab (autohide popup) makes the root view's
  `hitTest:` return the grabbed view, so outside taps reach the popup.
- Keyboard: `GtkIMContextIos` (gtk/gtkimcontextios.c) + `gdkiostextinput.c`,
  a hidden `UIKeyInput` responder; typed text is committed, backspace and
  return become key events; the root view shrinks toplevels above the
  keyboard (safe area minus keyboard frame). `gdk_ios_set_bars_colors()`
  paints the status-bar and home-indicator strips.
- Missing: GL/Metal, clipboard, `CADisplayLink` frame pacing, real devices.

## Cassette

```sh
build-aux/ios/setup-cassette.sh          # meson setup build-ios (cross, static, all subprojects)
ninja -C build-ios
build-aux/ios/package-cassette.sh build-ios <udid>   # stage install → Cassette.app, simctl install
SIMCTL_CHILD_G_MESSAGES_DEBUG=space.rirusha.Cassette xcrun simctl launch <udid> space.rirusha.cassette
```

Platform pieces live in `src/ios` (`ios-runtime.m` environment shim,
`ios-player.m` AVPlayer, `ios-auth.m` WKWebView sheet) and the MediaPlayer
now-playing bridge is shared with macOS (`src/macos/macos-now-playing.m`).
`main.vala` enters through `gdk_ios_main`; `ios_setup` maps XDG dirs onto
the bundle (`share/`, `etc/`) and the container (Application Support,
Caches), loads the static OpenSSL GIO module and points OpenSSL at the
bundled `cacert.pem`. Static libadwaita must be force-loaded (its resource
registration is a constructor nothing references). Meson patches beyond
GTK: libadwaita (`patches/0003`, AppKit only on macOS, portal settings path
on iOS) and GLib (`patches/0002`).

To test with an existing session copy `~/.local/share/cassette/cassette.db`
(token in `additional.oauth_token`) into the container's
`Library/Application Support/cassette/share/cassette/` and set
`application-state='online'` in `.../cassette/config/glib-2.0/settings/keyfile`
(`xcrun simctl get_app_container <udid> space.rirusha.cassette data`).
Russian UI: `xcrun simctl spawn <udid> defaults write "Apple Global Domain" AppleLanguages -array ru en`.
`SIMCTL_CHILD_GDK_IOS_DEBUG_TYPE="ms:text"` types on the keyboard responder.

## Flow (hello app)

```sh
build-aux/ios/setup-hello.sh            # meson setup build-ios-hello
ninja -C build-ios-hello
xcrun simctl boot <udid>
build-aux/ios/package-hello.sh build-ios-hello <udid>
SIMCTL_CHILD_G_MESSAGES_DEBUG=all xcrun simctl launch <udid> space.rirusha.hello
xcrun simctl io <udid> screenshot shot.png
xcrun simctl spawn <udid> log show --last 1m --predicate 'process == "Hello"'
```

Do not launch with `--console-pty` and then kill simctl: the app dies with
it. GLib messages are mirrored to `NSLog`, so `log show` sees them.
`SIMCTL_CHILD_GDK_IOS_DEBUG_TAPS="x,y,ms;…"` synthesizes taps (points) for
checks without a hand on the simulator. Crash reports land in
`~/Library/Logs/DiagnosticReports/Hello-*.ips`.

Gotchas met on the way: `sassc` must be native (`brew install sassc`);
libepoxy/pixman tests and OpenMP are disabled in the cross build; the iOS
SDK links `pipe2` without declaring it (GLib patch); GTK's quartz color
picker was gated on `__APPLE__` (now `GDK_WINDOWING_MACOS`).
