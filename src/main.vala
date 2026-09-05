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

    // Debug switches: `adb shell` cannot pass environment variables, so
    // KEY=VALUE lines from <app files dir>/debug.env become the environment
    // (CASSETTE_DEBUG_*, G_MESSAGES_DEBUG, ...). Absent in normal use.
    // Absent in normal use — and an unhandled error here would end this
    // whole function (Vala returns on unhandled errors), taking the font
    // setup below with it. That is exactly what happened on devices
    // without the file.
    var debug_env = Path.build_filename (Environment.get_user_data_dir (), "..", "debug.env");
    if (FileUtils.test (debug_env, FileTest.EXISTS)) {
        try {
            string debug_lines;
            FileUtils.get_contents (debug_env, out debug_lines);
            foreach (var line in debug_lines.split ("\n")) {
                var parts = line.strip ().split ("=", 2);
                if (parts.length == 2 && parts[0] != "") {
                    Environment.set_variable (parts[0], parts[1], true);
                }
            }
        } catch (Error e) {
            warning ("debug.env not read: %s", e.message);
        }
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
 * Pins the UI font to the bundled static Inter (share/fonts/Inter in the
 * APK). fontconfig's stock fonts.conf pulls the user configuration in
 * through an "xdg"-prefixed include, which needs XDG_CONFIG_HOME in the
 * process environment — the runtime hands GLib its directories another
 * way, so that include silently did nothing and every device fell back to
 * its system sans (Roboto on Pixel, MiSans VF on HyperOS: hairline weight,
 * missing spaces). Now FONTCONFIG_FILE points at a config of our own that
 * includes the stock one, adds the bundled directory and aliases the
 * generic families to Inter. CJK, emoji etc. still come from /system/fonts.
 */
void android_setup_fonts () {
    // What GLib knows about the directories, fontconfig must see too.
    Environment.set_variable ("XDG_DATA_HOME", Environment.get_user_data_dir (), false);
    Environment.set_variable ("XDG_CONFIG_HOME", Environment.get_user_config_dir (), false);
    Environment.set_variable ("XDG_CACHE_HOME", Environment.get_user_cache_dir (), false);

    var data_dirs = Environment.get_system_data_dirs ();
    if (data_dirs.length == 0) {
        return;
    }

    var fonts_dir = Path.build_filename (data_dirs[0], "fonts");
    if (!FileUtils.test (Path.build_filename (fonts_dir, "Inter", "Inter-Regular.ttf"), FileTest.EXISTS)) {
        warning ("bundled fonts not found in %s; system fonts will be used", fonts_dir);
        Environment.set_variable ("CASSETTE_FONTS_STATUS", "bundled fonts not found in %s".printf (fonts_dir), true);
        return;
    }

    string? stock_conf = null;
    foreach (var dir in Environment.get_system_config_dirs ()) {
        var conf = Path.build_filename (dir, "fonts", "fonts.conf");
        if (FileUtils.test (conf, FileTest.EXISTS)) {
            stock_conf = conf;
            break;
        }
    }

    // External storage first; some vendors make it read-only or slow to
    // appear, so the app-private directory (parent of share/) is the fallback.
    string[] conf_dirs = {
        Path.build_filename (Environment.get_user_config_dir (), "fontconfig"),
        Path.build_filename (data_dirs[0], "..", "fontconfig")
    };
    var conf = """<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<!-- written by Cassette on every start; see main.vala -->
<fontconfig>
%s
  <dir>%s</dir>
  <cachedir>%s</cachedir>
  <alias binding="strong"><family>sans-serif</family><prefer><family>Inter</family></prefer></alias>
  <alias binding="strong"><family>Sans</family><prefer><family>Inter</family></prefer></alias>
  <alias binding="strong"><family>Cantarell</family><prefer><family>Inter</family></prefer></alias>
  <alias binding="strong"><family>Adwaita Sans</family><prefer><family>Inter</family></prefer></alias>
</fontconfig>
""".printf (
        stock_conf != null ? "  <include ignore_missing=\"yes\">%s</include>".printf (stock_conf) : "",
        fonts_dir,
        Path.build_filename (Environment.get_user_cache_dir (), "fontconfig")
    );

    foreach (var conf_dir in conf_dirs) {
        var conf_path = Path.build_filename (conf_dir, "fonts.conf");
        try {
            DirUtils.create_with_parents (conf_dir, 0755);
            string? old = null;
            if (FileUtils.test (conf_path, FileTest.EXISTS)) {
                FileUtils.get_contents (conf_path, out old);
            }
            if (old != conf) {
                FileUtils.set_contents (conf_path, conf);
            }
            Environment.set_variable ("FONTCONFIG_FILE", conf_path, true);
            Environment.set_variable ("CASSETTE_FONTS_STATUS", "config %s".printf (conf_path), true);
            return;
        } catch (Error e) {
            warning ("fontconfig config not written to %s: %s", conf_path, e.message);
            Environment.set_variable ("CASSETTE_FONTS_STATUS", "config write failed: %s".printf (e.message), true);
        }
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
