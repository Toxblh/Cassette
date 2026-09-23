#!/bin/sh
# Install pinned wraps and the iOS changes to GTK, GLib and libadwaita.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)

mkdir -p "$ROOT/subprojects/packagefiles/glib" "$ROOT/subprojects/packagefiles/pcre2"
cp "$HERE"/wraps/*.wrap "$ROOT/subprojects/"
cp "$HERE"/wraps/packagefiles/*.patch "$ROOT/subprojects/packagefiles/"
cp "$HERE"/wraps/packagefiles/glib/*.patch "$ROOT/subprojects/packagefiles/glib/"
cp "$HERE"/wraps/packagefiles/pcre2/*.patch "$ROOT/subprojects/packagefiles/pcre2/"

meson subprojects download --sourcedir "$ROOT" gtk glib libadwaita

apply_patch() {
    subproject=$1
    patch=$2
    checkout="$ROOT/subprojects/$subproject"
    if git -C "$checkout" apply --reverse --check "$patch" 2>/dev/null; then
        echo "$subproject: iOS patch already applied"
    else
        git -C "$checkout" apply --check "$patch"
        git -C "$checkout" apply "$patch"
        echo "$subproject: iOS patch applied"
    fi
}

apply_patch gtk "$HERE/patches/0001-gtk-ios-backend.patch"
apply_patch glib "$HERE/patches/0002-glib-ios-undeclared-functions.patch"
apply_patch libadwaita "$HERE/patches/0003-libadwaita-ios.patch"
