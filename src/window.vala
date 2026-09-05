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

using Cassette.Client;

[GtkTemplate (ui = "/space/rirusha/Cassette/ui/window.ui")]
public class Cassette.Window : ApplicationWindow {

    const ActionEntry[] ACTION_ENTRIES = {
        { "close-sidebar", on_close_sidebar_action },
        { "show-disliked-tracks", on_show_disliked_tracks_action },
        { "preferences", on_preferences_action },
        { "about", on_about_action },
    };

    [GtkChild]
    unowned Adw.ToolbarView player_bar_toolbar;
    [GtkChild]
    unowned Sidebar sidebar;
    [GtkChild]
    unowned Adw.ToastOverlay toast_overlay;
    [GtkChild]
    unowned HeaderBar header_bar;
    [GtkChild]
    unowned Gtk.SearchEntry search_entry;
    [GtkChild]
    unowned Adw.Banner info_banner;
    [GtkChild]
    unowned Gtk.Stack loading_stack;
    [GtkChild]
    unowned LoadingSpinner loading_spinner;
    [GtkChild]
    unowned Adw.ViewStack main_stack;
    [GtkChild]
    unowned Adw.ToolbarView switcher_toolbar;
    [GtkChild]
    unowned PlayerBar player_bar;
    [GtkChild]
    unowned Gtk.Stack bar_stack;
    [GtkChild]
    unowned StationBar station_bar;

    int reconnect_timer = Cassette.Client.TIMEOUT;

    public Pager pager { get; construct; }

    GLib.Binding? current_view_can_back_binding = null;
    GLib.Binding? current_view_can_refresh_binding = null;
    PageRoot _current_view;
    public PageRoot current_view {
        get {
            return _current_view;
        }
        set {
            if (current_view_can_back_binding != null) {
                current_view_can_back_binding.unbind ();
            }
            if (current_view_can_refresh_binding != null) {
                current_view_can_refresh_binding.unbind ();
            }

            _current_view = value;
            current_view_can_back_binding = _current_view.bind_property (
                "can-back",
                header_bar,
                "can-backward",
                GLib.BindingFlags.SYNC_CREATE
            );

            current_view_can_refresh_binding = _current_view.bind_property (
                "can-refresh",
                header_bar,
                "can-refresh",
                GLib.BindingFlags.SYNC_CREATE
            );
        }
    }

    public Sidebar window_sidebar {
        get {
            return sidebar;
        }
    }

    // TODO: Remove this
    public bool player_bar_is_visible { get; set; }

    public bool is_ready { get; private set; default = false; }

    static construct {
        typeof (PlayerBar).ensure ();
        typeof (StationBar).ensure ();
        typeof (ClipBin).ensure ();
    }

    public Window (Cassette.Application app) {
        Object (application: app);
    }

#if ANDROID
    // libadwaita's raised (header bar) and flat (window) colours, dark and light.
    const uint32 BARS_RAISED_DARK = (uint32) 0xff2e2e32;
    const uint32 BARS_FLAT_DARK = (uint32) 0xff222226;
    const uint32 BARS_RAISED_LIGHT = (uint32) 0xffffffff;
    const uint32 BARS_FLAT_LIGHT = (uint32) 0xfffafafb;

    /**
     * Paints the areas under the Android status bar and navigation bar in
     * the colour of whatever toolbar touches them: the header bar is always
     * raised; at the bottom it is the flat view switcher on phones in
     * portrait, the raised player bar when the switcher is up top.
     */
    void update_android_bars () {
        bool dark = Adw.StyleManager.get_default ().dark;
        uint32 raised = dark ? BARS_RAISED_DARK : BARS_RAISED_LIGHT;
        uint32 flat = dark ? BARS_FLAT_DARK : BARS_FLAT_LIGHT;

        bool player_bar_is_bottom = player_bar_toolbar.reveal_bottom_bars && !switcher_toolbar.reveal_bottom_bars;

        cassette_android_set_bars_colors (raised, player_bar_is_bottom ? raised : flat);
    }
#endif

    construct {
        resized.connect ((width, height) => {
            bool compact = width < PLAYER_BAR_COMPACT_WIDTH;
            bool tiny = width < PLAYER_BAR_TINY_WIDTH;
            if (player_bar.compact != compact) {
                player_bar.compact = compact;
            }
            if (station_bar.compact != compact) {
                station_bar.compact = compact;
            }
            if (player_bar.tiny != tiny) {
                player_bar.tiny = tiny;
            }
            if (station_bar.tiny != tiny) {
                station_bar.tiny = tiny;
            }
            if (is_tiny != tiny) {
                is_tiny = tiny;
            }
            // The overlay sidebar's minimum is the window's minimum too.
            int sidebar_min = tiny ? 260 : 360;
            if (sidebar.min_sidebar_width != sidebar_min) {
                sidebar.min_sidebar_width = sidebar_min;
            }
        });

        Client.Glagol.station_manager.connection_changed.connect (update_output_bar);

        // Manual UI testing without clicking: CASSETTE_DEBUG_STATION=<device id>
        // connects to that station after start-up; CASSETTE_DEBUG_PICKER=1 opens
        // the picker. Both are ignored when unset.
        var debug_station = Environment.get_variable ("CASSETTE_DEBUG_STATION");
        var debug_picker = Environment.get_variable ("CASSETTE_DEBUG_PICKER");
        // CASSETTE_DEBUG_MEASURE=<px>: 9 s after start, list the widgets whose
        // minimum width exceeds <px> (who keeps the window from shrinking).
        var debug_measure = Environment.get_variable ("CASSETTE_DEBUG_MEASURE");
        if (debug_measure != null) {
            Timeout.add_seconds (9, () => {
                // CASSETTE_DEBUG_PAGE=<page id>: measure that page instead of the first.
                var debug_page = Environment.get_variable ("CASSETTE_DEBUG_PAGE");
                if (debug_page != null) {
                    main_stack.visible_child_name = debug_page;
                }
                int min, nat;
                measure (Gtk.Orientation.HORIZONTAL, -1, out min, out nat, null, null);
                message ("window min width %d, nat %d, allocated %d", min, nat, get_width ());
                debug_measure_tree (this, int.parse (debug_measure), 0);
                // The bars are hidden until something plays; measure them anyway.
                player_bar.measure (Gtk.Orientation.HORIZONTAL, -1, out min, out nat, null, null);
                message ("player bar (%s) min %d nat %d", player_bar.multi_layout.layout_name, min, nat);
                station_bar.measure (Gtk.Orientation.HORIZONTAL, -1, out min, out nat, null, null);
                message ("station bar (%s) min %d nat %d", station_bar.multi_layout.layout_name, min, nat);
                return Source.REMOVE;
            });
        }
        if (debug_station != null || debug_picker != null) {
            Timeout.add_seconds (8, () => {
                debug_station_hook.begin (debug_station, debug_picker != null);
                return Source.REMOVE;
            });
        }
        Client.Glagol.station_manager.message.connect ((text) => {
            Cassette.application.show_message (text);
        });

#if ANDROID
        update_android_bars ();
        player_bar_toolbar.notify["reveal-bottom-bars"].connect (update_android_bars);
        switcher_toolbar.notify["reveal-bottom-bars"].connect (update_android_bars);
        Adw.StyleManager.get_default ().notify["dark"].connect (update_android_bars);
#endif

        info_banner.button_clicked.connect (try_reconnect);

        main_stack.notify["visible-child-name"].connect (() => {
            if (sidebar.collapsed) {
                activate_action ("close-sidebar", null);
            }
        });

        pager = new Pager (this, main_stack);

        add_action_entries (ACTION_ENTRIES, this);

        Cassette.settings.bind ("window-width", this, "default-width", SettingsBindFlags.DEFAULT);
        Cassette.settings.bind ("window-height", this, "default-height", SettingsBindFlags.DEFAULT);
        Cassette.settings.bind ("window-maximized", this, "maximized", SettingsBindFlags.DEFAULT);

        // CASSETTE_DEBUG_SIZE=WxH: start with that size instead of the saved
        // one (small-screen checks).
        var debug_size = Environment.get_variable ("CASSETTE_DEBUG_SIZE");
        if (debug_size != null) {
            var parts = debug_size.split ("x");
            if (parts.length == 2) {
                maximized = false;
                set_default_size (int.parse (parts[0]), int.parse (parts[1]));
            }
        }

        header_bar.backward_clicked.connect ((obj) => {
            current_view.backward ();
        });

        header_bar.refresh_clicked.connect ((obj) => {
            current_view.refresh ();
        });

        sidebar.notify["collapsed"].connect (check_bar_visible);
        sidebar.notify["is-shown"].connect (check_bar_visible);
        notify["is-shrinked"].connect (check_bar_visible);

        loading_stack.notify["visible-child"].connect (() => {
            if (loading_stack.visible_child_name == "done") {
                do_welcome.begin ();

                is_ready = true;
            }
        });

        close_request.connect (on_close_request);

        if (Cassette.application.is_devel) {
            add_css_class ("devel");
        }
    }

    bool on_close_request () {
        if (window_sidebar.sidebar_child == null) {
            return false;

        } else {
            window_sidebar.close ();
            return true;
        }
    }

    // Below this width the player bar drops to its two-row phone layout.
    /** Window narrower than PLAYER_BAR_TINY_WIDTH: rows and bars drop secondary controls. */
    public bool is_tiny { get; set; default = false; }

    const int PLAYER_BAR_COMPACT_WIDTH = 620;
    // Foldable outer screens (~300 dp): the bars drop to their tiny layout.
    const int PLAYER_BAR_TINY_WIDTH = 340;

    void check_bar_visible () {
        switcher_toolbar.reveal_bottom_bars = (sidebar.collapsed && sidebar.is_shown) || is_shrinked;
    }

    void on_preferences_action () {
        var pref_win = new PreferencesDialog ();

        pref_win.present (this);
    }

    void on_about_action () {
        var about = build_about_dialog ();

        about.present (this);
    }

    void on_show_disliked_tracks_action () {
        current_view.add_view (new DislikedTracksView ());
    }

    void on_close_sidebar_action () {
        sidebar.close ();
    }

    async void do_welcome () {
        switch (settings.get_string ("last-version")) {
            default:
                break;
        }

        settings.set_string ("last-version", Config.VERSION);
    }

    public void set_online () {
        info_banner.revealed = false;
    }

    public void set_offline () {
        info_banner.revealed = true;
    }

    public void load_default_views () {
        if (loading_stack.visible_child_name == "loading") {
            pager.load_pages (PagesType.ONLINE);

            header_bar.load_avatar.begin ();
            yam_talker.update_all.begin ();
            header_bar.can_search = true;

            header_bar.interactive = true;

            cachier.check_all_cache.begin ();

            notify["is-active"].connect (() => {
                if (
                    is_active &&
                    player.state != Player.State.PLAYING
                ) {
                    yam_talker.update_all.begin ();
                }
            });

            loading_stack.visible_child_name = "done";
        }
    }

    public void load_local_views () {
        if (loading_stack.visible_child_name == "loading") {
            pager.load_pages (PagesType.LOCAL);
            loading_stack.visible_child_name = "done";
        }
    }

    public void show_toast (string message) {
        var toast = new Adw.Toast (message);
        toast_overlay.add_toast (toast);

        Logger.info (_("Window info message: %s").printf (message));
    }

    async void try_reconnect () {
        info_banner.sensitive = false;
        info_banner.button_label = reconnect_timer.to_string ();

        yam_talker.update_all.begin ();

        Timeout.add_seconds (1, () => {
            if (reconnect_timer > 1) {
                reconnect_timer--;
                info_banner.button_label = reconnect_timer.to_string ();
                return Source.CONTINUE;

            } else {
                info_banner.sensitive = true;
                info_banner.button_label = _("Reconnect");
                reconnect_timer = Cassette.Client.TIMEOUT;
                return Source.REMOVE;
            }
        });
    }

    public void show_player_bar () {
        player_bar_toolbar.reveal_bottom_bars = true;
    }

    public void hide_player_bar () {
        // The station bar lives in the same toolbar; keep it while remote.
        if (Client.Glagol.station_manager.active != null) {
            return;
        }
        player_bar_toolbar.reveal_bottom_bars = false;
    }

    static void debug_measure_tree (Gtk.Widget widget, int threshold, int depth) {
        if (!widget.visible) {
            return;
        }
        int min, nat;
        widget.measure (Gtk.Orientation.HORIZONTAL, -1, out min, out nat, null, null);
        if (min > threshold) {
            var classes = string.joinv (".", widget.get_css_classes ());
            message ("%s%s%s min=%d nat=%d alloc=%d", string.nfill (depth * 2, ' '),
                widget.get_type ().name (), classes != "" ? "." + classes : "", min, nat, widget.get_width ());
        }
        for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
            debug_measure_tree (child, threshold, depth + 1);
        }
    }

    async void debug_station_hook (string? station_id, bool open_picker) {
        var manager = Client.Glagol.station_manager;
        if (station_id != null) {
            yield manager.refresh ();
            for (uint i = 0; i < manager.stations.get_n_items (); i++) {
                var station = (Client.Glagol.Station) manager.stations.get_item (i);
                if (station.id == station_id) {
                    try {
                        yield manager.transfer_to (station);
                    } catch (Error e) {
                        warning ("debug station: %s", e.message);
                    }
                }
            }
        }
        if (open_picker) {
            new StationPickerDialog ().present (this);
        }

        // CASSETTE_DEBUG_SHOT=<file.png>: render the window from inside GTK
        // (screen capture needs permissions a terminal rarely has).
        var shot = Environment.get_variable ("CASSETTE_DEBUG_SHOT");
        if (shot != null) {
            Timeout.add_seconds (9, () => {
                try {
                    var paintable = new Gtk.WidgetPaintable (this);
                    var snapshot = new Gtk.Snapshot ();
                    paintable.snapshot (snapshot, get_width (), get_height ());
                    var node = snapshot.free_to_node ();
                    if (node != null) {
                        var texture = get_renderer ().render_texture (node, null);
                        texture.save_to_png (shot);
                        message ("debug shot saved to %s", shot);
                    }
                } catch (Error e) {
                    warning ("debug shot: %s", e.message);
                }
                return Source.REMOVE;
            });
        }
    }

    // Local player bar or the station bar, depending on where playback goes.
    void update_output_bar () {
        bool remote = Client.Glagol.station_manager.active != null;
        bar_stack.visible_child_name = remote ? "station" : "local";

        if (remote) {
            player_bar_toolbar.reveal_bottom_bars = true;
        } else {
            player_bar_toolbar.reveal_bottom_bars = player.mode.get_current_track_info () != null;
        }
    }
}
