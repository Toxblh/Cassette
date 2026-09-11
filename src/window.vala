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

#if ANDROID || IOS
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

#if ANDROID
        cassette_android_set_bars_colors (raised, player_bar_is_bottom ? raised : flat);
#else
        gdk_ios_set_bars_colors (raised, player_bar_is_bottom ? raised : flat);
#endif
    }
#endif

    /**
     * Opens the artist page on the current page root. On a phone the
     * sidebar covers the content, so it closes to reveal the page.
     */
    public void open_artist (string artist_id) {
        if (current_view == null) {
            return;
        }
        current_view.add_view (new ArtistView (artist_id));
        if (sidebar.collapsed) {
            sidebar.close ();
        }
    }

    /**
     * Search: the entry under the header bar pushes a SearchView on the
     * current page root, or re-queries the one already on top.
     */
    void run_search (string text) {
        var query = text.strip ();
        if (query == "" || current_view == null) {
            return;
        }
        var top = current_view.visible_view as SearchView;
        if (top != null) {
            top.query = query;
            top.refresh.begin ();
        } else {
            current_view.add_view (new SearchView (query));
        }
    }

    int last_height = 0;

    // The on-screen keyboard shrinks the window (adjustResize); GTK only
    // scrolls to the focus on focus changes, so do it on shrink too.
    void keep_focus_visible (int height) {
        bool shrank = last_height > 0 && height < last_height;
        last_height = height;
        if (!shrank) {
            return;
        }
        var focus = get_focus ();
        if (focus == null || !(focus is Gtk.Editable || focus is Gtk.Text)) {
            return;
        }
        Idle.add_once (() => {
            var viewport = focus.get_ancestor (typeof (Gtk.Viewport)) as Gtk.Viewport;
            if (viewport != null) {
                viewport.scroll_to (focus, null);
                return;
            }
            // Inside a Gtk.ListView (the track list) there is no viewport:
            // move the scrolled window's adjustment by hand.
            var scrolled = focus.get_ancestor (typeof (Gtk.ScrolledWindow)) as Gtk.ScrolledWindow;
            if (scrolled == null) {
                return;
            }
            Graphene.Rect bounds;
            if (!focus.compute_bounds (scrolled, out bounds)) {
                return;
            }
            var adj = scrolled.vadjustment;
            double bottom = bounds.origin.y + bounds.size.height + 16;
            if (bottom > adj.page_size) {
                adj.value = adj.value + (bottom - adj.page_size);
            } else if (bounds.origin.y < 0) {
                adj.value = adj.value + bounds.origin.y;
            }
        });
    }

    construct {
        search_entry.search_changed.connect (() => {
            run_search (search_entry.text);
        });
        search_entry.activate.connect (() => {
            run_search (search_entry.text);
        });
        header_bar.notify["search-active"].connect (() => {
            if (header_bar.search_active) {
                search_entry.grab_focus ();
            }
        });

#if ANDROID || IOS
        // Scrolling the page dismisses the on-screen keyboard: a drag over
        // the content takes focus away from whatever text field has it.
        // Touch scrolling is a drag gesture (not a scroll event), and
        // adjustments also move on programmatic scrolls, so watch the
        // gesture itself. Capture phase: the page's scrolled windows own
        // the sequence, so a bubbling controller would not see it.
        var unfocus_on_scroll = new Gtk.GestureDrag ();
        unfocus_on_scroll.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
        unfocus_on_scroll.drag_begin.connect ((start_x, start_y) => {
            var focus = get_focus ();
            if (focus == null || !(focus is Gtk.Editable)) {
                return;
            }
            // A drag that starts on the field itself selects text: keep focus.
            var start = Graphene.Point () { x = (float) start_x, y = (float) start_y };
            Graphene.Point in_focus;
            if (main_stack.compute_point (focus, start, out in_focus) &&
                focus.contains ((double) in_focus.x, (double) in_focus.y)) {
                return;
            }
            debug ("window: content scroll unfocuses %s", focus.get_type ().name ());
            set_focus (null);
        });
        main_stack.add_controller (unfocus_on_scroll);
#endif

        // CASSETTE_DEBUG_SHOT=<file.png>: render the window from inside GTK
        // (screen capture needs permissions a terminal rarely has).
        var shot = Environment.get_variable ("CASSETTE_DEBUG_SHOT");
        if (shot != null) {
            var shot_page = Environment.get_variable ("CASSETTE_DEBUG_PAGE");
            if (shot_page != null) {
                Timeout.add_seconds (6, () => {
                    main_stack.visible_child_name = shot_page;
                    return Source.REMOVE;
                });
            }
            Timeout.add_seconds (12, () => {
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

        // CASSETTE_DEBUG_PIXBUF_STRESS=<threads>: decode cached cover images
        // from that many threads at once, 300 times each (gdk-pixbuf race check).
        var debug_stress = Environment.get_variable ("CASSETTE_DEBUG_PIXBUF_STRESS");
        if (debug_stress != null) {
            Timeout.add_seconds (10, () => {
                debug_pixbuf_stress (int.parse (debug_stress));
                return Source.REMOVE;
            });
        }

        // CASSETTE_DEBUG_MENU_SHOTS=<dir>: open the primary menu as a bottom
        // sheet and save a burst of snapshots of the window while it animates.
        // CASSETTE_DEBUG_DIALOG=menu|account|picker picks what to open.
        var debug_menu_shots = Environment.get_variable ("CASSETTE_DEBUG_MENU_SHOTS");
        if (debug_menu_shots != null) {
            Timeout.add_seconds (8, () => {
                int64 t0 = get_monotonic_time ();
                var clock = get_frame_clock ();
                int64 f0 = clock != null ? clock.get_frame_counter () : 0;
                var which = Environment.get_variable ("CASSETTE_DEBUG_DIALOG") ?? "menu";
                if (which == "account") {
                    header_bar.on_avatar_button_clicked ();
                } else if (which == "picker") {
                    new StationPickerDialog ().present (this);
                } else {
                    header_bar.open_primary_menu_dialog ();
                }
                message ("menu shots: dialog presented after %.1f ms", (get_monotonic_time () - t0) / 1000.0);
                int64 last_tick = get_monotonic_time ();
                Timeout.add (5, () => {
                    int64 now = get_monotonic_time ();
                    if (now - last_tick > 40000) {
                        message ("main loop stalled %.0f ms (at %.0f ms)", (now - last_tick) / 1000.0, (now - t0) / 1000.0);
                    }
                    last_tick = now;
                    return now - t0 < 1500000 ? Source.CONTINUE : Source.REMOVE;
                });
                int shot_no = 0;
                Timeout.add (25, () => {
                    // Timing first: a late tick means the main loop was busy,
                    // few frames between ticks mean nothing was painted.
                    message ("menu shot %02d at %.0f ms, frames painted so far: %" + int64.FORMAT, shot_no,
                        (get_monotonic_time () - t0) / 1000.0,
                        clock != null ? clock.get_frame_counter () - f0 : 0);
                    // Rendering a snapshot is itself slow on phones: with a
                    // missing directory only the timing is logged.
                    if (FileUtils.test (debug_menu_shots, FileTest.IS_DIR)) {
                        save_snapshot ("%s/menu-%02d.png".printf (debug_menu_shots, shot_no));
                    }
                    shot_no++;
                    return shot_no < 24 ? Source.CONTINUE : Source.REMOVE;
                });
                return Source.REMOVE;
            });
        }

        // CASSETTE_DEBUG_SEARCH=<text> / CASSETTE_DEBUG_ARTIST=<id>: open
        // those pages after start-up (snapshots without clicking).
        var debug_search = Environment.get_variable ("CASSETTE_DEBUG_SEARCH");
        var debug_artist = Environment.get_variable ("CASSETTE_DEBUG_ARTIST");
        var debug_album = Environment.get_variable ("CASSETTE_DEBUG_ALBUM");
        if (debug_search != null || debug_artist != null || debug_album != null) {
            Timeout.add_seconds (8, () => {
                if (debug_artist != null && current_view != null) {
                    current_view.add_view (new ArtistView (debug_artist));
                } else if (debug_album != null && current_view != null) {
                    current_view.add_view (new AlbumView (debug_album));
                } else if (debug_search != null) {
                    run_search (debug_search);
                }
                return Source.REMOVE;
            });
        }

        resized.connect ((width, height) => {
            keep_focus_visible (height);
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

        // CASSETTE_DEBUG_SENSITIVE=1: every 3 s, log the sensitivity of the
        // player bar and its row widgets (phones showed a half-disabled bar).
        if (Environment.get_variable ("CASSETTE_DEBUG_SENSITIVE") != null) {
            Timeout.add_seconds (3, () => {
                message ("player bar: layout %s, sensitive %s, effective %s, loading %s, size %dx%d, window %dx%d",
                    player_bar.multi_layout.layout_name,
                    player_bar.sensitive.to_string (), player_bar.is_sensitive ().to_string (),
                    player.current_track_loading.to_string (),
                    player_bar.get_width (), player_bar.get_height (), get_width (), get_height ());
                var clock = get_frame_clock ();
                if (clock != null) {
                    var timings = clock.get_current_timings ();
                    message ("  frame clock: frame_time %s, monotonic %s, diff %s us, refresh %s us",
                        clock.get_frame_time ().to_string (), get_monotonic_time ().to_string (),
                        (clock.get_frame_time () - get_monotonic_time ()).to_string (),
                        timings != null ? timings.get_refresh_interval ().to_string () : "-");
                }
                // Computed CSS of the bar and its toolbar parent (filter, transitions).
                for (Gtk.Widget? w = player_bar; w != null; w = w.parent) {
                    if (w.get_css_classes ().length > 0 && "bottom-bar" in string.joinv (",", w.get_css_classes ())) {
                        foreach (var line in w.get_first_child ().get_style_context ().to_string (Gtk.StyleContextPrintFlags.SHOW_STYLE).split ("\n")) {
                            if ("filter" in line || "transition" in line || "opacity" in line) {
                                message ("  css(%s child): %s", w.get_type ().name (), line.strip ());
                            }
                        }
                    }
                }
                foreach (var line in player_bar.get_style_context ().to_string (Gtk.StyleContextPrintFlags.SHOW_STYLE).split ("\n")) {
                    if ("filter" in line || "transition" in line || "opacity" in line) {
                        message ("  css(bar): %s", line.strip ());
                    }
                }
                for (Gtk.Widget? w = player_bar; w != null; w = w.parent) {
                    var flags = w.get_state_flags ();
                    message ("  up: %s%s opacity=%.2f flags=0x%x%s%s classes=%s",
                        w.get_type ().name (),
                        w.name != null && w.name != w.get_type ().name () ? "(" + w.name + ")" : "",
                        w.opacity, (uint) flags,
                        (flags & Gtk.StateFlags.BACKDROP) != 0 ? " BACKDROP" : "",
                        (flags & Gtk.StateFlags.INSENSITIVE) != 0 ? " INSENSITIVE" : "",
                        string.joinv (",", w.get_css_classes ()));
                }
                debug_sensitive_tree (player_bar, 0);
                return Source.CONTINUE;
            });
        }

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
        // CASSETTE_DEBUG_FONTS=1: which fonts Pango really uses for sample
        // strings (family, weight, variations per run) and the families
        // fontconfig knows. For "thin text / missing spaces" reports.
        if (Environment.get_variable ("CASSETTE_DEBUG_FONTS") != null) {
            Timeout.add_seconds (9, () => {
                debug_fonts ();
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

#if ANDROID || IOS
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
    void debug_sensitive_tree (Gtk.Widget widget, int depth) {
        if (depth > 6) {
            return;
        }
        for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
            if (!child.visible) {
                continue;
            }
            Graphene.Rect bounds;
            child.compute_bounds (this, out bounds);
            var flags = child.get_state_flags ();
            message ("%*s%s%s sens=%s eff=%s opacity=%.2f flags=0x%x%s at %.0f,%.0f %.0fx%.0f",
                depth * 2, "", child.get_type ().name (),
                child.name != null && child.name != child.get_type ().name () ? "(" + child.name + ")" : "",
                child.sensitive.to_string (), child.is_sensitive ().to_string (), child.opacity,
                (uint) flags, (flags & Gtk.StateFlags.BACKDROP) != 0 ? " BACKDROP" : "",
                bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height);
            if (child is Gtk.Image || child is Gtk.Label) {
                foreach (var line in child.get_style_context ().to_string (Gtk.StyleContextPrintFlags.SHOW_STYLE).split ("\n")) {
                    var t = line.strip ();
                    if (t.has_prefix ("filter") || t.has_prefix ("-gtk-icon-filter") || t.has_prefix ("opacity") || t.has_prefix ("color:")) {
                        message ("%*s  css: %s", depth * 2, "", t);
                    }
                }
            }
            debug_sensitive_tree (child, depth + 1);
        }
    }

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
                debug ("window is-active -> %s", is_active.to_string ());
                if (
                    is_active &&
                    player.state != Player.State.PLAYING
                ) {
                    int64 t = get_monotonic_time ();
                    yam_talker.update_all.begin ((obj, res) => {
                        debug ("update_all done in %.0f ms", (get_monotonic_time () - t) / 1000.0);
                    });
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

    void save_snapshot (string path) {
        try {
            var paintable = new Gtk.WidgetPaintable (this);
            var snapshot = new Gtk.Snapshot ();
            paintable.snapshot (snapshot, get_width (), get_height ());
            var node = snapshot.free_to_node ();
            if (node != null) {
                var texture = get_renderer ().render_texture (node, null);
                texture.save_to_png (path);
            }
        } catch (Error e) {
            warning ("snapshot %s: %s", path, e.message);
        }
    }

    void debug_pixbuf_stress (int threads) {
        // Any cached image files will do.
        var dir = Client.storager.cache_images_dir_file;
        string[] files = {};
        try {
            var children = dir.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
            FileInfo? info;
            while ((info = children.next_file ()) != null && files.length < 8) {
                files += dir.get_child (info.get_name ()).peek_path ();
            }
        } catch (Error e) {
            warning ("pixbuf stress: %s", e.message);
            return;
        }
        message ("pixbuf stress: %d threads over %d files", threads, files.length);
        if (files.length == 0) {
            return;
        }
        for (int t = 0; t < threads; t++) {
            int thread_no = t;
            new Thread<void> ("pixbuf-stress", () => {
                int ok = 0;
                for (int i = 0; i < 300; i++) {
                    try {
                        uint8[] data;
                        FileUtils.get_data (files[(i + thread_no) % files.length], out data);
                        Client.Cachier.Storager.simple_dencode_public (ref data);
                        var stream = new MemoryInputStream.from_data (data);
                        var pixbuf = new Gdk.Pixbuf.from_stream (stream);
                        if (pixbuf != null) {
                            ok++;
                        }
                    } catch (Error e) {
                        // decode errors are fine here; a crash is what we look for
                    }
                }
                Idle.add_once (() => message ("pixbuf stress: thread %d done, %d decoded", thread_no, ok));
            });
        }
    }

    void debug_fonts () {
        message ("%s", font_report ());
    }

    /**
     * What Pango really uses: default font, the font of every run of a few
     * sample strings, whether the bundled font directory exists, and the
     * font families fontconfig knows. Shown by the "Font check" dialog so a
     * screenshot from a device without adb is enough to diagnose.
     */
    public string font_report () {
        var report = new StringBuilder ();
        var context = get_pango_context ();
        report.append_printf ("default font: %s\n", context.get_font_description ().to_string ());
        report.append_printf ("FONTCONFIG_FILE: %s\n", Environment.get_variable ("FONTCONFIG_FILE") ?? "(unset)");
        report.append_printf ("setup: %s\n", Environment.get_variable ("CASSETTE_FONTS_STATUS") ?? "(not run)");
        report.append_printf ("XDG_CONFIG_HOME: %s\n", Environment.get_variable ("XDG_CONFIG_HOME") ?? "(unset)");
        report.append_printf ("LANGUAGE: %s, languages: %s, _(\"Liked\") = %s\n",
            Environment.get_variable ("LANGUAGE") ?? "(unset)",
            string.joinv (",", Intl.get_language_names ()), _("Liked"));
        foreach (var dir in Environment.get_system_data_dirs ()) {
            var inter = Path.build_filename (dir, "fonts", "Inter", "Inter-Regular.ttf");
            if (FileUtils.test (inter, FileTest.EXISTS)) {
                report.append_printf ("bundled Inter: %s\n", inter);
            }
        }
        string[] samples = {
            "Play next 3:27", "Карнавал SØMN", "開 關 中文 日本語 漢字 テスト", "<b>Bold Latin</b>",
            "<span weight=\"300\">Light</span>",
            "<span font_family=\"Press Start 2P\">Test</span>"
        };
        foreach (var sample in samples) {
            var layout = new Pango.Layout (context);
            layout.set_markup (sample, -1);
            var iter = layout.get_iter ();
            do {
                unowned Pango.LayoutRun? run = iter.get_run_readonly ();
                if (run != null) {
                    var font = run.item.analysis.font;
                    report.append_printf ("\"%s\" → %s (%s %s)\n", sample,
                        font.describe ().to_string (), font.get_face ().get_family ().get_name (),
                        font.get_face ().get_face_name ());
                }
            } while (iter.next_run ());
        }
        Pango.FontFamily[] families;
        context.list_families (out families);
        var names = new StringBuilder ();
        foreach (var family in families) {
            names.append (family.get_name ()).append ("; ");
        }
        report.append_printf ("fontconfig families (%d): %s", families.length, names.str);
        return report.str;
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
