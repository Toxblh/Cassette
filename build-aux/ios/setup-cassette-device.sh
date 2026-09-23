#!/bin/sh
# Configure Cassette for the iOS simulator. Usage: setup-cassette.sh [builddir] [extra meson args]
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
BUILD=${1:-$ROOT/build-ios-device}
shift 2>/dev/null || true
export PKG_CONFIG_LIBDIR=/nonexistent
cd "$ROOT"
"$HERE/prepare-subprojects.sh"
mkdir -p "$BUILD"
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
sed "s|^sdk = .*|sdk = '$sdk'|" "$HERE/ios-device-arm64.cross" > "$BUILD/ios-device-arm64.cross"
exec meson setup "$BUILD" --cross-file "$BUILD/ios-device-arm64.cross" \
 --prefix /usr -Dbuildtype="${IOS_BUILDTYPE:-debugoptimized}" -Ddefault_library=static \
 -Dwith_webkit=false \
 -Dgtk:ios-backend=true -Dgtk:macos-backend=false -Dgtk:x11-backend=false -Dgtk:wayland-backend=false -Dgtk:broadway-backend=false \
 -Dgtk:media-gstreamer=disabled -Dgtk:print-cups=disabled -Dgtk:vulkan=disabled -Dgtk:build-demos=false -Dgtk:build-testsuite=false -Dgtk:build-examples=false -Dgtk:build-tests=false -Dgtk:introspection=disabled -Dgtk:documentation=false -Dgtk:sysprof=disabled \
 -Dlibadwaita:examples=false -Dlibadwaita:tests=false -Dlibadwaita:introspection=disabled -Dlibadwaita:documentation=false -Dlibadwaita:vapi=false \
 -Dglib:tests=false -Dglib:introspection=disabled -Dglib:glib_debug=disabled \
 -Dharfbuzz:tests=disabled -Dharfbuzz:docs=disabled -Dharfbuzz:introspection=disabled -Dharfbuzz:coretext=disabled -Dharfbuzz:icu=disabled \
 -Dcairo:tests=disabled -Dcairo:quartz=disabled -Dcairo:fontconfig=enabled -Dcairo:freetype=enabled \
 -Dpango:fontconfig=enabled -Dpango:introspection=disabled \
 -Dfontconfig:tests=disabled -Dfontconfig:doc=disabled \
 -Dgdk-pixbuf:introspection=disabled -Dgdk-pixbuf:man=false -Dgdk-pixbuf:tests=false -Dgdk-pixbuf:installed_tests=false \
 -Dgraphene:introspection=disabled -Dgraphene:tests=false \
 -Dfreetype2:brotli=disabled -Dfreetype2:harfbuzz=disabled -Dfreetype2:bzip2=disabled \
 -Dlibepoxy:tests=false -Dlibepoxy:glx=no -Dlibepoxy:egl=no -Dlibepoxy:x11=false \
 -Dpixman:openmp=disabled -Dpixman:tests=disabled -Dpixman:demos=disabled \
 -Djson-glib:documentation=disabled -Djson-glib:gtk_doc=disabled -Djson-glib:tests=false -Djson-glib:conformance=false -Djson-glib:installed_tests=false -Djson-glib:introspection=disabled \
 -Dlibsoup:tls_check=true -Dlibsoup:tests=false -Dlibsoup:docs=disabled -Dlibsoup:introspection=disabled -Dlibsoup:vapi=disabled -Dlibsoup:sysprof=disabled \
 -Dlibgee:tests=disabled -Dlibgee:disable-introspection=true \
 -Dglib-networking:gnome_proxy=disabled -Dglib-networking:environment_proxy=disabled -Dglib-networking:gnutls=disabled -Dglib-networking:openssl=enabled -Dglib-networking:libproxy=disabled -Dglib-networking:default_library=static \
 "$@"
