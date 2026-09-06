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

using Gee;

namespace Cassette.Client.YaMAPI {

    public class SearchTracks : YaMObject {
        public int total { get; set; }
        public ArrayList<Track> results { get; set; default = new ArrayList<Track> (); }
    }

    public class SearchArtists : YaMObject {
        public int total { get; set; }
        public ArrayList<Artist> results { get; set; default = new ArrayList<Artist> (); }
    }

    public class SearchAlbums : YaMObject {
        public int total { get; set; }
        public ArrayList<Album> results { get; set; default = new ArrayList<Album> (); }
    }

    public class SearchPlaylists : YaMObject {
        public int total { get; set; }
        public ArrayList<Playlist> results { get; set; default = new ArrayList<Playlist> (); }
    }

    /** /search?type=all: one page of everything that matched the text. */
    public class SearchResult : YaMObject, HasID, HasTrackList {

        public string oid {
            owned get {
                return text ?? "";
            }
        }

        public string? text { get; set; }
        public int page { get; set; }
        public SearchTracks? tracks { get; set; }
        public SearchArtists? artists { get; set; }
        public SearchAlbums? albums { get; set; }
        public SearchPlaylists? playlists { get; set; }

        public ArrayList<Track> get_filtered_track_list (
            bool show_explicit,
            bool show_child,
            string? exception_track_id = null
        ) {
            if (tracks == null) {
                return new ArrayList<Track> ();
            }
            return filter_tracks (tracks.results, show_explicit, show_child, exception_track_id);
        }
    }
}
