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
using Gee;

namespace Cassette {

    public enum SortType {
        NAME,
        ARTISTS,
        ALBUM,
        DURATION
    }

    public enum SortDirection {
        ASCENDING,
        DESCENDING
    }

    /** What a row of the list represents. */
    public enum TrackRowKind {
        DEFAULT,    // playlist row: like, dislike hidden, options
        BASE,       // plain row
        DISLIKED,   // row with the dislike button
        QUEUE       // queue row with position
    }

    /** Model item: one track of the list. */
    public class TrackItem : Object {
        public YaMAPI.Track track_info { get; construct; }
        public HasTrackList? yam_object { get; construct; }
        public TrackRowKind kind { get; construct; }
        public int position { get; construct; }

        public TrackItem (YaMAPI.Track track_info, HasTrackList? yam_object, TrackRowKind kind, int position) {
            Object (track_info: track_info, yam_object: yam_object, kind: kind, position: position);
        }
    }

    /** Model item: a widget that scrolls with the list (page header, toolbar, footer, empty state). */
    public class WidgetItem : Object {
        public Gtk.Widget widget { get; construct; }

        public WidgetItem (Gtk.Widget widget) {
            Object (widget: widget);
        }
    }

    /**
     * The track list: a `Gtk.ListView` over a model, so only the visible
     * rows exist as widgets and scrolling never depends on guessed row
     * heights (the old placeholder scheme shook the list on phones).
     *
     * It is the scrollable of its page: put it straight into the page's
     * `Gtk.ScrolledWindow`. Whatever the page shows above the tracks goes
     * into `header_widget`, whatever goes below into `footer_widget`;
     * both scroll with the rows as items of the same model. Search and
     * sorting are `Gtk.FilterListModel` / `Gtk.SortListModel` on top of
     * the tracks.
     */
    public class TrackList : Gtk.Widget, Gtk.Scrollable {

        // GtkListView is final, so the list wraps one and forwards the
        // scrollable interface to it: pages put a TrackList straight into
        // their Gtk.ScrolledWindow and it scrolls as a real list view.
        Gtk.ListView list_view;

        public Gtk.Adjustment hadjustment {
            get { ensure_list_view (); return list_view.hadjustment; }
            set construct { ensure_list_view (); list_view.hadjustment = value; }
        }
        public Gtk.Adjustment vadjustment {
            get { ensure_list_view (); return list_view.vadjustment; }
            set construct { ensure_list_view (); list_view.vadjustment = value; }
        }
        public Gtk.ScrollablePolicy hscroll_policy {
            get { return list_view.hscroll_policy; }
            set { list_view.hscroll_policy = value; }
        }
        public Gtk.ScrollablePolicy vscroll_policy {
            get { return list_view.vscroll_policy; }
            set { list_view.vscroll_policy = value; }
        }

        public bool get_border (out Gtk.Border border) {
            return list_view.get_border (out border);
        }

        static construct {
            set_layout_manager_type (typeof (Gtk.BinLayout));
        }

        public override void dispose () {
            if (list_view != null) {
                list_view.unparent ();
                list_view = null;
            }
            base.dispose ();
        }

        public int length {
            get {
                return (int) sort_model.get_n_items ();
            }
        }

        public SortType? sort_type = null;
        SortDirection sort_direction = SortDirection.ASCENDING;

        ListStore store = new ListStore (typeof (TrackItem));
        Gtk.FilterListModel filter_model;
        Gtk.SortListModel sort_model;
        Gtk.CustomFilter filter;
        Gtk.CustomSorter sorter;
        ListStore header_store = new ListStore (typeof (WidgetItem));
        ListStore toolbar_store = new ListStore (typeof (WidgetItem));
        ListStore empty_store = new ListStore (typeof (WidgetItem));
        ListStore footer_store = new ListStore (typeof (WidgetItem));

        Gtk.SearchEntry search_entry;
        Adw.Clamp toolbar;
        Gtk.Button sort_direction_button;
        Gtk.Button remove_sort_button;
        Adw.StatusPage status_page;

        YaMAPI.TrackType track_type = YaMAPI.TrackType.MUSIC;
        bool is_queue = false;

        /** Above the tracks (page header). Scrolls with the list. */
        public Gtk.Widget? header_widget {
            owned get {
                return header_store.get_n_items () > 0 ? ((WidgetItem) header_store.get_item (0)).widget : null;
            }
            set {
                header_store.remove_all ();
                if (value != null) {
                    header_store.append (new WidgetItem (value));
                }
                scroll_to_top ();
            }
        }

        /** Below the tracks (albums grid, more sections …). Scrolls with the list. */
        public Gtk.Widget? footer_widget {
            owned get {
                return footer_store.get_n_items () > 0 ? ((WidgetItem) footer_store.get_item (0)).widget : null;
            }
            set {
                footer_store.remove_all ();
                if (value != null) {
                    footer_store.append (new WidgetItem (value));
                }
            }
        }

        /** Search entry and sort buttons above the rows. */
        public bool show_toolbar {
            get {
                return toolbar_store.get_n_items () > 0;
            }
            set {
                toolbar_store.remove_all ();
                if (value) {
                    toolbar_store.append (new WidgetItem (toolbar));
                }
                scroll_to_top ();
            }
        }

        /** Rows narrower than this get side margins like the pages' clamps. */
        public int row_maximum_size { get; set; default = 1000; }

        /**
         * Becomes the content of @scrolled_window: whatever it held so far
         * (a template's page header) turns into the list's header item.
         */
        public void take_over (Gtk.ScrolledWindow scrolled_window) {
            var content = scrolled_window.child;
            if (content is Gtk.Viewport) {
                var viewport = (Gtk.Viewport) content;
                content = viewport.child;
                viewport.child = null;
            }
            scrolled_window.child = null;
            header_widget = content;
            scrolled_window.child = this;

            if (Environment.get_variable ("CASSETTE_DEBUG_SCROLL") != null) {
                vadjustment.value_changed.connect (() => {
                    debug ("scrollpos %.2f upper %.2f page %.2f", vadjustment.value, vadjustment.upper, vadjustment.page_size);
                });
            }
        }

        // Gtk.ListView keeps the first visible item in place when items are
        // inserted before it, so adding a header would hide it above the
        // toolbar. Pin the view to the top after changing the leading items.
        void scroll_to_top () {
            list_view.scroll_to (0, Gtk.ListScrollFlags.NONE, null);
        }

        public TrackList () {
            Object ();
        }

        void ensure_list_view () {
            if (list_view == null) {
                list_view = new Gtk.ListView (null, null) {
                    single_click_activate = true
                };
                list_view.add_css_class ("track-list");
                list_view.set_parent (this);
            }
        }

        construct {
            ensure_list_view ();

            build_toolbar ();
            status_page = new Adw.StatusPage () {
                icon_name = "emblem-music-symbolic",
                title = _("Nothing here"),
                vexpand = false
            };
            status_page.add_css_class ("compact");

            filter = new Gtk.CustomFilter (match_item);
            filter_model = new Gtk.FilterListModel (store, filter);
            sorter = new Gtk.CustomSorter ((a, b) => compare_items ((Object) a, (Object) b));
            sort_model = new Gtk.SortListModel (filter_model, null);

            var sections = new ListStore (typeof (ListModel));
            sections.append (header_store);
            sections.append (toolbar_store);
            sections.append (empty_store);
            sections.append (sort_model);
            sections.append (footer_store);
            var flat = new Gtk.FlattenListModel (sections);

            list_view.model = new Gtk.NoSelection (flat);
            list_view.factory = build_factory ();

            show_toolbar = true;

            sort_model.items_changed.connect (() => {
                update_empty_state ();
            });
            update_empty_state ();

            search_entry.search_changed.connect (() => {
                filter.changed (Gtk.FilterChange.DIFFERENT);
            });
            Cassette.settings.changed.connect ((key) => {
                if (key == "explicit-visible" || key == "child-visible" || key == "available-visible") {
                    filter.changed (Gtk.FilterChange.DIFFERENT);
                }
            });

            list_view.activate.connect ((position) => {
                var item = list_view.model.get_item (position) as TrackItem;
                if (item == null) {
                    return;
                }
                // The row widget belongs to the list item; find it through
                // the focus-less path: the model position is stable, the
                // widget is not — rebuild the queue from the item instead.
                var row = row_widget_for (position);
                if (row != null) {
                    row.trigger ();
                }
            });
        }

        // ── toolbar ─────────────────────────────────────────────────────

        void build_toolbar () {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                margin_top = 8,
                margin_bottom = 4
            };
            toolbar = new Adw.Clamp () {
                maximum_size = row_maximum_size,
                margin_start = 12,
                margin_end = 12,
                child = box
            };
            var toolbar = box;

            search_entry = new Gtk.SearchEntry () {
                hexpand = true,
                placeholder_text = _("Search track")
            };
            search_entry.add_css_class ("transparent-background");
            toolbar.append (search_entry);

            var sort_label = new Gtk.Label (_("Sort by"));
            sort_label.add_css_class ("dim-label");
            toolbar.append (sort_label);

            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 1);
            toolbar.append (buttons);

            var menu = new Menu ();
            menu.append (_("name"), "tracklist.sort-name");
            menu.append (_("artist"), "tracklist.sort-artists");
            menu.append (_("album"), "tracklist.sort-album");
            menu.append (_("duration"), "tracklist.sort-duration");
            var sort_button = new Gtk.MenuButton () {
                icon_name = "pan-down-symbolic",
                menu_model = menu
            };
            sort_button.add_css_class ("flat");
            buttons.append (sort_button);

            sort_direction_button = new Gtk.Button.from_icon_name ("view-sort-ascending-symbolic");
            sort_direction_button.add_css_class ("flat");
            buttons.append (sort_direction_button);

            remove_sort_button = new Gtk.Button.from_icon_name ("window-close-symbolic") {
                visible = false
            };
            remove_sort_button.add_css_class ("flat");
            buttons.append (remove_sort_button);

            var actions = new SimpleActionGroup ();
            string[] names = { "sort-name", "sort-artists", "sort-album", "sort-duration" };
            SortType[] types = { SortType.NAME, SortType.ARTISTS, SortType.ALBUM, SortType.DURATION };
            for (int i = 0; i < names.length; i++) {
                var type = types[i];
                var action = new SimpleAction (names[i], null);
                action.activate.connect (() => {
                    sort_type = type;
                    apply_sort ();
                });
                actions.add_action (action);
            }
            insert_action_group ("tracklist", actions);

            sort_direction_button.clicked.connect (() => {
                if (sort_direction == SortDirection.ASCENDING) {
                    sort_direction = SortDirection.DESCENDING;
                    sort_direction_button.icon_name = "view-sort-descending-symbolic";
                } else {
                    sort_direction = SortDirection.ASCENDING;
                    sort_direction_button.icon_name = "view-sort-ascending-symbolic";
                }
                apply_sort ();
            });
            remove_sort_button.clicked.connect (() => {
                sort_type = null;
                apply_sort ();
            });
        }

        // ── filtering and sorting ───────────────────────────────────────

        bool match_item (Object obj) {
            var item = (TrackItem) obj;
            var track = item.track_info;
            if (search_entry.text != "") {
                var needle = search_entry.text.down ();
                return needle in (track.title ?? "").down () ||
                    needle in track.get_artists_names ().down ();
            }
            if (item.kind == TrackRowKind.QUEUE) {
                return true;
            }
            bool show_explicit = Cassette.settings.get_boolean ("explicit-visible");
            bool show_child = Cassette.settings.get_boolean ("child-visible");
            bool show_unavailable = Cassette.settings.get_boolean ("available-visible");
            return track.track_type == track_type &&
                (track.available || show_unavailable) &&
                (!track.is_explicit || show_explicit) &&
                (!track.is_suitable_for_children || show_child);
        }

        static int compare_strings (string a, string b) {
            return strcmp (a.down (), b.down ());
        }

        int compare_items (Object a_obj, Object b_obj) {
            var a = ((TrackItem) a_obj).track_info;
            var b = ((TrackItem) b_obj).track_info;
            int result = 0;
            switch (sort_type) {
                case SortType.NAME:
                    result = compare_strings (a.title ?? "", b.title ?? "");
                    break;
                case SortType.ARTISTS:
                    if (a.artists.size == 0 || b.artists.size == 0) {
                        result = (a.artists.size == 0 ? 0 : 1) - (b.artists.size == 0 ? 0 : 1);
                    } else {
                        result = compare_strings (a.get_artists_names (), b.get_artists_names ());
                    }
                    break;
                case SortType.ALBUM:
                    if (a.albums.size == 0 || b.albums.size == 0) {
                        result = (a.albums.size == 0 ? 0 : 1) - (b.albums.size == 0 ? 0 : 1);
                    } else {
                        result = compare_strings (a.albums[0].title ?? "", b.albums[0].title ?? "");
                    }
                    break;
                case SortType.DURATION:
                    result = (int) (a.duration_ms > b.duration_ms) - (int) (a.duration_ms < b.duration_ms);
                    break;
                default:
                    // No sort type: keep the original order, or reverse it.
                    result = 0;
                    break;
            }
            return sort_direction == SortDirection.ASCENDING ? result : -result;
        }

        void apply_sort () {
            if (sort_type == null) {
                sort_model.sorter = null;
                remove_sort_button.visible = false;
                if (sort_direction == SortDirection.DESCENDING && !is_queue) {
                    // "Reverse" without a key: the store order, backwards.
                    reverse_store ();
                    sort_direction = SortDirection.ASCENDING;
                    sort_direction_button.icon_name = "view-sort-ascending-symbolic";
                }
            } else {
                sort_model.sorter = sorter;
                sorter.changed (Gtk.SorterChange.DIFFERENT);
                remove_sort_button.visible = true;
            }
            sort_direction_button.visible = !is_queue || sort_type != null;
        }

        void reverse_store () {
            var items = new ArrayList<TrackItem> ();
            for (uint i = 0; i < store.get_n_items (); i++) {
                items.add ((TrackItem) store.get_item (i));
            }
            store.remove_all ();
            for (int i = items.size - 1; i >= 0; i--) {
                store.append (items[i]);
            }
        }

        public void sort () {
            apply_sort ();
        }

        void update_empty_state () {
            bool empty = sort_model.get_n_items () == 0 && store.get_n_items () > 0;
            if (empty && empty_store.get_n_items () == 0) {
                empty_store.append (new WidgetItem (status_page));
            } else if (!empty && empty_store.get_n_items () > 0) {
                empty_store.remove_all ();
            }
        }

        // ── rows ────────────────────────────────────────────────────────

        Gtk.ListItemFactory build_factory () {
            var f = new Gtk.SignalListItemFactory ();
            f.setup.connect ((obj) => {
                var list_item = (Gtk.ListItem) obj;
                list_item.activatable = true;
                list_item.focusable = false;
                list_item.child = new Adw.Bin ();
            });
            f.bind.connect ((obj) => {
                var list_item = (Gtk.ListItem) obj;
                var bin = (Adw.Bin) list_item.child;
                var item = list_item.item;
                if (item is WidgetItem) {
                    var widget = ((WidgetItem) item).widget;
                    if (widget.parent != null && widget.parent != bin) {
                        // Still bound to a recycled item that was not unbound yet.
                        ((Adw.Bin) widget.parent).child = null;
                    }
                    bin.child = widget;
                    list_item.activatable = false;
                } else if (item is TrackItem) {
                    bin.child = clamp_row (build_row ((TrackItem) item));
                    list_item.activatable = true;
                }
            });
            f.unbind.connect ((obj) => {
                var list_item = (Gtk.ListItem) obj;
                var bin = (Adw.Bin) list_item.child;
                bin.child = null;
            });
            return f;
        }

        Gtk.Widget clamp_row (Gtk.Widget row) {
            return new Adw.Clamp () {
                maximum_size = row_maximum_size,
                child = row
            };
        }

        Gtk.Widget build_row (TrackItem item) {
            switch (item.kind) {
                case TrackRowKind.BASE:
                    return new TrackBase (item.track_info, item.yam_object);
                case TrackRowKind.DISLIKED:
                    return new TrackDefault.with_dislike_button (item.track_info, item.yam_object);
                case TrackRowKind.QUEUE:
                    return new TrackQueue (item.track_info, item.position);
                default:
                    return new TrackDefault (item.track_info, item.yam_object);
            }
        }

        TrackRow? row_widget_for (uint position) {
            // The list item widgets are children of the list view; find the
            // one currently showing this position.
            for (var child = list_view.get_first_child (); child != null; child = child.get_next_sibling ()) {
                var bin = child.get_first_child () as Adw.Bin;
                if (bin == null) {
                    continue;
                }
                var clamp = bin.child as Adw.Clamp;
                var row = clamp != null ? clamp.child as TrackRow : bin.child as TrackRow;
                if (row == null) {
                    continue;
                }
                var item = list_view.model.get_item (position) as TrackItem;
                if (item != null && row.track_info == item.track_info) {
                    return row;
                }
            }
            return null;
        }

        // ── public API kept from the old list ───────────────────────────

        /** Scrolls the list so that the row @position is in view. */
        public void move_to (int position, int max) {
            uint offset = header_store.get_n_items () + toolbar_store.get_n_items () + empty_store.get_n_items ();
            if (position >= 0 && position < length) {
                list_view.scroll_to (offset + position, Gtk.ListScrollFlags.NONE, null);
            }
        }

        public void unload_all () { }

        public void load_all () { }

        public bool compare_tracks (ArrayList<YaMAPI.Track> track_list) {
            if (track_list.size != store.get_n_items ()) {
                return false;
            }
            for (int i = 0; i < track_list.size; i++) {
                if (track_list[i].id != ((TrackItem) store.get_item (i)).track_info.id) {
                    return false;
                }
            }
            return true;
        }

        void set_items (ArrayList<YaMAPI.Track> track_list, HasTrackList? yam_object, TrackRowKind kind) {
            var items = new Object[track_list.size];
            for (int i = 0; i < track_list.size; i++) {
                items[i] = new TrackItem (track_list[i], yam_object, kind, i);
            }
            store.splice (0, store.get_n_items (), items);
            update_empty_state ();
        }

        public void set_tracks_default (ArrayList<YaMAPI.Track> track_list, YaMAPI.Playlist yam_object) {
            is_queue = false;
            set_items (track_list, yam_object, TrackRowKind.DEFAULT);
        }

        public void set_tracks_base (ArrayList<YaMAPI.Track> track_list, HasTrackList yam_object) {
            is_queue = false;
            set_items (track_list, yam_object, TrackRowKind.BASE);
        }

        public void set_tracks_disliked (ArrayList<YaMAPI.Track> track_list, HasTrackList yam_object) {
            is_queue = false;
            set_items (track_list, yam_object, TrackRowKind.DISLIKED);
        }

        public void set_tracks_as_queue (ArrayList<YaMAPI.Track> track_list) {
            is_queue = true;
            sort_direction_button.visible = sort_type != null;
            set_items (track_list, null, TrackRowKind.QUEUE);
        }

        public void set_tracks_with_positions (ArrayList<YaMAPI.Track> track_list) {
            set_tracks_as_queue (track_list);
        }

        public void clear_all () {
            store.remove_all ();
            update_empty_state ();
        }
    }

    /**
     * A short, non-virtual list (the sidebar's "similar tracks"): plain
     * rows in a box, for places that already live inside another scroller.
     */
    public class SimpleTrackList : Gtk.Box {

        public SimpleTrackList () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        }

        public void set_tracks_base (ArrayList<YaMAPI.Track> track_list, HasTrackList yam_object) {
            while (get_first_child () != null) {
                remove (get_first_child ());
            }
            foreach (var track_info in track_list) {
                var row = new TrackBase (track_info, yam_object);
                var click = new Gtk.GestureClick ();
                click.released.connect (() => {
                    row.trigger ();
                });
                row.add_controller (click);
                append (row);
            }
        }
    }
}
