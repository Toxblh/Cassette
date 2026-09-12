#!/usr/bin/env python3
"""Post-processes the Android project that `pixiewood generate` wrote.

pixiewood has no hooks for either: the manifest comes from a fixed XSLT
(permissions, application class, no services) and only org/gtk/android is
symlinked into the Java sources. Both are patched here, between `generate`
and `build`; `build` does not regenerate them.

usage: patch-android-project.py <path/to/.pixiewood/android> <path/to/build-aux/android>
"""
import math
import re
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

    # Android Auto / Android Automotive media source: the car binds this
    # MediaBrowserService. The androidx.car.app.launchable meta-data is the
    # opt-in the car's MediaUtils checks (the built-in players carry it too).
    if app.find("service[@%s='space.rirusha.cassette.CassetteAutoService']" % a("name")) is None:
        auto = ET.SubElement(app, "service")
        auto.set(a("name"), "space.rirusha.cassette.CassetteAutoService")
        auto.set(a("exported"), "true")
        auto.set(a("foregroundServiceType"), "mediaPlayback")
        auto_filter = ET.SubElement(auto, "intent-filter")
        auto_action = ET.SubElement(auto_filter, "action")
        auto_action.set(a("name"), "android.media.browse.MediaBrowserService")
        auto_optin = ET.SubElement(auto, "meta-data")
        auto_optin.set(a("name"), "androidx.car.app.launchable")
        auto_optin.set(a("value"), "true")

    if app.find("meta-data[@%s='com.google.android.gms.car.application']" % a("name")) is None:
        car = ET.SubElement(app, "meta-data")
        car.set(a("name"), "com.google.android.gms.car.application")
        car.set(a("resource"), "@xml/automotive_app_desc")

    # Cover art for Android Auto items (the car does not render an http icon).
    if app.find("provider[@%s='space.rirusha.cassette.CassetteImageProvider']" % a("name")) is None:
        prov = ET.SubElement(app, "provider")
        prov.set(a("name"), "space.rirusha.cassette.CassetteImageProvider")
        prov.set(a("authorities"), "space.rirusha.cassette.images")
        prov.set(a("exported"), "true")
        prov.set(a("grantUriPermissions"), "true")

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
    for needle in ["CassetteApplication", "PlaybackService", "CassetteAutoService", "CassetteImageProvider", "AuthActivity", "FOREGROUND_SERVICE_MEDIA_PLAYBACK"]:
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


# ── the app's own symbolic icons → Android VectorDrawable ───────────────
# The car cannot render the GTK symbolic icons the phone UI uses, and the
# MediaBrowserService can run with no window (so no Gdk.Display to rasterise
# through). Convert the very SVGs the phone UI shows into VectorDrawables at
# build time; the browse tree then points at `builtin:<icon-name>` and the
# framework draws them headlessly.
#
# Only the subset the icons actually use is supported: `<path>` with
# fill/stroke (fill and stroke are painted white for the dark car UI), no
# transforms/masks/gradients. Anything else is skipped with a warning.

ICON_SVG_DIRS = ["data/assets/icons"]
# The phone UI's Playlists page icon is a GTK built-in, not an app asset.
EXTRA_ICON_SVGS = ["subprojects/gtk/gtk/icons/view-list-symbolic.svg"]


def _svg_prop(node, name):
    for part in (node.get("style") or "").split(";"):
        if ":" in part:
            key, value = part.split(":", 1)
            if key.strip() == name:
                return value.strip()
    return node.get(name)


def _svg_paint(value, default):
    # SVG defaults an absent fill to black (drawn) but an absent stroke to none.
    if value is None:
        return default
    return value.strip() not in ("none", "transparent", "")


def _svg_number(value, fallback):
    if value is None:
        return fallback
    digits = "".join(c for c in value if c.isdigit() or c in ".-")
    try:
        return float(digits)
    except ValueError:
        return fallback


def svg_to_vector(svg: Path):
    root = ET.parse(str(svg)).getroot()
    for node in root.iter():
        tag = node.tag.split("}")[-1]
        if tag in ("mask", "clipPath", "filter", "feColorMatrix"):
            raise ValueError(tag)
        if node.get("mask") or node.get("filter") or node.get("clip-path"):
            raise ValueError("mask/filter/clip")

    view = root.get("viewBox")
    if view:
        parts = view.replace(",", " ").split()
        view_w, view_h = parts[2], parts[3]
    else:
        view_w = (root.get("width") or "16").replace("px", "")
        view_h = (root.get("height") or "16").replace("px", "")

    def transform_group(transform):
        attrs = {}
        for name, args in re.findall(r"(\w+)\s*\(([^)]*)\)", transform):
            vals = [float(x) for x in re.split(r"[\s,]+", args.strip()) if x]
            if name == "translate":
                attrs["translateX"] = vals[0]
                if len(vals) > 1:
                    attrs["translateY"] = vals[1]
            elif name == "scale":
                attrs["scaleX"] = vals[0]
                attrs["scaleY"] = vals[1] if len(vals) > 1 else vals[0]
            elif name == "rotate":
                attrs["rotation"] = vals[0]
                if len(vals) == 3:
                    attrs["pivotX"], attrs["pivotY"] = vals[1], vals[2]
            elif name == "matrix":
                ma, mb, mc, md, me, mf = vals
                if abs(ma * mc + mb * md) > 1e-6:
                    raise ValueError("skew")
                attrs["scaleX"], attrs["scaleY"] = math.hypot(ma, mb), math.hypot(mc, md)
                rotation = math.degrees(math.atan2(mb, ma))
                if abs(rotation) > 1e-6:
                    attrs["rotation"] = rotation
                attrs["translateX"], attrs["translateY"] = me, mf
            else:
                raise ValueError(name)
        return " ".join('android:%s="%s"' % kv for kv in attrs.items())

    def path_xml(d, fill, stroke, width, cap, join, rule):
        attrs = ['android:fillColor="%s"' % ("#FFFFFFFF" if _svg_paint(fill, True) else "#00000000")]
        if _svg_paint(stroke, False):
            attrs.append('android:strokeColor="#FFFFFFFF"')
            attrs.append('android:strokeWidth="%s"' % _svg_number(width, 1))
            if cap in ("butt", "round", "square"):
                attrs.append('android:strokeLineCap="%s"' % cap)
            if join in ("miter", "round", "bevel"):
                attrs.append('android:strokeLineJoin="%s"' % join)
        if rule == "evenodd":
            attrs.append('android:fillType="evenOdd"')
        attrs.append('android:pathData="%s"' % " ".join(d.split()))
        return "<path %s/>" % " ".join(attrs)

    def walk(node, fill, stroke, width, cap, join, rule):
        tag = node.tag.split("}")[-1]
        if tag in ("defs", "mask", "clipPath", "filter", "metadata",
                   "namedview", "title", "style"):
            return []
        fill = _svg_prop(node, "fill") if _svg_prop(node, "fill") is not None else fill
        stroke = _svg_prop(node, "stroke") if _svg_prop(node, "stroke") is not None else stroke
        width = _svg_prop(node, "stroke-width") if _svg_prop(node, "stroke-width") is not None else width
        cap = _svg_prop(node, "stroke-linecap") if _svg_prop(node, "stroke-linecap") is not None else cap
        join = _svg_prop(node, "stroke-linejoin") if _svg_prop(node, "stroke-linejoin") is not None else join
        rule = _svg_prop(node, "fill-rule") if _svg_prop(node, "fill-rule") is not None else rule
        inner = []
        if tag == "path" and node.get("d"):
            inner.append(path_xml(node.get("d"), fill, stroke, width, cap, join, rule))
        for child in node:
            inner += walk(child, fill, stroke, width, cap, join, rule)
        transform = node.get("transform")
        if transform and inner:
            return ["<group %s>" % transform_group(transform)] + inner + ["</group>"]
        return inner

    body = walk(root, None, None, None, None, None, None)

    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="24dp" android:height="24dp"\n'
        '    android:viewportWidth="%s" android:viewportHeight="%s">\n'
        '%s\n</vector>\n' % (
            view_w, view_h,
            "\n".join("    " + line for line in body))
    )


def icon_drawables(repo: Path):
    drawables = {}
    sources = []
    for rel in ICON_SVG_DIRS:
        sources += sorted((repo / rel).glob("*.svg"))
    sources += [repo / rel for rel in EXTRA_ICON_SVGS]
    skipped = 0
    for svg in sources:
        try:
            drawables[svg.stem.replace("-", "_")] = svg_to_vector(svg)
        except Exception as e:  # noqa: BLE001 - a bad icon must not break the build
            skipped += 1
            print("icon skip %s: %s" % (svg.name, e))
    print("app icons: %d vector drawables (%d skipped)" % (len(drawables), skipped))
    return drawables


# The app's symbolic icon (data/icons/hicolor/symbolic/apps), 128-unit viewport:
# small icon of the playback notification.
APP_ICON_PATH = 'm 87.881025,25.414537 -0.08467,25.581112 c -2.058067,-0.904518 -2.333344,-1.231737 -4.663391,-1.231737 -4.396049,0 -8.272223,2.219328 -10.574961,5.596672 h -17.22569 c -2.302677,-3.37776 -6.180156,-5.596672 -10.576523,-5.596672 -7.065057,0 -12.792392,5.727416 -12.792392,12.792393 0,0.08841 0.0045,0.175921 0.0062,0.263905 -8e-4,0.04569 -0.0062,0.08997 -0.0062,0.135857 0,0.39027 0.03849,0.77021 0.09526,1.144632 0.762726,6.33657 6.154947,11.247998 12.697136,11.247998 4.039035,0 7.638706,-1.873598 9.983126,-4.797147 h 18.417172 c 2.344474,2.921953 5.939127,4.797147 9.97688,4.797147 6.562651,0 11.971002,-4.942078 12.706512,-11.307338 0.051,-0.355512 0.0859,-0.715663 0.0859,-1.085292 0,-0.0306 -0.004,-0.06006 -0.005,-0.09057 2.5e-4,-0.01047 0.002,-0.02076 0.002,-0.03123 l 0.003,-0.0016 0.165819,-23.038278 c 0.01902,-2.64258 3.153364,-2.992175 4.125587,-2.275354 2.4373,1.797021 2.00397,1.640305 4.46291,3.815139 1.59273,1.408705 4.39962,1.363921 5.90041,-0.13548 l 5.04867,-5.968826 c 1.56009,-1.65952 1.52912,-4.088687 -0.18408,-5.631605 -11.62162,-10.466501 -14.41553,-12.007212 -20.071842,-11.957859 -3.886208,0.03391 -7.475676,2.89258 -7.491833,7.774135 z M 20.204593,30.814453 C 13.619504,30.814453 8,36.313343 8,42.527453 v 56.059692 c 0,5.542365 6.07697,12.227305 12.159056,12.227305 h 87.742084 c 6.34673,0 12.09886,-5.76826 12.09886,-11.741979 0.0564,-15.969425 0.0899,-26.500348 0.0215,-42.469892 0,-4.043991 -2.46364,-7.009322 -6.08265,-7.099454 -3.96264,-0.09869 -6.60078,3.361201 -6.60078,7.282921 v 17.882499 c 0,4.746335 -3.14976,8.128278 -8.000008,8.132789 l -70.511817,0.0641 c -4.524458,0.0041 -8.518618,-3.372632 -8.518618,-8.530675 V 63 52.017797 c 0,-4.571992 4.203362,-8.677178 8.599983,-8.677178 h 42.84548 c 3.227152,0.01218 6.047376,-2.728628 6.047376,-6.595782 -0.002,-3.705975 -2.893705,-5.930384 -6.077738,-5.930384 z m 6.757124,57.519709 c 3.58197,3.12e-4 6.485221,2.904807 6.484,6.486777 -3.1e-4,3.580885 -2.903115,6.483681 -6.484,6.483991 -3.581969,8.9e-4 -6.486466,-2.902021 -6.486777,-6.483991 -0.0012,-3.583055 2.903723,-6.487999 6.486777,-6.486777 z m 73.568923,0.08269 c 3.6351,3.15e-4 6.58184,2.947063 6.58216,6.582158 -3.2e-4,3.635093 -2.94706,6.58183 -6.58216,6.58215 -3.636184,8.9e-4 -6.584657,-2.945957 -6.584975,-6.58215 3.18e-4,-3.636196 2.948791,-6.583397 6.584975,-6.582158 z m -24.797484,3.166992 c 3.695995,-0.0012 6.692949,2.994412 6.69327,6.690408 -3.18e-4,3.695998 -2.997272,6.691658 -6.69327,6.690408 -3.694879,-3.2e-4 -6.69009,-2.99552 -6.690408,-6.690408 3.22e-4,-3.694877 2.995532,-6.690086 6.690408,-6.690408 z m -23.673101,0.02864 c 3.695995,3.2e-4 6.691667,2.997276 6.690407,6.693271 -3.23e-4,3.694875 -2.995531,6.690075 -6.690407,6.690395 -3.695994,8.9e-4 -6.692949,-2.99441 -6.69327,-6.690395 -0.0012,-3.697115 2.996156,-6.694532 6.69327,-6.693271 z'

def write_drawables(res: Path, repo: Path):
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
    for name, vector in icon_drawables(repo).items():
        (d / (name + ".xml")).write_text(vector)
    print("drawables: %d" % (len(DRAWABLES) + 1))


def copy_java(src: Path, dst: Path):
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dst, dirs_exist_ok=True)
    n = len(list(dst.rglob("*.java")))
    print("java: %d files under %s" % (n, dst))


# Android Auto / Automotive opt-in: the app declares itself as a media source.
def write_automotive_xml(res: Path):
    d = res / "xml"
    d.mkdir(parents=True, exist_ok=True)
    (d / "automotive_app_desc.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<automotiveApp>\n'
        '    <uses name="media" />\n'
        '</automotiveApp>\n')
    print("automotive xml: ok")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    project = Path(sys.argv[1])
    aux = Path(sys.argv[2])
    repo = aux.resolve().parent.parent
    patch_manifest(project / "app/src/main/AndroidManifest.xml")
    copy_java(aux / "java", project / "app/src/main/java")
    write_bars_colors(project / "app/src/main/res")
    write_drawables(project / "app/src/main/res", repo)
    write_automotive_xml(project / "app/src/main/res")


if __name__ == "__main__":
    main()
