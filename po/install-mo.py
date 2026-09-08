#!/usr/bin/env python3
"""Copy po/<lang>/LC_MESSAGES/<domain>.mo from the build dir into
$MESON_INSTALL_DESTDIR_PREFIX/share/locale, for install runs that skip the
i18n install tag (pixiewood)."""
import glob, os, shutil
build = os.environ["MESON_BUILD_ROOT"]
dest = os.path.join(os.environ["MESON_INSTALL_DESTDIR_PREFIX"], "share", "locale")
n = 0
for mo in glob.glob(os.path.join(build, "po", "*", "LC_MESSAGES", "*.mo")):
    lang = os.path.basename(os.path.dirname(os.path.dirname(mo)))
    target = os.path.join(dest, lang, "LC_MESSAGES")
    os.makedirs(target, exist_ok=True)
    shutil.copy2(mo, target)
    n += 1
print("install-mo: %d catalogues -> %s" % (n, dest))
