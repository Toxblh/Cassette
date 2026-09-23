# Cassette on iOS: experimental

GTK has no iOS backend, so this directory carries one plus the build flow
that gets a GTK 4 app into the iPhone simulator. State of things: Cassette
runs in the simulator and on a real device (signed with a development
profile) with a signed-in session (stations, playlists, artwork, search,
playback through AVPlayer, Russian UI, on-screen keyboard, copy/paste);
the WKWebView sign-in opens but was not driven to the end. The app icon
is a layered asset catalog (`assets/`) with light/dark/tinted variants,
compiled by `actool` in the package scripts. Not done: media keys/lock
screen (MPRemoteCommandCenter is wired but untested), background audio
checks, GL rendering; App Store distribution has a TestFlight pipeline
(`fastlane`, below) that needs the App Store Connect app record and the
first upload.

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
- Clipboard: `gdkiosclipboard.c`, a `GdkClipboard` over
  `UIPasteboard`'s general pasteboard. It advertises text unconditionally
  (asking `hasStrings` would raise the iOS paste alert before the user
  pasted) and polls `changeCount` to notice content copied elsewhere.
  Reading triggers the system "allow paste" alert once per source.
- Missing: GL/Metal, `CADisplayLink` frame pacing, real devices.

## Cassette

`setup-cassette.sh` prepares the pinned wraps in `wraps/` and applies the
GTK, GLib and libadwaita patches on a clean checkout. The simulator SDK path
is read from the installed Xcode. GitHub Actions builds and uploads a
simulator `.app` archive; locally, set `CASSETTE_PACKAGE_ONLY=1` when running
`package-cassette.sh` to package without installing into a simulator. The
device and TestFlight scripts still require your Apple signing setup.

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

## TestFlight

Distribution builds reuse the device cross setup in release mode. One-time
setup in App Store Connect (the API key cannot create an app record):

1. Register the App ID `space.rirusha.cassette` (developer.apple.com →
   Identifiers) and create the app record (App Store Connect → My Apps → +,
   iOS, that bundle ID).
2. Put an App Store Connect API key (App Manager role) at
   `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` and set `ASC_KEY_ID`
   and `ASC_ISSUER_ID` in the gitignored `fastlane/.env`.

Then:

```sh
cd build-aux/ios
fastlane certs   # Apple Distribution cert + App Store profile (build/AppStore.mobileprovision)
fastlane beta    # release build → Cassette.ipa → upload to TestFlight
```

`package-cassette-testflight.sh` keeps GTK in `Frameworks/` (App Store
validation rejects a dylib next to the executable), signs with the
distribution identity and the `beta-reports-active` entitlement, and drops
the broken fontconfig symlinks the staged `/usr` prefix leaves behind. Bump
`IOS_MARKETING_VERSION`/`IOS_BUILD_NUMBER` per upload (the build number
defaults to a timestamp). External testers later need full metadata and Beta
App Review — a third-party Yandex client is a real guideline 5.2.1 rejection
risk; internal testers skip that.

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
checks without a hand on the simulator; an optional fourth field is the
hold duration in ms (`x,y,ms,hold`, e.g. for long-press selection
bubbles). `SIMCTL_CHILD_GDK_IOS_DEBUG_DRAGS="x1,y1,x2,y2,ms;…"`
synthesizes a touch drag after `ms` (scrolling checks). Crash reports land
in `~/Library/Logs/DiagnosticReports/Hello-*.ips`.

Gotchas met on the way: `sassc` must be native (`brew install sassc`);
libepoxy/pixman tests and OpenMP are disabled in the cross build; the iOS
SDK links `pipe2` without declaring it (GLib patch); GTK's quartz color
picker was gated on `__APPLE__` (now `GDK_WINDOWING_MACOS`).
