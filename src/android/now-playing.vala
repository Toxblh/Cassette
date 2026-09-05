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
 * Android MediaSession adapter. Mirrors whatever is the output: the local
 * Player, or the active Yandex station (its state, its volume through the
 * hardware keys, commands forwarded to it).
 */
namespace Cassette.Client.AndroidNowPlaying {

public static void init () {
    cassette_android_now_playing_init (
        on_cmd_play,
        on_cmd_pause,
        on_cmd_play_pause,
        on_cmd_next,
        on_cmd_prev,
        on_cmd_seek,
        on_cmd_like,
        on_cmd_volume
    );

    player.played.connect (on_played);
    player.paused.connect (on_paused);
    player.stopped.connect (on_local_stopped);
    player.track_stopped.connect (on_local_stopped);
    player.playback_callback.connect ((pos_sec) => {
        if (!remote ()) {
            cassette_android_now_playing_update_state (pos_sec, player.state == Player.State.PLAYING);
        }
    });

    yam_talker.track_likes_end_change.connect ((track_id, is_liked) => {
        if (track_id == current_track_id ()) {
            cassette_android_now_playing_set_liked (is_liked);
        }
    });

    Glagol.station_manager.connection_changed.connect (on_station_connection);
    Glagol.station_manager.state_changed.connect (on_station_state);
}

static bool remote () {
    return Glagol.station_manager.active != null;
}

static string? current_track_id () {
    if (remote ()) {
        var state = Glagol.station_manager.state;
        return state != null && state.track_id != "" ? state.track_id : null;
    }
    var track = player.mode.get_current_track_info ();
    return track != null ? track.id : null;
}

// MediaSession command callbacks — called on the GLib main loop via g_idle_add

static void on_cmd_play () {
    if (remote ()) {
        Glagol.station_manager.play ();
    } else {
        player.play ();
    }
}

static void on_cmd_pause () {
    if (remote ()) {
        Glagol.station_manager.pause ();
    } else {
        player.pause ();
    }
}

static void on_cmd_play_pause () {
    if (remote ()) {
        Glagol.station_manager.play_pause ();
    } else {
        player.play_pause ();
    }
}

static void on_cmd_next () {
    if (remote ()) {
        Glagol.station_manager.next ();
    } else if (player.can_go_next) {
        player.next ();
    }
}

static void on_cmd_prev () {
    if (remote ()) {
        Glagol.station_manager.prev ();
    } else if (player.can_go_prev) {
        player.prev ();
    }
}

static void on_cmd_seek (double position_sec) {
    if (remote ()) {
        Glagol.station_manager.seek (position_sec);
    } else {
        player.seek ((int64) (position_sec * 1000));
    }
}

// Heart in the system media controls: toggles the like of the current track.
static void on_cmd_like () {
    var track_id = current_track_id ();
    if (track_id == null) {
        return;
    }

    if (yam_talker.likes_controller.get_content_is_liked (LikableType.TRACK, track_id)) {
        yam_talker.unlike.begin (LikableType.TRACK, track_id);
    } else {
        yam_talker.like.begin (LikableType.TRACK, track_id);
    }
}

// Volume keys while a station plays.
static void on_cmd_volume (int percent) {
    if (remote ()) {
        Glagol.station_manager.set_volume (percent / 100.0);
    }
}

// Local player

static void on_played (YaMAPI.Track track) {
    if (!remote ()) {
        send_local_update (track, true);
    }
}

static void on_paused (YaMAPI.Track track) {
    if (!remote ()) {
        send_local_update (track, false);
    }
}

static void on_local_stopped () {
    if (!remote ()) {
        cassette_android_now_playing_clear ();
    }
}

static void send_local_update (YaMAPI.Track track, bool is_playing) {
    string artist = "";
    if (track.artists.size > 0 && track.artists[0].name != null) {
        artist = track.artists[0].name;
    }

    string? artwork_url = null;
    var covers = track.get_cover_items_by_size ((int) CoverSize.BIG);
    if (covers.size > 0) {
        artwork_url = covers[0];
    }

    cassette_android_now_playing_set_liked (
        yam_talker.likes_controller.get_content_is_liked (LikableType.TRACK, track.id)
    );

    cassette_android_now_playing_update (
        track.title ?? "",
        artist,
        track.get_album_title (),
        track.duration_ms / 1000.0,
        player.playback_pos_ms / 1000.0,
        is_playing,
        artwork_url
    );
}

// Station

static string? last_station_track;

static void on_station_connection () {
    if (remote ()) {
        last_station_track = null;
        var state = Glagol.station_manager.state;
        cassette_android_now_playing_set_remote_volume (true, state != null ? (int) (state.volume * 100) : 50);
        if (state != null) {
            on_station_state (state);
        }
    } else {
        cassette_android_now_playing_set_remote_volume (false, 0);
        last_station_track = null;
        // Whatever the local player does now becomes the session again.
        var track = player.mode.get_current_track_info ();
        if (track != null && player.state != Player.State.NONE) {
            send_local_update (track, player.state == Player.State.PLAYING);
        } else {
            cassette_android_now_playing_clear ();
        }
    }
}

static void on_station_state (Glagol.PlayerState state) {
    if (!remote ()) {
        return;
    }

    cassette_android_now_playing_set_remote_volume (true, (int) (state.volume * 100));

    if (state.track_id == "") {
        cassette_android_now_playing_clear ();
        last_station_track = null;
        return;
    }

    if (state.track_id != last_station_track) {
        last_station_track = state.track_id;
        cassette_android_now_playing_set_liked (
            yam_talker.likes_controller.get_content_is_liked (LikableType.TRACK, state.track_id)
        );
        string cover = state.get_cover_url (400);
        cassette_android_now_playing_update (
            state.title,
            state.artist,
            "",
            state.duration,
            state.progress,
            state.playing,
            cover != "" ? cover : null
        );
    } else {
        cassette_android_now_playing_update_state (state.progress, state.playing);
    }
}

}
