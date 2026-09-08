#!/bin/sh
# Bundle the hello binary as Hello.app, install it in the booted simulator and launch it.
# Usage: package-hello.sh [builddir] [simulator udid|booted]
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD=${1:-$HERE/../../build-ios-hello}
UDID=${2:-booted}
APP="$BUILD/Hello.app"
BUNDLE_ID=space.rirusha.hello

rm -rf "$APP"
mkdir -p "$APP/fonts"
cp "$BUILD/hello" "$APP/Hello"
# GTK itself is the only shared library; everything else is static inside it.
cp "$BUILD/subprojects/gtk/gtk/libgtk-4.1.dylib" "$APP/"
install_name_tool -add_rpath @executable_path "$APP/Hello" 2>/dev/null || true
cp "$HERE"/../android/fonts/Inter/*.ttf "$APP/fonts/"

cat > "$APP/fonts.conf" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir prefix="relative">fonts</dir>
  <cachedir prefix="xdg">fontconfig</cachedir>
  <alias><family>sans-serif</family><prefer><family>Inter</family></prefer></alias>
  <alias><family>Cantarell</family><prefer><family>Inter</family></prefer></alias>
  <alias><family>Adwaita Sans</family><prefer><family>Inter</family></prefer></alias>
</fontconfig>
XML

cat > "$APP/Info.plist" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleExecutable</key><string>Hello</string>
<key>CFBundleName</key><string>GTK Hello</string>
<key>CFBundleDisplayName</key><string>GTK Hello</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>LSRequiresIPhoneOS</key><true/>
<key>UILaunchScreen</key><dict/>
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
