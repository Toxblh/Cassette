#!/bin/sh
# Bundle Cassette as Cassette.app and install it in the simulator.
# Usage: package-cassette.sh [builddir] [simulator udid|booted]
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
BUILD=${1:-$ROOT/build-ios}
UDID=${2:-booted}
APP="$BUILD/Cassette.app"
STAGE="$BUILD/stage"
BUNDLE_ID=space.rirusha.cassette

rm -rf "$STAGE" "$APP"
DESTDIR="$STAGE" meson install -C "$BUILD" --no-rebuild --quiet
mkdir -p "$APP"
cp "$BUILD/src/cassette" "$APP/Cassette"
cp -R "$STAGE/usr/share" "$APP/share"
# the compiled schema file is what GSettings actually reads
glib-compile-schemas "$APP/share/glib-2.0/schemas"
[ -d "$STAGE/usr/etc" ] && cp -R "$STAGE/usr/etc" "$APP/etc"
# only libgtk is shared; the app and the rest are static
cp "$BUILD/subprojects/gtk/gtk/libgtk-4.1.dylib" "$APP/"
install_name_tool -add_rpath @executable_path "$APP/Cassette" 2>/dev/null || true
# Mozilla CA bundle for OpenSSL (macOS ships one)
cp /etc/ssl/cert.pem "$APP/cacert.pem"

cat > "$APP/Info.plist" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleExecutable</key><string>Cassette</string>
<key>CFBundleName</key><string>Cassette</string>
<key>CFBundleDisplayName</key><string>Cassette</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.2.4</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>LSRequiresIPhoneOS</key><true/>
<key>UILaunchScreen</key><dict/>
<key>UIBackgroundModes</key><array><string>audio</string></array>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
<key>UISupportedInterfaceOrientations</key><array>
  <string>UIInterfaceOrientationPortrait</string>
  <string>UIInterfaceOrientationLandscapeLeft</string>
  <string>UIInterfaceOrientationLandscapeRight</string>
</array>
<key>UIViewControllerBasedStatusBarAppearance</key><true/>
</dict></plist>
XML

codesign -s - --force --deep "$APP" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "installed $APP"
