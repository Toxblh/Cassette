/* Copyright 2023-2024 Vladimir Vaskov
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#if ANDROID
[CCode (cname = "g_io_openssl_load")]
extern void g_io_openssl_load (IOModule? module);

/**
 * Process environment the GTK Android runtime does not provide.
 * Must run before anything touches GIO TLS, the cache dir or fonts.
 */
void android_setup () {
    // glib-networking is linked statically; GIO cannot load modules from an APK.
    g_io_openssl_load (null);

    // OpenSSL has no idea where Android keeps its CA store.
    if (Environment.get_variable ("SSL_CERT_DIR") == null) {
        Environment.set_variable ("SSL_CERT_DIR", "/system/etc/security/cacerts", true);
    }

    // The runtime sets XDG_DATA_HOME and XDG_CONFIG_HOME but not XDG_CACHE_HOME,
    // so g_get_user_cache_dir () would land in an unwritable ~/.cache.
    if (Environment.get_variable ("XDG_CACHE_HOME") == null) {
        Environment.set_variable (
            "XDG_CACHE_HOME",
            Path.build_filename (Environment.get_user_data_dir (), "cache"),
            true
        );
    }

    // fontconfig defaults to /etc/fonts, which does not exist on Android;
    // the config from the fontconfig subproject lands in XDG_CONFIG_DIRS.
    if (Environment.get_variable ("FONTCONFIG_FILE") == null) {
        foreach (var dir in Environment.get_system_config_dirs ()) {
            var conf = Path.build_filename (dir, "fonts", "fonts.conf");
            if (FileUtils.test (conf, FileTest.EXISTS)) {
                Environment.set_variable ("FONTCONFIG_FILE", conf, true);
                break;
            }
        }
    }

    android_setup_fonts ();
}

/**
 * Pins the UI font to the bundled Adwaita Sans. fontconfig only knows
 * /system/fonts here, and the default fonts.conf reads
 * $XDG_CONFIG_HOME/fontconfig/fonts.conf, so that file adds the fonts the
 * APK ships (share/fonts under XDG_DATA_DIRS) and aliases the generic
 * families to Adwaita Sans. Everything not covered (CJK, emoji) still
 * falls back to the system fonts.
 */
void android_setup_fonts () {
    var data_dirs = Environment.get_system_data_dirs ();
    if (data_dirs.length == 0) {
        return;
    }

    var fonts_dir = Path.build_filename (data_dirs[0], "fonts");
    if (!FileUtils.test (Path.build_filename (fonts_dir, "Adwaita", "AdwaitaSans-Regular.ttf"), FileTest.EXISTS)) {
        return;
    }

    var conf_dir = Path.build_filename (Environment.get_user_config_dir (), "fontconfig");
    var conf_path = Path.build_filename (conf_dir, "fonts.conf");
    var conf = """<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<!-- written by Cassette on every start; see main.vala -->
<fontconfig>
  <dir>%s</dir>
  <alias binding="strong"><family>sans-serif</family><prefer><family>Adwaita Sans</family></prefer></alias>
  <alias binding="strong"><family>Sans</family><prefer><family>Adwaita Sans</family></prefer></alias>
  <alias binding="strong"><family>Cantarell</family><prefer><family>Adwaita Sans</family></prefer></alias>
</fontconfig>
""".printf (fonts_dir);

    try {
        DirUtils.create_with_parents (conf_dir, 0755);
        string? old = null;
        if (FileUtils.test (conf_path, FileTest.EXISTS)) {
            FileUtils.get_contents (conf_path, out old);
        }
        if (old != conf) {
            FileUtils.set_contents (conf_path, conf);
        }
    } catch (Error e) {
        warning ("fontconfig user config not written: %s", e.message);
    }
}
#endif

int main (string[] args) {
#if ANDROID
    android_setup ();
#endif

    Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.GNOMELOCALEDIR);
    Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
    Intl.textdomain (Config.GETTEXT_PACKAGE);

    Environment.set_application_name (_("Cassette"));

    var app = new Cassette.Application ();
    return app.run (args);
}
