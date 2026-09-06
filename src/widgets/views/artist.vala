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
using Gee;

namespace Cassette {

    /**
     * Pieces shared by the artist, album and search pages: the page
     * skeleton (scrolled clamp with a header) and the rows that open
     * other pages.
     */
    namespace EntityPages {

        public Gtk.Label section_title (string text) {
            var label = new Gtk.Label (text) {
                xalign = 0,
                margin_top = 12,
                margin_bottom = 4
            };
            label.add_css_class ("title-3");
            return label;
        }

        /** A list row with a cover, opening a page when activated. */
        public Adw.ActionRow entity_row (HasCover? cover_object, string title, string? subtitle) {
            var row = new Adw.ActionRow () {
                title = Markup.escape_text (title),
                subtitle = subtitle != null ? Markup.escape_text (subtitle) : null,
                activatable = true
            };
            var cover = new CoverImage () {
                cover_size = CoverSize.SMALL,
                image_widget_size = 48,
                valign = Gtk.Align.CENTER
            };
            if (cover_object != null) {
                cover.init_content (cover_object);
                cover.load_image.begin ();
            }
            row.add_prefix (cover);
            row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            return row;
        }

        public Gtk.ListBox entity_list () {
            var list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.NONE
            };
            list.add_css_class ("boxed-list");
            return list;
        }

        /** Album card for a grid: cover, title, year. */
        public Gtk.Widget album_card (YaMAPI.Album album, PageRoot root_view) {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                width_request = 132
            };
            var cover = new CoverImage () {
                cover_size = CoverSize.BIG,
                image_widget_size = 120,
                halign = Gtk.Align.CENTER
            };
            cover.init_content (album);
            cover.load_image.begin ();
            box.append (cover);
            var title = new Gtk.Label (album.title ?? "") {
                ellipsize = Pango.EllipsizeMode.END,
                max_width_chars = 14,
                justify = Gtk.Justification.CENTER,
                wrap = true,
                lines = 2
            };
            title.add_css_class ("heading");
            box.append (title);
            if (album.year > 0) {
                var year = new Gtk.Label (album.year.to_string ());
                year.add_css_class ("dim-label");
                year.add_css_class ("caption");
                box.append (year);
            }
            var button = new Gtk.Button () {
                child = box,
                valign = Gtk.Align.START
            };
            button.add_css_class ("flat");
            button.clicked.connect (() => {
                root_view.add_view (new AlbumView (album.id));
            });
            return button;
        }

        public string artists_names (ArrayList<YaMAPI.Artist> artists) {
            var names = new StringBuilder ();
            foreach (var artist in artists) {
                if (names.len > 0) {
                    names.append (", ");
                }
                names.append (artist.name ?? "");
            }
            return names.str;
        }
    }

    /**
     * Artist page: cover, name, genres, popular tracks (playable) and the
     * albums grid. Opened from track authors and from search.
     */
    public class ArtistView : HasTracksView {

        public string artist_id { get; construct; }

        public override bool can_refresh {
            get {
                return true;
            }
        }

        Gtk.ScrolledWindow scrolled_window;
        Gtk.Box header_box;
        CoverImage cover_image;
        Gtk.Label name_label;
        Gtk.Label details_label;
        Gtk.Button play_button;
        Gtk.Label tracks_title;
        Gtk.Label albums_title;
        Gtk.FlowBox albums_flow;

        public ArtistView (string artist_id) {
            Object (artist_id: artist_id);
        }

        construct {
            scrolled_window = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.NEVER
            };
            child = scrolled_window;

            var clamp = new Adw.Clamp () {
                maximum_size = 1000,
                margin_start = 12,
                margin_end = 12,
                margin_top = 12,
                margin_bottom = 12
            };
            scrolled_window.child = clamp;

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            clamp.child = content;

            header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16);
            content.append (header_box);

            cover_image = new CoverImage () {
                cover_size = CoverSize.BIG,
                image_widget_size = 200,
                valign = Gtk.Align.START
            };
            header_box.append (cover_image);

            var titles = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                valign = Gtk.Align.CENTER,
                hexpand = true
            };
            header_box.append (titles);

            name_label = new Gtk.Label ("") {
                xalign = 0,
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR
            };
            name_label.add_css_class ("title-1");
            titles.append (name_label);

            details_label = new Gtk.Label ("") {
                xalign = 0,
                wrap = true
            };
            details_label.add_css_class ("dim-label");
            titles.append (details_label);

            play_button = new Gtk.Button.from_icon_name ("media-playback-start-symbolic") {
                halign = Gtk.Align.START,
                margin_top = 6,
                sensitive = false,
                tooltip_text = _("Play popular tracks")
            };
            play_button.add_css_class ("suggested-action");
            play_button.add_css_class ("pill");
            play_button.clicked.connect (start_playing);
            titles.append (play_button);

            tracks_title = EntityPages.section_title (_("Popular tracks"));
            content.append (tracks_title);

            track_list = new TrackList (scrolled_window.vadjustment);
            content.append (track_list);

            albums_title = EntityPages.section_title (_("Albums"));
            content.append (albums_title);

            albums_flow = new Gtk.FlowBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                homogeneous = true,
                column_spacing = 8,
                row_spacing = 8,
                min_children_per_line = 2,
                max_children_per_line = 6
            };
            content.append (albums_flow);

            if (application.main_window != null) {
                application.main_window.bind_property (
                    "is-shrinked", header_box, "orientation",
                    BindingFlags.SYNC_CREATE,
                    (binding, src, ref target) => {
                        target.set_enum (src.get_boolean () ? Gtk.Orientation.VERTICAL : Gtk.Orientation.HORIZONTAL);
                        return true;
                    }
                );
                application.main_window.bind_property (
                    "is-shrinked", cover_image, "halign",
                    BindingFlags.SYNC_CREATE,
                    (binding, src, ref target) => {
                        target.set_enum (src.get_boolean () ? Gtk.Align.CENTER : Gtk.Align.START);
                        return true;
                    }
                );
            }
        }

        void set_values () {
            var info = (YaMAPI.ArtistBriefInfo) object_info;
            var artist = info.artist;

            name_label.label = artist != null ? (artist.name ?? "") : "";
            var details = new StringBuilder ();
            if (artist != null) {
                foreach (var genre in artist.genres) {
                    if (details.len > 0) {
                        details.append (", ");
                    }
                    details.append (genre);
                }
            }
            details_label.label = details.str;
            details_label.visible = details.len > 0;

            track_list.set_tracks_base (info.popular_tracks, info);
            play_button.sensitive = info.popular_tracks.size > 0;
            tracks_title.visible = info.popular_tracks.size > 0;

            while (albums_flow.get_first_child () != null) {
                albums_flow.remove (albums_flow.get_first_child ());
            }
            var albums = new ArrayList<YaMAPI.Album> ();
            albums.add_all (info.albums);
            albums.add_all (info.also_albums);
            foreach (var album in albums) {
                albums_flow.append (EntityPages.album_card (album, root_view));
            }
            albums_title.visible = albums.size > 0;
            albums_flow.visible = albums.size > 0;

            cover_image.init_content (info);
            cover_image.load_image.begin ();

            show_ready ();
        }

        public async override int try_load_from_web () {
            int code = 0;

            threader.add (() => {
                try {
                    object_info = yam_talker.get_artist_info (artist_id);
                } catch (BadStatusCodeError e) {
                    code = e.code;
                }

                Idle.add (try_load_from_web.callback);
            });

            yield;

            if (object_info != null) {
                set_values ();
                return -1;
            }
            return code;
        }

        public async override bool try_load_from_cache () {
            return false;
        }
    }
}
