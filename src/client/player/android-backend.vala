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
 * android.media.MediaPlayer behind the PlayerBackend contract, through the
 * C shim in src/android/android-player.c and PlayerBridge.java.
 *
 * The shim keeps one player per process, so the callbacks are static and
 * forward to the single instance. Callbacks arrive on the GLib main loop.
 */
public class Cassette.Client.Player.AndroidPlayerBackend : PlayerBackend {

    static AndroidPlayerBackend? instance = null;

    public override int64 position_ms {
        get {
            return cassette_android_player_position ();
        }
    }

    construct {
        instance = this;

        cassette_android_player_init (on_event, on_error);

        notify["volume"].connect (push_volume);
        notify["mute"].connect (push_volume);
    }

    void push_volume () {
        cassette_android_player_volume (volume, mute);
    }

    static void on_event (int event) {
        if (instance == null) {
            return;
        }

        switch ((AndroidPlayerEventType) event) {
            case AndroidPlayerEventType.EOS:
                instance.eos ();
                break;
            case AndroidPlayerEventType.FOCUS_LOST:
                instance.suspended ();
                break;
            case AndroidPlayerEventType.FOCUS_GAINED:
                instance.resumed ();
                break;
        }
    }

    static void on_error (string message) {
        if (instance != null) {
            instance.error (message);
        }
    }

    public override void set_uri (string? uri) {
        cassette_android_player_set_uri (uri);
    }

    public override void play () {
        push_volume ();
        cassette_android_player_play ();
    }

    public override void pause () {
        cassette_android_player_pause ();
    }

    public override void stop () {
        cassette_android_player_stop ();
    }

    public override void seek (int64 ms) {
        cassette_android_player_seek (ms);
    }
}
