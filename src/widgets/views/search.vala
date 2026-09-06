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
     * Search results for one query: tracks (playable as a list), artists,
     * albums and playlists, each opening its page. The window reuses the
     * page for the next query instead of stacking pages.
     */
    public class SearchView : HasTracksView {

        public string query { get; set; }

        public override bool can_refresh {
            get {
                return true;
            }
        }

        Gtk.ScrolledWindow scrolled_window;
        Gtk.Label title_label;
        Gtk.Label tracks_title;
        Gtk.Button play_button;
        Gtk.Label artists_title;
        Gtk.ListBox artists_list;
        Gtk.Label albums_title;
        Gtk.ListBox albums_list;
        Gtk.Label playlists_title;
        Gtk.ListBox playlists_list;
        Gtk.Label nothing_label;

        public SearchView (string query) {
            Object (query: query);
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

            var head = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            content.append (head);

            title_label = new Gtk.Label ("") {
                xalign = 0,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END
            };
            title_label.add_css_class ("title-2");
            head.append (title_label);

            play_button = new Gtk.Button.from_icon_name ("media-playback-start-symbolic") {
                valign = Gtk.Align.CENTER,
                sensitive = false,
                tooltip_text = _("Play found tracks")
            };
            play_button.add_css_class ("suggested-action");
            play_button.add_css_class ("circular");
            play_button.clicked.connect (start_playing);
            head.append (play_button);

            nothing_label = new Gtk.Label (_("Nothing found")) {
                margin_top = 24,
                visible = false
            };
            nothing_label.add_css_class ("dim-label");
            content.append (nothing_label);

            tracks_title = EntityPages.section_title (_("Tracks"));
            content.append (tracks_title);
            track_list = new TrackList (scrolled_window.vadjustment);
            content.append (track_list);

            artists_title = EntityPages.section_title (_("Artists"));
            content.append (artists_title);
            artists_list = EntityPages.entity_list ();
            content.append (artists_list);

            albums_title = EntityPages.section_title (_("Albums"));
            content.append (albums_title);
            albums_list = EntityPages.entity_list ();
            content.append (albums_list);

            playlists_title = EntityPages.section_title (_("Playlists"));
            content.append (playlists_title);
            playlists_list = EntityPages.entity_list ();
            content.append (playlists_list);
        }

        static void clear_list (Gtk.ListBox list) {
            while (list.get_first_child () != null) {
                list.remove (list.get_first_child ());
            }
        }

        void set_values () {
            var result = (YaMAPI.SearchResult) object_info;
            title_label.label = _("Search: %s").printf (result.text ?? query);

            var tracks = result.tracks != null ? result.tracks.results : new ArrayList<YaMAPI.Track> ();
            track_list.set_tracks_base (tracks, result);
            tracks_title.visible = tracks.size > 0;
            track_list.visible = tracks.size > 0;
            play_button.sensitive = tracks.size > 0;

            clear_list (artists_list);
            var artists = result.artists != null ? result.artists.results : new ArrayList<YaMAPI.Artist> ();
            foreach (var artist in artists) {
                var row = EntityPages.entity_row (artist, artist.name ?? "", null);
                row.activated.connect (() => {
                    root_view.add_view (new ArtistView (artist.id));
                });
                artists_list.append (row);
            }
            if (artists.size > 0) {
                debug ("search: first artist %s (%s)", artists[0].name, artists[0].id);
            }
            artists_title.visible = artists.size > 0;
            artists_list.visible = artists.size > 0;

            clear_list (albums_list);
            var albums = result.albums != null ? result.albums.results : new ArrayList<YaMAPI.Album> ();
            foreach (var album in albums) {
                var subtitle = EntityPages.artists_names (album.artists);
                if (album.year > 0) {
                    subtitle = subtitle != "" ? "%s · %d".printf (subtitle, album.year) : album.year.to_string ();
                }
                var row = EntityPages.entity_row (album, album.title ?? "", subtitle);
                row.activated.connect (() => {
                    root_view.add_view (new AlbumView (album.id));
                });
                albums_list.append (row);
            }
            if (albums.size > 0) {
                debug ("search: first album %s (%s)", albums[0].title, albums[0].id);
            }
            albums_title.visible = albums.size > 0;
            albums_list.visible = albums.size > 0;

            clear_list (playlists_list);
            var playlists = result.playlists != null ? result.playlists.results : new ArrayList<YaMAPI.Playlist> ();
            foreach (var playlist in playlists) {
                var row = EntityPages.entity_row (playlist, playlist.title ?? "",
                    playlist.owner != null ? playlist.owner.name : null);
                row.activated.connect (() => {
                    root_view.add_view (new PlaylistView (playlist.uid, playlist.kind));
                });
                playlists_list.append (row);
            }
            playlists_title.visible = playlists.size > 0;
            playlists_list.visible = playlists.size > 0;

            nothing_label.visible = tracks.size + artists.size + albums.size + playlists.size == 0;

            show_ready ();
        }

        public async override int try_load_from_web () {
            int code = 0;
            string text = query;

            threader.add (() => {
                try {
                    object_info = yam_talker.search (text);
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
