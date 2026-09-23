#!/bin/sh
# Build an arm64 APK in the Forgejo node:22-trixie Linux/amd64 container.
set -eu

export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
export ANDROID_HOME=/opt/android-sdk ANDROID_SDK_ROOT=/opt/android-sdk
ndk_version=27.2.12479018
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/$ndk_version"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/36.0.0:$PATH"

apt-get update
apt-get install -y --no-install-recommends \
  libglib-perl libglib-object-introspection-perl libipc-run-perl \
  libjson-perl libset-scalar-perl libxml-libxml-perl libxml-libxslt-perl \
  gir1.2-appstream-1.0 gir1.2-gtk-4.0 gir1.2-adw-1 \
  openjdk-17-jdk-headless build-essential glslc gobject-introspection \
  libglib2.0-dev libglib2.0-dev-bin libxml2-utils ninja-build sassc gettext \
  pkg-config cmake git curl wget unzip ca-certificates python3 python3-pip \
  python3-gi xz-utils valac blueprint-compiler
python3 -m pip install --break-system-packages --no-cache-dir meson==1.12.0

# valac checks --target-glib against host pkg-config, while Meson links the
# newer GLib built as a subproject. Give only valac the cross-build version.
mkdir -p /opt/vala-pc
printf 'Name: glib-2.0\nDescription: valac cross-build version\nVersion: 2.88.0\n' \
  > /opt/vala-pc/glib-2.0.pc
cat > /usr/local/bin/valac <<'VALAC'
#!/bin/sh
export PKG_CONFIG_PATH="/opt/vala-pc${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
exec /usr/bin/valac "$@"
VALAC
chmod +x /usr/local/bin/valac

# GLib's flag enums need the new glib-mkenums parser during the GTK build.
curl -fsSL https://raw.githubusercontent.com/GNOME/glib/main/gobject/glib-mkenums.in \
  | sed -e 's/@VERSION@/2.89.4/' -e 's|@PYTHON@|/usr/bin/python3|' \
  > /usr/bin/glib-mkenums
chmod +x /usr/bin/glib-mkenums

mkdir -p "$ANDROID_HOME/cmdline-tools"
curl -fsSL -o /tmp/cassette-cmdline.zip \
  https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip
unzip -q /tmp/cassette-cmdline.zip -d /tmp
mv /tmp/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"
rm /tmp/cassette-cmdline.zip
yes | sdkmanager --licenses > /dev/null 2>&1 || true
sdkmanager --install 'platform-tools' 'platforms;android-36' \
  'build-tools;36.0.0' "ndk;$ndk_version"

mkdir -p /opt/cassette-tools
git clone -q https://github.com/sp1ritCS/gtk-android-builder.git /opt/cassette-tools/pixiewood
git -C /opt/cassette-tools/pixiewood checkout -q de3719725a8f6e3efe0f28203e803e7ce1904902
git clone -q https://github.com/sp1ritCS/mini-studio.git /opt/cassette-tools/mini-studio
git -C /opt/cassette-tools/mini-studio checkout -q 8c2901968b07245ad07c1b38270928a49a510765

make -f build-aux/android/android.mk android-blueprints
make -f build-aux/android/android.mk android release=1 \
  PIXIEWOOD=/opt/cassette-tools/pixiewood/pixiewood \
  ANDROID_STUDIO=/opt/cassette-tools/mini-studio \
  ANDROID_SDK="$ANDROID_HOME" ANDROID_NDK="$ANDROID_NDK_HOME"

mkdir -p apks
source_apk=.pixiewood/android/app/build/outputs/apk/release/app-arm64-v8a-release-unsigned.apk
cp "$source_apk" apks/Cassette-arm64-v8a-release-unsigned.apk

if [ -n "${ANDROID_KEYSTORE_B64:-}${ANDROID_KEYSTORE_PASSWORD:-}${ANDROID_KEY_ALIAS:-}" ]; then
  : "${ANDROID_KEYSTORE_B64:?missing Android keystore}"
  : "${ANDROID_KEYSTORE_PASSWORD:?missing Android keystore password}"
  : "${ANDROID_KEY_ALIAS:?missing Android key alias}"
  printf '%s' "$ANDROID_KEYSTORE_B64" | base64 -d > /tmp/cassette-release.jks
  apksigner sign --ks /tmp/cassette-release.jks \
    --ks-key-alias "$ANDROID_KEY_ALIAS" \
    --ks-pass env:ANDROID_KEYSTORE_PASSWORD \
    --out apks/Cassette-arm64-v8a-release-signed.apk "$source_apk"
  rm -f /tmp/cassette-release.jks apks/*.idsig
fi
