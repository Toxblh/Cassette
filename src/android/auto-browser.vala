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


/**
 * Android Auto browse tree. The car asks Java, Java asks native, native hops
 * here on the GLib main loop; the network work runs on a worker thread
 * (threader.add + yield, like the views) and the reply goes back through JNI
 * (Java posts it to its looper).
 *
 * Media ids are "track|<ctxType>|<ctxId>|<index>|<trackId>" so a play request
 * can rebuild the queue without a lookup; "station|<id>" starts a rotor wave.
 */
namespace Cassette.Client.AndroidAuto {

class QueueResult {
    public Gee.ArrayList<YaMAPI.Track>? queue;
    public string ctx_type = "various";
    public string? ctx_id;
    public int index = 0;
    public string? desc;
}

// Fetched browse trees, so re-opening a collection does not hit the network
// again (the car caches too, but re-browses between sessions).
const int64 CACHE_TTL_USEC = 5 * 60 * 1000000;

class BrowseCache {
    HashTable<string, string> json = new HashTable<string, string> (str_hash, str_equal);
    HashTable<string, int64?> time = new HashTable<string, int64?> (str_hash, str_equal);

    public string? get (string parent) {
        var when = time.lookup (parent);
        if (when == null || GLib.get_monotonic_time () - when > CACHE_TTL_USEC) {
            return null;
        }
        return json.lookup (parent);
    }

    public void put (string parent, string value) {
        json.insert (parent, value);
        time.insert (parent, GLib.get_monotonic_time ());
    }
}

static BrowseCache? browse_cache;

static string? cached (string parent) {
    return browse_cache == null ? null : browse_cache.get (parent);
}

static void store (string parent, string value) {
    // Never cache an empty/failed result: the next request should retry.
    if (browse_cache != null && value.length > 4) {
        browse_cache.put (parent, value);
    }
}

public static void init () {
    browse_cache = new BrowseCache ();
    cassette_android_auto_init (on_browse, on_play_media_id, on_play_from_search);
}

// ── incoming from the car ────────────────────────────────────────────────

static void on_browse (string parent_id, int64 request_id) {
    browse.begin (parent_id.dup (), request_id);
}

static async void browse (string parent, int64 request_id) {
    string? hit = cached (parent);
    if (hit != null) {
        cassette_android_auto_browse_result (request_id, hit);
        return;
    }

    string json = "[ ]";
    threader.add (() => {
        try {
            json = build (parent);
        } catch (Error e) {
            warning ("auto browse %s: %s", parent, e.message);
        }
        Idle.add (browse.callback);
    });
    yield;
    store (parent, json);
    cassette_android_auto_browse_result (request_id, json);
}

static void on_play_media_id (string media_id) {
    string id = media_id.dup ();
    if (id.has_prefix ("station|")) {
        player.start_flow (id.substring (8));
        return;
    }
    play_media.begin (id);
}

static async void play_media (string id) {
    QueueResult? result = null;
    threader.add (() => {
        result = resolve_queue (id);
        Idle.add (play_media.callback);
    });
    yield;
    if (result == null || result.queue == null || result.queue.size == 0) {
        return;
    }
    player.start_track_list (result.queue, result.ctx_type, result.ctx_id, result.index, result.desc);
}

static void on_play_from_search (string query) {
    search.begin (query.dup ());
}

static async void search (string text) {
    Gee.ArrayList<YaMAPI.Track>? queue = null;
    threader.add (() => {
        try {
            var result = yam_talker.search (text);
            if (result != null) {
                queue = result.get_filtered_track_list (
                    Cassette.settings.get_boolean ("explicit-visible"),
                    Cassette.settings.get_boolean ("child-visible")
                );
            }
        } catch (Error e) {
            warning ("auto search %s: %s", text, e.message);
        }
        Idle.add (search.callback);
    });
    yield;
    if (queue == null || queue.size == 0) {
        return;
    }
    player.start_track_list (queue, "search", text, 0, text);
}

// ── browse tree ──────────────────────────────────────────────────────────

static string build (string parent) throws Error {
    if (parent == "root") {
        var items = new Gee.ArrayList<string> ();
        items.add (item_json ("liked", "Liked", "", false, "builtin:emblem-favorite-symbolic"));
        items.add (item_json ("playlists", "Playlists", "", false, "builtin:view-list-symbolic"));
        items.add (item_json ("stations", "Stations", "", false, "builtin:wave-my-wave-symbolic"));
        return array_json (items);
    }

    if (parent == "liked") {
        var playlist = yam_talker.get_playlist_info_old (null, "3");
        if (playlist == null) {
            return "[ ]";
        }
        return track_array (playlist.get_track_list (), "liked", "3");
    }

    if (parent == "playlists") {
        var items = new Gee.ArrayList<string> ();
        var own = yam_talker.get_playlist_list (null);
        if (own != null) {
            foreach (var playlist in own) {
                if (playlist.playlist_uuid == null) {
                    continue;
                }
                items.add (item_json ("playlist|" + playlist.playlist_uuid, playlist.title, ""));
            }
        }
        var liked = yam_talker.get_likes_playlist_list (null);
        if (liked != null) {
            foreach (var entry in liked) {
                if (entry.playlist.playlist_uuid == null) {
                    continue;
                }
                items.add (item_json ("playlist|" + entry.playlist.playlist_uuid, entry.playlist.title, ""));
            }
        }
        return array_json (items);
    }

    if (parent.has_prefix ("playlist|")) {
        string uuid = parent.substring (9);
        var playlist = yam_talker.get_playlist_info (uuid);
        if (playlist == null) {
            return "[ ]";
        }
        return track_array (playlist.get_track_list (), "playlist", uuid);
    }

    if (parent == "stations") {
        var items = new Gee.ArrayList<string> ();
        try {
            yam_talker.init_if_not ();
            var stations = yam_talker.client.rotor_stations_list ();
            if (stations != null) {
                foreach (var station in stations) {
                    var info = station.station;
                    if (info == null || info.id == null) {
                        continue;
                    }
                    string id = info.id.normal ?? "";
                    if (id == "") {
                        continue;
                    }
                    string icon_name = info.icon != null
                        ? info.icon.get_internal_icon_name (id) : "music-note-symbolic";
                    items.add (item_json ("station|" + id, info.name, "", true, "builtin:" + icon_name));
                }
            }
        } catch (Error e) {
            warning ("auto stations: %s", e.message);
        }
        return array_json (items);
    }

    return "[ ]";
}

static QueueResult? resolve_queue (string media_id) {
    var parts = media_id.split ("|");
    if (parts.length != 5 || parts[0] != "track") {
        return null;
    }

    var result = new QueueResult ();
    result.ctx_type = parts[1];
    result.ctx_id = parts[2];
    result.index = int.parse (parts[3]);

    try {
        if (result.ctx_type == "liked") {
            var playlist = yam_talker.get_playlist_info_old (null, "3");
            if (playlist == null) {
                return null;
            }
            result.desc = playlist.title;
            result.queue = playlist.get_track_list ();
        } else if (result.ctx_type == "playlist") {
            var playlist = yam_talker.get_playlist_info (result.ctx_id);
            if (playlist == null) {
                return null;
            }
            result.desc = playlist.title;
            result.queue = playlist.get_track_list ();
        } else if (result.ctx_type == "search") {
            var search_result = yam_talker.search (result.ctx_id);
            if (search_result == null) {
                return null;
            }
            result.desc = result.ctx_id;
            result.queue = search_result.get_filtered_track_list (
                Cassette.settings.get_boolean ("explicit-visible"),
                Cassette.settings.get_boolean ("child-visible")
            );
        } else {
            return null;
        }
    } catch (Error e) {
        warning ("auto queue %s: %s", media_id, e.message);
        return null;
    }

    return result;
}

// ── json ─────────────────────────────────────────────────────────────────

static string track_array (Gee.ArrayList<YaMAPI.Track> tracks, string ctx_type, string ctx_id) {
    var items = new Gee.ArrayList<string> ();
    for (int i = 0; i < tracks.size; i++) {
        var track = tracks[i];
        string icon = "";
        var covers = track.get_cover_items_by_size ((int) CoverSize.SMALL);
        if (covers.size > 0) {
            icon = covers[0];
        }
        string id = "track|%s|%s|%d|%s".printf (ctx_type, ctx_id, i, track.id);
        items.add (item_json (id, track.title ?? "", track.get_artists_names (), true, icon));
    }
    return array_json (items);
}

static string array_json (Gee.ArrayList<string> items) {
    var builder = new StringBuilder ("[");
    for (int i = 0; i < items.size; i++) {
        if (i > 0) {
            builder.append (",");
        }
        builder.append (items[i]);
    }
    builder.append ("]");
    return builder.str;
}

static string item_json (string id, string? title, string? subtitle, bool playable = false, string? icon = null) {
    var builder = new StringBuilder ("{");
    builder.append_printf ("\"id\":\"%s\",\"title\":\"%s\",\"subtitle\":\"%s\",\"playable\":%s",
        escape (id), escape (title ?? ""), escape (subtitle ?? ""), playable ? "true" : "false");
    if (icon != null && icon != "") {
        builder.append_printf (",\"icon\":\"%s\"", escape (icon));
    }
    builder.append ("}");
    return builder.str;
}

static string escape (string text) {
    var builder = new StringBuilder ();
    unichar c;
    int i = 0;
    while (text.get_next_char (ref i, out c)) {
        switch (c) {
            case '"':  builder.append ("\\\""); break;
            case '\\': builder.append ("\\\\"); break;
            case '\n': builder.append ("\\n");  break;
            case '\r': builder.append ("\\r");  break;
            case '\t': builder.append ("\\t");  break;
            default:
                if (c < 0x20) {
                    builder.append_printf ("\\u%04x", c);
                } else {
                    builder.append_unichar (c);
                }
                break;
        }
    }
    return builder.str;
}

// The car cannot render our bundled symbolic SVGs, and the browser service
// can run without a window (no Gdk.Display). Both station icons and the root
// tabs are therefore referenced as `builtin:<app icon>`; the app's SVG icons
// are converted to Android vector drawables at build time and the provider
// rasterises them through the framework.

}
