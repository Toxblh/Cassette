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
using Cassette.Client.Glagol;

/**
 * Where to play: this device or one of the account's stations. Opens as a
 * bottom sheet on phones. Picking a station moves the current track there
 * from its position; picking this device takes it back.
 */
public class Cassette.StationPickerDialog : Adw.Dialog {

    Gtk.ListBox local_list;
    Gtk.ListBox station_list;
    Adw.ActionRow local_row;
    Gtk.Image local_check;
    Gtk.Spinner scan_spinner;
    Gtk.Button refresh_button;
    Gtk.Label status_label;
    Gtk.Label error_label;

    bool busy = false;

    construct {
        title = _("Play on");
        content_width = 420;

        var toolbar_view = new Adw.ToolbarView ();
        var header = new Adw.HeaderBar ();

        refresh_button = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
            tooltip_text = _("Look for stations again")
        };
        refresh_button.clicked.connect (() => {
            Glagol.station_manager.refresh.begin ();
        });
        header.pack_end (refresh_button);

        scan_spinner = new Gtk.Spinner () {
            margin_end = 6
        };
        header.pack_end (scan_spinner);

        toolbar_view.add_top_bar (header);

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
            margin_top = 6,
            margin_bottom = 18,
            margin_start = 12,
            margin_end = 12
        };

        local_list = new Gtk.ListBox () {
            selection_mode = Gtk.SelectionMode.NONE,
            css_classes = { "boxed-list" }
        };
        local_row = new Adw.ActionRow () {
            title = _("This device"),
            activatable = true
        };
#if ANDROID
        local_row.add_prefix (new Gtk.Image.from_icon_name ("phone-symbolic"));
#else
        local_row.add_prefix (new Gtk.Image.from_icon_name ("computer-symbolic"));
#endif
        local_check = new Gtk.Image.from_icon_name ("emblem-ok-symbolic");
        local_row.add_suffix (local_check);
        local_list.append (local_row);
        local_list.row_activated.connect (() => {
            choose_local.begin ();
        });
        box.append (local_list);

        var stations_title = new Gtk.Label (_("Yandex stations")) {
            css_classes = { "heading" },
            halign = Gtk.Align.START,
            margin_top = 6
        };
        box.append (stations_title);

        station_list = new Gtk.ListBox () {
            selection_mode = Gtk.SelectionMode.NONE,
            css_classes = { "boxed-list" }
        };
        station_list.bind_model (Glagol.station_manager.stations, create_row);
        station_list.row_activated.connect ((row) => {
            var station = ((StationRow) row).station;
            choose_station.begin (station);
        });
        box.append (station_list);

        status_label = new Gtk.Label ("") {
            css_classes = { "dim-label" },
            wrap = true,
            justify = Gtk.Justification.CENTER,
            margin_top = 6
        };
        box.append (status_label);

        error_label = new Gtk.Label ("") {
            css_classes = { "error" },
            wrap = true,
            justify = Gtk.Justification.CENTER,
            visible = false
        };
        box.append (error_label);

        var clamp = new Adw.Clamp () {
            maximum_size = 480,
            child = box
        };
        toolbar_view.content = clamp;
        child = toolbar_view;

        Glagol.station_manager.notify["scanning"].connect (update_status);
        Glagol.station_manager.stations.items_changed.connect (update_status);
        Glagol.station_manager.connection_changed.connect (update_status);
        update_status ();

        Glagol.station_manager.refresh.begin ();
    }

    Gtk.Widget create_row (Object item) {
        return new StationRow ((Station) item);
    }

    void update_status () {
        var manager = Glagol.station_manager;

        scan_spinner.spinning = manager.scanning;
        scan_spinner.visible = manager.scanning;
        refresh_button.visible = !manager.scanning;

        local_check.visible = manager.active == null;
        station_list.visible = manager.stations.get_n_items () > 0;

        if (manager.scanning && manager.stations.get_n_items () == 0) {
            status_label.label = _("Looking for stations…");
            status_label.visible = true;
        } else if (manager.stations.get_n_items () == 0) {
            status_label.label = _("No stations in your account. They appear here once added in the Yandex app.");
            status_label.visible = true;
        } else {
            status_label.visible = false;
        }
    }

    async void choose_local () {
        if (busy) {
            return;
        }
        if (Glagol.station_manager.active == null) {
            close ();
            return;
        }

        set_busy (true);
        yield Glagol.station_manager.take_back ();
        set_busy (false);
        close ();
    }

    async void choose_station (Station station) {
        if (busy) {
            return;
        }
        if (!station.online) {
            error_label.label = _("%s is not on this network").printf (station.display_name);
            error_label.visible = true;
            return;
        }
        if (station == Glagol.station_manager.active) {
            close ();
            return;
        }

        set_busy (true);
        error_label.visible = false;
        try {
            yield Glagol.station_manager.transfer_to (station);
            set_busy (false);
            close ();
            application.show_message (_("Playing on %s").printf (station.display_name));
        } catch (Error e) {
            set_busy (false);
            error_label.label = e.message;
            error_label.visible = true;
        }
    }

    void set_busy (bool value) {
        busy = value;
        local_list.sensitive = !value;
        station_list.sensitive = !value;
    }

    class StationRow : Adw.ActionRow {
        public Station station { get; construct; }

        Gtk.Image check;
        Gtk.Spinner spinner;

        public StationRow (Station station) {
            Object (station: station);
        }

        construct {
            add_prefix (new Gtk.Image.from_icon_name ("audio-speakers-symbolic"));

            check = new Gtk.Image.from_icon_name ("emblem-ok-symbolic");
            add_suffix (check);

            spinner = new Gtk.Spinner ();
            add_suffix (spinner);

            station.notify.connect (update);
            Glagol.station_manager.connection_changed.connect (update);
            Glagol.station_manager.notify["connecting"].connect (update);
            update ();
        }

        void update () {
            var manager = Glagol.station_manager;
            bool is_active = manager.active == station;

            title = station.display_name;
            activatable = station.online;
            sensitive = station.online;

            if (is_active) {
                subtitle = _("%s · playing here now").printf (station.model);
            } else if (station.online) {
                subtitle = station.model;
            } else {
                subtitle = _("%s · not on this network").printf (station.model);
            }

            check.visible = is_active;
            spinner.visible = false;
            spinner.spinning = false;
        }
    }
}
