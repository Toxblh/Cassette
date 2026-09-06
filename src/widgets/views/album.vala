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

    /** Album page: cover, title, artists (each opens their page), tracks. */
    public class AlbumView : HasTracksView {

        public string album_id { get; construct; }

        public override bool can_refresh {
            get {
                return true;
            }
        }

        Gtk.ScrolledWindow scrolled_window;
        Gtk.Box header_box;
        CoverImage cover_image;
        Gtk.Label title_label;
        Gtk.Box artists_box;
        Gtk.Label details_label;
        Gtk.Button play_button;

        public AlbumView (string album_id) {
            Object (album_id: album_id);
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

            title_label = new Gtk.Label ("") {
                xalign = 0,
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR
            };
            title_label.add_css_class ("title-1");
            titles.append (title_label);

            artists_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            titles.append (artists_box);

            details_label = new Gtk.Label ("") {
                xalign = 0,
                wrap = true
            };
            details_label.add_css_class ("dim-label");
            titles.append (details_label);

            play_button = new Gtk.Button.from_icon_name ("media-playback-start-symbolic") {
                halign = Gtk.Align.START,
                margin_top = 6,
                sensitive = false
            };
            play_button.add_css_class ("suggested-action");
            play_button.add_css_class ("pill");
            play_button.clicked.connect (start_playing);
            titles.append (play_button);

            track_list = new TrackList (scrolled_window.vadjustment);
            content.append (track_list);

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
            var album = (YaMAPI.Album) object_info;

            title_label.label = album.title ?? "";
            if (album.version != null && album.version != "") {
                title_label.label = "%s (%s)".printf (album.title ?? "", album.version);
            }

            while (artists_box.get_first_child () != null) {
                artists_box.remove (artists_box.get_first_child ());
            }
            foreach (var artist in album.artists) {
                var button = new Gtk.Button.with_label (artist.name ?? "") {
                    tooltip_text = _("Open artist")
                };
                button.add_css_class ("flat");
                button.clicked.connect (() => {
                    root_view.add_view (new ArtistView (artist.id));
                });
                artists_box.append (button);
            }
            artists_box.visible = album.artists.size > 0;

            var details = new StringBuilder ();
            if (album.year > 0) {
                details.append (album.year.to_string ());
            }
            if (album.genre != null && album.genre != "") {
                if (details.len > 0) {
                    details.append (" · ");
                }
                details.append (album.genre);
            }
            var tracks = album.get_track_list ();
            if (details.len > 0) {
                details.append (" · ");
            }
            details.append (ngettext ("%d track", "%d tracks", tracks.size).printf (tracks.size));
            details_label.label = details.str;

            track_list.set_tracks_base (tracks, album);
            play_button.sensitive = tracks.size > 0;

            cover_image.init_content (album);
            cover_image.load_image.begin ();

            show_ready ();
        }

        public async override int try_load_from_web () {
            int code = 0;

            threader.add (() => {
                try {
                    object_info = yam_talker.get_album_info (album_id);
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
