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
 * The player bar while a station is the output: what the station plays,
 * transport, seek and volume for it, and the way back to this device.
 * Same wide/narrow layouts as PlayerBar, switched by the window.
 */
public class Cassette.StationBar : Adw.Bin {

    const int COVER_SIZE = 48;

    Adw.MultiLayoutView multi_layout;

    Gtk.Image cover;
    Gtk.Label title_label;
    Gtk.Label artist_label;
    Gtk.Button prev_button;
    Gtk.Button play_button;
    Gtk.Button next_button;
    Gtk.Label current_time;
    Gtk.Label total_time;
    Gtk.Scale slider;
    StationVolumeSlider volume;
    OutputButton output_wide;
    OutputButton output_narrow;
    Gtk.Button back_button;

    Soup.Session soup = new Soup.Session ();
    string cover_url = "";
    PlayerState? last = null;
    int64 last_state_time = 0;
    uint tick_source = 0;
    bool seeking = false;

    public bool compact {
        get {
            return multi_layout.layout_name == "narrow";
        }
        set {
            multi_layout.layout_name = value ? "narrow" : "wide";
        }
    }

    construct {
        build_children ();

        multi_layout = new Adw.MultiLayoutView ();
        multi_layout.add_layout (new Adw.Layout (build_wide ()) { name = "wide" });
        multi_layout.add_layout (new Adw.Layout (build_narrow ()) { name = "narrow" });

        multi_layout.set_child ("cover", cover_widget ());
        multi_layout.set_child ("titles", titles_widget ());
        multi_layout.set_child ("prev", prev_button);
        multi_layout.set_child ("play", play_button);
        multi_layout.set_child ("next", next_button);
        multi_layout.set_child ("progress", progress_widget ());
        multi_layout.set_child ("volume", volume);
        multi_layout.set_child ("output-wide", output_wide);
        multi_layout.set_child ("output-narrow", output_narrow);
        multi_layout.set_child ("back", back_button);

        child = multi_layout;

        Glagol.station_manager.state_changed.connect (on_state);
        Glagol.station_manager.connection_changed.connect (on_connection);
        on_connection ();
    }

    void build_children () {
        // Gtk.Image honours pixel-size; a Picture would request the texture's size.
        cover = new Gtk.Image () {
            pixel_size = COVER_SIZE,
            valign = Gtk.Align.CENTER
        };

        title_label = new Gtk.Label ("") {
            halign = Gtk.Align.START,
            ellipsize = Pango.EllipsizeMode.END,
            css_classes = { "heading" }
        };
        artist_label = new Gtk.Label ("") {
            halign = Gtk.Align.START,
            ellipsize = Pango.EllipsizeMode.END,
            css_classes = { "dim-label" }
        };

        prev_button = new Gtk.Button.from_icon_name ("media-skip-backward-symbolic") {
            css_classes = { "circular", "flat" },
            valign = Gtk.Align.CENTER,
            tooltip_text = _("Play previous track")
        };
        prev_button.clicked.connect (() => Glagol.station_manager.prev ());

        play_button = new Gtk.Button.from_icon_name ("media-playback-start-symbolic") {
            css_classes = { "circular", "flat" },
            valign = Gtk.Align.CENTER,
            margin_start = 4,
            margin_end = 4
        };
        play_button.clicked.connect (() => Glagol.station_manager.play_pause ());

        next_button = new Gtk.Button.from_icon_name ("media-skip-forward-symbolic") {
            css_classes = { "circular", "flat" },
            valign = Gtk.Align.CENTER,
            tooltip_text = _("Play next track")
        };
        next_button.clicked.connect (() => Glagol.station_manager.next ());

        current_time = new Gtk.Label ("0:00") {
            css_classes = { "dim-label", "caption" },
            halign = Gtk.Align.START,
            width_request = 32
        };
        total_time = new Gtk.Label ("0:00") {
            css_classes = { "dim-label", "caption" },
            halign = Gtk.Align.END,
            width_request = 32
        };
        slider = new Gtk.Scale (Gtk.Orientation.HORIZONTAL, new Gtk.Adjustment (0, 0, 1, 1, 5, 0)) {
            hexpand = true
        };
        slider.change_value.connect ((scroll, value) => {
            Glagol.station_manager.seek (value);
            if (last != null) {
                last.progress = value;
                last_state_time = GLib.get_monotonic_time ();
            }
            current_time.label = sec2str ((int) value, true);
            return false;
        });

        volume = new StationVolumeSlider ();
        volume.volume_changed.connect ((v) => Glagol.station_manager.set_volume (v));

        output_wide = new OutputButton (true);
        output_narrow = new OutputButton (false);

#if ANDROID
        back_button = new Gtk.Button.from_icon_name ("phone-symbolic");
#else
        back_button = new Gtk.Button.from_icon_name ("computer-symbolic");
#endif
        back_button.add_css_class ("flat");
        back_button.valign = Gtk.Align.CENTER;
        back_button.tooltip_text = _("Play on this device");
        back_button.clicked.connect (() => {
            Glagol.station_manager.take_back.begin ();
        });
    }

    Gtk.Widget cover_widget () {
        var frame = new Gtk.Frame (null) {
            css_classes = { "card", "small-border-radius" },
            valign = Gtk.Align.CENTER,
            child = cover
        };
        return frame;
    }

    Gtk.Widget titles_widget () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
            valign = Gtk.Align.CENTER,
            hexpand = true,
            margin_start = 8,
            margin_end = 8
        };
        box.append (title_label);
        box.append (artist_label);
        // Long titles must not push the transport aside.
        title_label.max_width_chars = 24;
        artist_label.max_width_chars = 24;
        return box;
    }

    Gtk.Widget progress_widget () {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
        box.append (current_time);
        box.append (slider);
        box.append (total_time);
        return box;
    }

    static Adw.LayoutSlot slot (string id) {
        return new Adw.LayoutSlot (id);
    }

    Gtk.Widget build_wide () {
        // Start and end get their natural size, the transport takes the rest:
        // unlike the local bar there is no queue carousel to balance against.
        var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
            margin_top = 6,
            margin_bottom = 6,
            margin_start = 6,
            margin_end = 12
        };

        // hexpand of the title labels would propagate up and steal the
        // transport's space; the titles have max-width-chars instead.
        var left = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
            width_request = 220,
            hexpand = false
        };
        left.append (slot ("cover"));
        left.append (slot ("titles"));
        row.append (left);

        var middle = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
            valign = Gtk.Align.CENTER,
            hexpand = true,
            margin_start = 12,
            margin_end = 12
        };
        var transport = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
            halign = Gtk.Align.CENTER
        };
        transport.append (slot ("prev"));
        transport.append (slot ("play"));
        transport.append (slot ("next"));
        middle.append (transport);
        middle.append (slot ("progress"));
        var clamp = new Adw.Clamp () {
            maximum_size = 800,
            hexpand = true,
            child = middle
        };
        row.append (clamp);

        // Volume above, the station and the way back below.
        var right = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
            halign = Gtk.Align.END,
            valign = Gtk.Align.CENTER,
            hexpand = false
        };
        right.append (slot ("volume"));
        var station_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
            halign = Gtk.Align.END
        };
        station_row.append (slot ("output-wide"));
        station_row.append (slot ("back"));
        right.append (station_row);

        // Slots must exist in every layout.
        var hidden = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
            visible = false
        };
        hidden.append (slot ("output-narrow"));
        right.append (hidden);
        row.append (right);

        return row;
    }

    Gtk.Widget build_narrow () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
            margin_top = 4,
            margin_bottom = 4,
            margin_start = 6,
            margin_end = 6
        };

        var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
        row.append (slot ("cover"));
        row.append (slot ("titles"));
        row.append (slot ("prev"));
        row.append (slot ("play"));
        row.append (slot ("next"));

        // Station volume behind a popover: hardware keys change the phone, not the speaker.
        var volume_popover = new Gtk.Popover () {
            child = slot ("volume")
        };
        var volume_button = new Gtk.MenuButton () {
            icon_name = "audio-volume-high-symbolic",
            css_classes = { "flat" },
            valign = Gtk.Align.CENTER,
            popover = volume_popover,
            tooltip_text = _("Station volume")
        };
        row.append (volume_button);
        row.append (slot ("output-narrow"));
        row.append (slot ("back"));
        box.append (row);

        box.append (slot ("progress"));

        var hidden = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
            visible = false
        };
        hidden.append (slot ("output-wide"));
        box.append (hidden);

        return box;
    }

    // ── state ────────────────────────────────────────────────────────────

    void on_connection () {
        if (Glagol.station_manager.active == null) {
            stop_tick ();
            last = null;
            title_label.label = "";
            artist_label.label = "";
            cover.paintable = null;
            cover.icon_name = "audio-x-generic-symbolic";
            cover_url = "";
            return;
        }
        var state = Glagol.station_manager.state;
        if (state != null) {
            on_state (state);
        }
        start_tick ();
    }

    void on_state (PlayerState state) {
        last = state;
        last_state_time = GLib.get_monotonic_time ();

        title_label.label = state.title != "" ? state.title : _("Nothing is playing");
        artist_label.label = state.artist;
        artist_label.visible = state.artist != "";

        play_button.icon_name = state.playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
        play_button.tooltip_text = state.playing ? _("Pause") : _("Play");
        prev_button.sensitive = state.has_prev || state.track_id != "";
        next_button.sensitive = state.has_next || state.track_id != "";

        slider.adjustment.upper = state.duration > 0 ? state.duration : 1;
        slider.sensitive = state.duration > 0;
        total_time.label = sec2str ((int) state.duration, true);
        show_progress (state.progress);

        volume.set_volume_silent (state.volume);

        // avatars.yandex.net serves fixed sizes; 200 is the smallest square one.
        string url = state.get_cover_url (200);
        if (url != cover_url) {
            cover_url = url;
            if (url == "") {
                cover.icon_name = "audio-x-generic-symbolic";
            } else {
                load_cover.begin (url);
            }
        }
    }

    void show_progress (double seconds) {
        if (last != null && last.duration > 0) {
            slider.adjustment.value = seconds.clamp (0, last.duration);
        }
        current_time.label = sec2str ((int) seconds, true);
    }

    // The station reports state on changes and keepalive pings; in between
    // the position is advanced locally so the slider does not stutter.
    void start_tick () {
        if (tick_source != 0) {
            return;
        }
        tick_source = Timeout.add (1000, () => {
            if (last != null && last.playing && last.duration > 0) {
                double elapsed = (GLib.get_monotonic_time () - last_state_time) / 1000000.0;
                show_progress (last.progress + elapsed);
            }
            return Source.CONTINUE;
        });
    }

    void stop_tick () {
        if (tick_source != 0) {
            Source.remove (tick_source);
            tick_source = 0;
        }
    }

    async void load_cover (string url) {
        try {
            var msg = new Soup.Message ("GET", url);
            var bytes = yield soup.send_and_read_async (msg, Priority.DEFAULT, null);
            if (msg.status_code != 200 || cover_url != url) {
                return;
            }
            var pixbuf = new Gdk.Pixbuf.from_stream (new MemoryInputStream.from_bytes (bytes), null);
            if (cover_url == url) {
                cover.paintable = Gdk.Texture.for_pixbuf (pixbuf);
            }
        } catch (Error e) {
            Logger.debug ("Station cover: %s".printf (e.message));
        }
    }
}
