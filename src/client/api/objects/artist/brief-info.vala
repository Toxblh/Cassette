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

    /**
     * /artists/{id}/brief-info: the artist, their albums and popular tracks.
     * The popular tracks are what the artist page plays.
     */
    public class ArtistBriefInfo : YaMObject, HasID, HasTrackList, HasCover {

        public string oid {
            owned get {
                return artist != null ? artist.id : "";
            }
        }

        public Artist? artist { get; set; }
        public ArrayList<Album> albums { get; set; default = new ArrayList<Album> (); }
        public ArrayList<Album> also_albums { get; set; default = new ArrayList<Album> (); }
        public ArrayList<Track> popular_tracks { get; set; default = new ArrayList<Track> (); }
        public ArrayList<Artist> similar_artists { get; set; default = new ArrayList<Artist> (); }

        public ArrayList<Track> get_filtered_track_list (
            bool show_explicit,
            bool show_child,
            string? exception_track_id = null
        ) {
            return filter_tracks (popular_tracks, show_explicit, show_child, exception_track_id);
        }

        public ArrayList<string> get_cover_items_by_size (int size) {
            if (artist == null) {
                return new ArrayList<string> ();
            }
            return artist.get_cover_items_by_size (size);
        }
    }

    /** Availability / explicit / children filter shared by the list-like objects. */
    public static ArrayList<Track> filter_tracks (
        ArrayList<Track> tracks,
        bool show_explicit,
        bool show_child,
        string? exception_track_id = null
    ) {
        var out_track_list = new ArrayList<Track> ();
        foreach (Track track in tracks) {
            if (
                (track.available &&
                    (
                        (!track.is_explicit || show_explicit) &&
                        (!track.is_suitable_for_children || show_child)
                    )
                ) || track.id == exception_track_id
            ) {
                out_track_list.add (track);
            }
        }
        return out_track_list;
    }
}
