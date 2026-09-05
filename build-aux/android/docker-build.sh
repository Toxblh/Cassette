#!/usr/bin/env bash
# Builds the Android APK inside the cassette-android-build image.
#
#   build-aux/android/docker-build.sh            # debug APK
#   build-aux/android/docker-build.sh release=1  # unsigned release APK
#   build-aux/android/docker-build.sh -- bash    # a shell in the container
#
# The image derives from matras-android-build (see Dockerfile); pixiewood and
# mini-studio are taken from the Matras checkout next to this repository.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/../.." && pwd)"
MATRAS="${MATRAS_ANDROID:-$HOME/git/matras-android}"
IMAGE="${IMAGE:-cassette-android-build:latest}"

if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
  echo "==> image $IMAGE missing, building (needs matras-android-build:latest)"
  docker build --platform linux/amd64 -t "$IMAGE" "$HERE/build-aux/android/"
fi

# blueprint-compiler needs current Gtk/Adw typelibs, which only the host has.
# The .ui files go to build-aux/android/ui and data/meson.build copies them.
echo "==> compiling blueprints on the host"
make -C "$HERE" -f build-aux/android/android.mk android-blueprints

run() {
  docker run --rm --platform linux/amd64 \
    -v "$HERE:/work/cassette" \
    -v "$MATRAS/pixiewood:/work/pixiewood:ro" \
    -v "$MATRAS/mini-studio:/work/mini-studio:ro" \
    -v matras-gradle:/root/.gradle \
    -w /work/cassette \
    "$IMAGE" "$@"
}

if [ "${1:-}" = "--" ]; then
  shift
  exec docker run --rm -it --platform linux/amd64 \
    -v "$HERE:/work/cassette" \
    -v "$MATRAS/pixiewood:/work/pixiewood:ro" \
    -v "$MATRAS/mini-studio:/work/mini-studio:ro" \
    -v matras-gradle:/root/.gradle \
    -w /work/cassette \
    "$IMAGE" "$@"
fi

run bash -lc "set -o pipefail; make -f build-aux/android/android.mk android $*"
