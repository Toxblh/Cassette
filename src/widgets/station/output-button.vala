/* Copyright 2026 Anton Palgunov
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

using Cassette.Client;

/**
 * "Play on…" button: opens the device picker. Lit up (accent) while a
 * station is the output; with show-label it also names the station.
 */
public class Cassette.OutputButton : Gtk.Button {

    public bool show_label { get; construct; default = false; }

    Adw.ButtonContent? content = null;

    public OutputButton (bool show_label = false) {
        Object (show_label: show_label);
    }

    construct {
        add_css_class ("flat");
        valign = Gtk.Align.CENTER;

        if (show_label) {
            content = new Adw.ButtonContent () {
                icon_name = "audio-speakers-symbolic",
                can_shrink = true
            };
            child = content;
        } else {
            icon_name = "audio-speakers-symbolic";
        }

        clicked.connect (() => {
            new StationPickerDialog ().present (this);
        });

        Glagol.station_manager.connection_changed.connect (update);
        update ();
    }

    void update () {
        var station = Glagol.station_manager.active;

        if (station != null) {
            add_css_class ("accent");
            tooltip_text = _("Playing on %s").printf (station.display_name);
            if (content != null) {
                content.icon_name = station.icon_name;
                content.label = station.short_name;
            } else {
                icon_name = station.icon_name;
            }
        } else {
            remove_css_class ("accent");
            tooltip_text = _("Play on a Yandex station");
            if (content != null) {
                content.icon_name = "audio-speakers-symbolic";
                content.label = _("Play on…");
            } else {
                icon_name = "audio-speakers-symbolic";
            }
        }
    }
}
