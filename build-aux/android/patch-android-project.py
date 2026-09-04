#!/usr/bin/env python3
"""Post-processes the Android project that `pixiewood generate` wrote.

pixiewood has no hooks for either: the manifest comes from a fixed XSLT
(permissions, application class, no services) and only org/gtk/android is
symlinked into the Java sources. Both are patched here, between `generate`
and `build`; `build` does not regenerate them.

usage: patch-android-project.py <path/to/.pixiewood/android> <path/to/build-aux/android>
"""
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID)
ET.register_namespace("android-tools", "http://schemas.android.com/tools")


def a(name):
    return "{%s}%s" % (ANDROID, name)


PERMISSIONS = [
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",  # API 34+
    "android.permission.WAKE_LOCK",
    "android.permission.POST_NOTIFICATIONS",                 # API 33+, media notification
]


def patch_manifest(path: Path):
    tree = ET.parse(path)
    root = tree.getroot()
    app = root.find("application")
    if app is None:
        sys.exit("no <application> in %s" % path)

    app.set(a("name"), "space.rirusha.cassette.CassetteApplication")
    # the OAuth token lives in the app-private database
    app.set(a("allowBackup"), "false")

    if root.find("uses-permission[@%s='android.permission.INTERNET']" % a("name")) is None:
        sys.exit("INTERNET permission missing: metainfo needs <requires><internet>always</internet></requires>")

    for perm in PERMISSIONS:
        if root.find("uses-permission[@%s='%s']" % (a("name"), perm)) is None:
            el = ET.SubElement(root, "uses-permission")
            el.set(a("name"), perm)

    if app.find("service") is None:
        svc = ET.SubElement(app, "service")
        svc.set(a("name"), "space.rirusha.cassette.PlaybackService")
        svc.set(a("foregroundServiceType"), "mediaPlayback")
        svc.set(a("exported"), "false")

    if app.find("activity[@%s='space.rirusha.cassette.AuthActivity']" % a("name")) is None:
        act = ET.SubElement(app, "activity")
        act.set(a("name"), "space.rirusha.cassette.AuthActivity")
        act.set(a("exported"), "false")
        act.set(a("configChanges"), "orientation|screenSize|keyboardHidden")

    ET.indent(tree, space="    ")
    tree.write(path, encoding="utf-8", xml_declaration=True)

    text = path.read_text()
    for needle in ["CassetteApplication", "PlaybackService", "AuthActivity", "FOREGROUND_SERVICE_MEDIA_PLAYBACK"]:
        if needle not in text:
            sys.exit("manifest patch failed: %s missing" % needle)
    print("manifest: ok (%s)" % path)


# Colours painted under the status bar (top) and navigation bar (bottom) by
# the patched GTK glue (patches/gtk-android-bars-colors.patch): libadwaita's
# raised header bar and window background, light and dark.
BARS_COLORS = {
    "values": {"gtk_bars_top": "#ffffff", "gtk_bars_bottom": "#fafafb"},
    "values-night": {"gtk_bars_top": "#2e2e32", "gtk_bars_bottom": "#222226"},
}


def write_bars_colors(res: Path):
    for qualifier, colors in BARS_COLORS.items():
        d = res / qualifier
        d.mkdir(parents=True, exist_ok=True)
        body = "".join('    <color name="%s">%s</color>\n' % kv for kv in colors.items())
        (d / "gtk_bars.xml").write_text('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n%s</resources>\n' % body)
    print("bars colours: ok")


def copy_java(src: Path, dst: Path):
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dst, dirs_exist_ok=True)
    n = len(list(dst.rglob("*.java")))
    print("java: %d files under %s" % (n, dst))


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    project = Path(sys.argv[1])
    aux = Path(sys.argv[2])
    patch_manifest(project / "app/src/main/AndroidManifest.xml")
    copy_java(aux / "java", project / "app/src/main/java")
    write_bars_colors(project / "app/src/main/res")


if __name__ == "__main__":
    main()
