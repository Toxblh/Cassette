#!/bin/sh
# Configure the hello app for the iOS simulator. Usage: setup-hello.sh <builddir>
set -e
cd "$(dirname "$0")/hello"
BUILD=${1:-$PWD/../../../build-ios-hello}
export PKG_CONFIG_LIBDIR=/nonexistent
exec meson setup "$BUILD" --cross-file ../ios-simulator-arm64.cross \
 -Dbuildtype=debugoptimized \
 -Dgtk:ios-backend=true -Dgtk:macos-backend=false -Dgtk:x11-backend=false -Dgtk:wayland-backend=false -Dgtk:broadway-backend=false \
 -Dgtk:media-gstreamer=disabled -Dgtk:print-cups=disabled -Dgtk:vulkan=disabled -Dgtk:build-demos=false -Dgtk:build-testsuite=false -Dgtk:build-examples=false -Dgtk:build-tests=false -Dgtk:introspection=disabled -Dgtk:documentation=false -Dgtk:sysprof=disabled \
 -Dglib:tests=false -Dglib:introspection=disabled -Dglib:glib_debug=disabled \
 -Dharfbuzz:tests=disabled -Dharfbuzz:docs=disabled -Dharfbuzz:introspection=disabled -Dharfbuzz:coretext=disabled -Dharfbuzz:icu=disabled \
 -Dcairo:tests=disabled -Dcairo:quartz=disabled -Dcairo:fontconfig=enabled -Dcairo:freetype=enabled \
 -Dpango:fontconfig=enabled -Dpango:introspection=disabled \
 -Dfontconfig:tests=disabled -Dfontconfig:doc=disabled \
 -Dgdk-pixbuf:introspection=disabled -Dgdk-pixbuf:man=false -Dgdk-pixbuf:tests=false -Dgdk-pixbuf:installed_tests=false \
 -Dgraphene:introspection=disabled -Dgraphene:tests=false \
 -Dfreetype2:brotli=disabled -Dfreetype2:harfbuzz=disabled -Dfreetype2:bzip2=disabled \
 -Dlibepoxy:tests=false -Dlibepoxy:glx=no -Dlibepoxy:egl=no -Dlibepoxy:x11=false \
 "$@"
