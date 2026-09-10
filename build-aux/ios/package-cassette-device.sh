#!/bin/sh
# Bundle Cassette for a real iPhone and install it via devicectl.
# Usage: package-cassette-device.sh [builddir] [device udid]
# Signing identity / profile come from the environment (see ios README):
#   IOS_DEV_CERT    codesign identity (defaults to the author's)
#   IOS_DEV_PROFILE path to the development .mobileprovision
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
BUILD=${1:-$ROOT/build-ios-device}
UDID=${2:-00008140-000E048111E0801C}
APP="$BUILD/Cassette.app"
STAGE="$BUILD/stage"
BUNDLE_ID=space.rirusha.cassette
CERT="${IOS_DEV_CERT:-Apple Development: Pavel Subach (P84QNSJRGS)}"
PROFILE="${IOS_DEV_PROFILE:?set IOS_DEV_PROFILE to the .mobileprovision path}"

rm -rf "$STAGE" "$APP"
DESTDIR="$STAGE" meson install -C "$BUILD" --no-rebuild --quiet
mkdir -p "$APP"
cp "$BUILD/src/cassette" "$APP/Cassette"
cp -R "$STAGE/usr/share" "$APP/share"
glib-compile-schemas "$APP/share/glib-2.0/schemas"
[ -d "$STAGE/usr/etc" ] && cp -R "$STAGE/usr/etc" "$APP/etc"
cp "$BUILD/subprojects/gtk/gtk/libgtk-4.1.dylib" "$APP/"
install_name_tool -add_rpath @executable_path "$APP/Cassette" 2>/dev/null || true
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

cp "$PROFILE" "$APP/embedded.mobileprovision"

cat > "$APP/Entitlements.plist" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>application-identifier</key>
	<string>DCQJFSH9BA.space.rirusha.cassette</string>
	<key>com.apple.developer.team-identifier</key>
	<string>VZ5Q5CVRUL</string>
	<key>get-task-allow</key>
	<true/>
</dict>
</plist>
XML

codesign --force --sign "$CERT" --timestamp=none "$APP/libgtk-4.1.dylib"
codesign --force --sign "$CERT" --entitlements "$APP/Entitlements.plist" --timestamp=none --generate-entitlement-der "$APP"

echo "signed $APP"
xcrun devicectl device install app --device "$UDID" "$APP"
