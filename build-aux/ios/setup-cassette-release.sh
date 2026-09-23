#!/bin/sh
# Configure Cassette for an arm64 iOS release build (TestFlight/App Store).
# Usage: setup-cassette-release.sh [builddir]
# Reuses the device cross setup, overriding only the build type.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
BUILD=${1:-$ROOT/build-ios-release}
if [ -f "$BUILD/meson-private/coredata.dat" ]; then
    exec meson setup --reconfigure "$BUILD"
fi
IOS_BUILDTYPE=release exec "$HERE/setup-cassette-device.sh" "$BUILD"
