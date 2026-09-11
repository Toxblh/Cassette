#!/bin/sh
# Bundle Cassette as a distribution .ipa for TestFlight.
# Usage: package-cassette-testflight.sh [builddir]
#
# Expects the release build from setup-cassette-release.sh and a distribution
# identity from fastlane `cert`. Env:
#   IOS_DIST_CERT          codesign identity ("Apple Distribution: ...")
#   IOS_MARKETING_VERSION  CFBundleShortVersionString   (default 0.2.4)
#   IOS_BUILD_NUMBER       CFBundleVersion, unique       (default timestamp)
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
BUILD=${1:-$ROOT/build-ios-release}
BUILD="$(cd "$BUILD" && pwd)"
APP="$BUILD/Cassette.app"
STAGE="$BUILD/stage"
IPA="$BUILD/Cassette.ipa"
BUNDLE_ID=space.rirusha.cassette
TEAM_ID=VZ5Q5CVRUL
APP_ID_PREFIX=DCQJFSH9BA
CERT="${IOS_DIST_CERT:?set IOS_DIST_CERT to the Apple Distribution identity}"
VERSION="${IOS_MARKETING_VERSION:-0.2.4}"
BUILD_NUMBER="${IOS_BUILD_NUMBER:-$(date +%Y%m%d%H%M%S)}"

rm -rf "$STAGE" "$APP" "$BUILD/Payload" "$IPA"
DESTDIR="$STAGE" meson install -C "$BUILD" --no-rebuild --quiet
mkdir -p "$APP/Frameworks" "$APP/etc"
cp "$BUILD/src/cassette" "$APP/Cassette"
cp -R "$STAGE/usr/share" "$APP/share"
glib-compile-schemas "$APP/share/glib-2.0/schemas"
[ -d "$STAGE/etc" ] && cp -R "$STAGE/etc/." "$APP/etc/"
[ -d "$STAGE/usr/etc" ] && cp -R "$STAGE/usr/etc/." "$APP/etc/"
# The staged fontconfig conf.d entries are symlinks into the /usr prefix that
# do not survive the bundle layout. fontconfig config is written at runtime
# (main.vala), so drop the broken links rather than ship them to App Store.
find "$APP" -type l ! -exec test -e {} \; -delete
cp /etc/ssl/cert.pem "$APP/cacert.pem"

# GTK must live in Frameworks/ for App Store validation (a dylib next to the
# executable trips "invalid bundle"). The dylib id is already @rpath/...
cp "$BUILD/subprojects/gtk/gtk/libgtk-4.1.dylib" "$APP/Frameworks/"
install_name_tool -id @rpath/libgtk-4.1.dylib "$APP/Frameworks/libgtk-4.1.dylib"
# Drop the build-tree rpath (it points outside the bundle), add Frameworks/.
install_name_tool -delete_rpath @loader_path/../subprojects/gtk/gtk "$APP/Cassette" 2>/dev/null || true
install_name_tool -add_rpath @executable_path/Frameworks "$APP/Cassette"

cat > "$APP/Info.plist" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleExecutable</key><string>Cassette</string>
<key>CFBundleName</key><string>Cassette</string>
<key>CFBundleDisplayName</key><string>Cassette</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>LSRequiresIPhoneOS</key><true/>
<key>UILaunchScreen</key><dict/>
<key>UIBackgroundModes</key><array><string>audio</string></array>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
<key>ITSAppUsesNonExemptEncryption</key><false/>
<key>UISupportedInterfaceOrientations</key><array>
  <string>UIInterfaceOrientationPortrait</string>
  <string>UIInterfaceOrientationLandscapeLeft</string>
  <string>UIInterfaceOrientationLandscapeRight</string>
</array>
<key>UIViewControllerBasedStatusBarAppearance</key><true/>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>CFBundleIcons</key><dict><key>CFBundlePrimaryIcon</key><dict><key>CFBundleIconFiles</key><array><string>AppIcon60x60</string></array><key>CFBundleIconName</key><string>AppIcon</string></dict></dict>
<key>CFBundleIcons~ipad</key><dict><key>CFBundlePrimaryIcon</key><dict><key>CFBundleIconFiles</key><array><string>AppIcon60x60</string><string>AppIcon76x76</string></array><key>CFBundleIconName</key><string>AppIcon</string></dict></dict>
</dict></plist>
XML

# App icon (asset catalog -> Assets.car + legacy .png variants)
xcrun actool "$HERE/assets" --compile "$APP" \
  --platform iphoneos --minimum-deployment-target 17.0 \
  --app-icon AppIcon --output-partial-info-plist "$BUILD/actool-icon.plist" \
  --target-device iphone --target-device ipad >/dev/null

# TestFlight needs beta-reports-active; distribution needs get-task-allow off.
# The provisioning profile is not embedded (App Store builds never embed it).
cat > "$APP/Entitlements.plist" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>application-identifier</key>
	<string>$APP_ID_PREFIX.$BUNDLE_ID</string>
	<key>com.apple.developer.team-identifier</key>
	<string>$TEAM_ID</string>
	<key>beta-reports-active</key>
	<true/>
	<key>get-task-allow</key>
	<false/>
</dict>
</plist>
XML

codesign --force --sign "$CERT" --timestamp "$APP/Frameworks/libgtk-4.1.dylib"
codesign --force --sign "$CERT" --entitlements "$APP/Entitlements.plist" \
  --timestamp --generate-entitlement-der "$APP"

mkdir -p "$BUILD/Payload"
cp -R "$APP" "$BUILD/Payload/"
ditto -c -k --sequesterRsrc --keepParent "$BUILD/Payload" "$IPA"
rm -rf "$BUILD/Payload"

echo "packaged $IPA (version $VERSION, build $BUILD_NUMBER)"
