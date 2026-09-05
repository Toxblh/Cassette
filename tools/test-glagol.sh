#!/bin/bash
# Compile and run the Glagol CLI test tool.
# Usage: ./tools/test-glagol.sh <host> [token]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GLAGOL_DIR="$ROOT_DIR/src/client/glagol"

SOURCES=(
    "$GLAGOL_DIR/glagol-device.vala"
    "$GLAGOL_DIR/device-discovery.vala"
    "$GLAGOL_DIR/device-token-provider.vala"
    "$GLAGOL_DIR/glagol-client.vala"
    "$SCRIPT_DIR/test-glagol.vala"
)

OUT="/tmp/test-glagol"

echo "Compiling..."
valac \
    -X -DGETTEXT_PACKAGE=\"cassette\" \
    --pkg gee-0.8 \
    --pkg glib-2.0 \
    --pkg gobject-2.0 \
    --pkg json-glib-1.0 \
    --pkg libsoup-3.0 \
    --pkg gio-2.0 \
    --target-glib=2.76 \
    -o "$OUT" \
    "${SOURCES[@]}"

echo "Running: $OUT $*"
exec "$OUT" "$@"
