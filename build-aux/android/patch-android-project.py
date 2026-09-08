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
        # No action bar: the runtime's default theme drew a light title on a light bar.
        act.set(a("theme"), "@android:style/Theme.DeviceDefault.DayNight")
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


# Heart icons for the "like" custom action of the media session
# (Material Symbols "favorite" / "favorite_border", Apache-2.0).
DRAWABLES = {
    "cassette_like": "M16.5,3c-1.74,0 -3.41,0.81 -4.5,2.09C10.91,3.81 9.24,3 7.5,3 4.42,3 2,5.42 2,8.5c0,3.78 3.4,6.86 8.55,11.54L12,21.35l1.45,-1.32C18.6,15.36 22,12.28 22,8.5 22,5.42 19.58,3 16.5,3zM12.1,18.55l-0.1,0.1 -0.1,-0.1C7.14,14.24 4,11.39 4,8.5 4,6.5 5.5,5 7.5,5c1.54,0 3.04,0.99 3.57,2.36h1.87C13.46,5.99 14.96,5 16.5,5c2,0 3.5,1.5 3.5,3.5 0,2.89 -3.14,5.74 -7.9,10.05z",
    "cassette_liked": "M12,21.35l-1.45,-1.32C5.4,15.36 2,12.28 2,8.5 2,5.42 4.42,3 7.5,3c1.74,0 3.41,0.81 4.5,2.09C13.09,3.81 14.76,3 16.5,3 19.58,3 22,5.42 22,8.5c0,3.78 -3.4,6.86 -8.55,11.54L12,21.35z",
    # Material "shuffle" (Apache 2.0); the "on" variant adds a dot underneath.
    "cassette_shuffle": "M10.59,9.17L5.41,4 4,5.41l5.17,5.17 1.42,-1.41zM14.5,4l2.04,2.04L4,18.59 5.41,20 17.96,7.46 20,9.5V4h-5.5zm0.33,9.41l-1.41,1.41 3.13,3.13L14.5,20H20v-5.5l-2.04,2.04 -3.13,-3.13z",
    "cassette_shuffle_on": "M10.59,9.17L5.41,4 4,5.41l5.17,5.17 1.42,-1.41zM14.5,4l2.04,2.04L4,18.59 5.41,20 17.96,7.46 20,9.5V4h-5.5zm0.33,9.41l-1.41,1.41 3.13,3.13L14.5,20H20v-5.5l-2.04,2.04 -3.13,-3.13zM12,21.5a1.5,1.5 0 1,0 0.01,0z",
}


# The app's symbolic icon (data/icons/hicolor/symbolic/apps), 128-unit viewport:
# small icon of the playback notification.
APP_ICON_PATH = 'm 87.881025,25.414537 -0.08467,25.581112 c -2.058067,-0.904518 -2.333344,-1.231737 -4.663391,-1.231737 -4.396049,0 -8.272223,2.219328 -10.574961,5.596672 h -17.22569 c -2.302677,-3.37776 -6.180156,-5.596672 -10.576523,-5.596672 -7.065057,0 -12.792392,5.727416 -12.792392,12.792393 0,0.08841 0.0045,0.175921 0.0062,0.263905 -8e-4,0.04569 -0.0062,0.08997 -0.0062,0.135857 0,0.39027 0.03849,0.77021 0.09526,1.144632 0.762726,6.33657 6.154947,11.247998 12.697136,11.247998 4.039035,0 7.638706,-1.873598 9.983126,-4.797147 h 18.417172 c 2.344474,2.921953 5.939127,4.797147 9.97688,4.797147 6.562651,0 11.971002,-4.942078 12.706512,-11.307338 0.051,-0.355512 0.0859,-0.715663 0.0859,-1.085292 0,-0.0306 -0.004,-0.06006 -0.005,-0.09057 2.5e-4,-0.01047 0.002,-0.02076 0.002,-0.03123 l 0.003,-0.0016 0.165819,-23.038278 c 0.01902,-2.64258 3.153364,-2.992175 4.125587,-2.275354 2.4373,1.797021 2.00397,1.640305 4.46291,3.815139 1.59273,1.408705 4.39962,1.363921 5.90041,-0.13548 l 5.04867,-5.968826 c 1.56009,-1.65952 1.52912,-4.088687 -0.18408,-5.631605 -11.62162,-10.466501 -14.41553,-12.007212 -20.071842,-11.957859 -3.886208,0.03391 -7.475676,2.89258 -7.491833,7.774135 z M 20.204593,30.814453 C 13.619504,30.814453 8,36.313343 8,42.527453 v 56.059692 c 0,5.542365 6.07697,12.227305 12.159056,12.227305 h 87.742084 c 6.34673,0 12.09886,-5.76826 12.09886,-11.741979 0.0564,-15.969425 0.0899,-26.500348 0.0215,-42.469892 0,-4.043991 -2.46364,-7.009322 -6.08265,-7.099454 -3.96264,-0.09869 -6.60078,3.361201 -6.60078,7.282921 v 17.882499 c 0,4.746335 -3.14976,8.128278 -8.000008,8.132789 l -70.511817,0.0641 c -4.524458,0.0041 -8.518618,-3.372632 -8.518618,-8.530675 V 63 52.017797 c 0,-4.571992 4.203362,-8.677178 8.599983,-8.677178 h 42.84548 c 3.227152,0.01218 6.047376,-2.728628 6.047376,-6.595782 -0.002,-3.705975 -2.893705,-5.930384 -6.077738,-5.930384 z m 6.757124,57.519709 c 3.58197,3.12e-4 6.485221,2.904807 6.484,6.486777 -3.1e-4,3.580885 -2.903115,6.483681 -6.484,6.483991 -3.581969,8.9e-4 -6.486466,-2.902021 -6.486777,-6.483991 -0.0012,-3.583055 2.903723,-6.487999 6.486777,-6.486777 z m 73.568923,0.08269 c 3.6351,3.15e-4 6.58184,2.947063 6.58216,6.582158 -3.2e-4,3.635093 -2.94706,6.58183 -6.58216,6.58215 -3.636184,8.9e-4 -6.584657,-2.945957 -6.584975,-6.58215 3.18e-4,-3.636196 2.948791,-6.583397 6.584975,-6.582158 z m -24.797484,3.166992 c 3.695995,-0.0012 6.692949,2.994412 6.69327,6.690408 -3.18e-4,3.695998 -2.997272,6.691658 -6.69327,6.690408 -3.694879,-3.2e-4 -6.69009,-2.99552 -6.690408,-6.690408 3.22e-4,-3.694877 2.995532,-6.690086 6.690408,-6.690408 z m -23.673101,0.02864 c 3.695995,3.2e-4 6.691667,2.997276 6.690407,6.693271 -3.23e-4,3.694875 -2.995531,6.690075 -6.690407,6.690395 -3.695994,8.9e-4 -6.692949,-2.99441 -6.69327,-6.690395 -0.0012,-3.697115 2.996156,-6.694532 6.69327,-6.693271 z'

def write_drawables(res: Path):
    d = res / "drawable"
    d.mkdir(parents=True, exist_ok=True)
    for name, path in DRAWABLES.items():
        (d / (name + ".xml")).write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">\n'
            '    <path android:fillColor="#FFFFFFFF" android:pathData="%s"/>\n'
            '</vector>\n' % path)
    (d / "cassette_symbolic.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="24dp" android:height="24dp" android:viewportWidth="128" android:viewportHeight="128">\n'
        '    <path android:fillColor="#FFFFFFFF" android:pathData="%s"/>\n'
        '</vector>\n' % APP_ICON_PATH)
    print("drawables: %d" % (len(DRAWABLES) + 1))


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
    write_drawables(project / "app/src/main/res")


if __name__ == "__main__":
    main()
