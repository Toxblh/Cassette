/* Copyright 2023-2024 Vladimir Vaskov
 * Copyright 2026 Anton Palgunov
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
 * GStreamer playbin behind the PlayerBackend contract. Desktop only.
 */
public class Cassette.Client.Player.GstPlayerBackend : PlayerBackend {

    static bool gst_inited = false;

    Gst.Element playbin;

    public override int64 position_ms {
        get {
            int64 cur;

            if (!playbin.query_position (Gst.Format.TIME, out cur)) {
                return 0;
            }

            return cur / Gst.MSECOND;
        }
    }

    construct {
        if (!gst_inited) {
            unowned string[]? args = null;
            Gst.init (ref args);
            gst_inited = true;
        }

        playbin = Gst.ElementFactory.make ("playbin", null);
        var bus = playbin.get_bus ();

        bus.add_signal_watch ();
        bus.message["eos"].connect ((bus, message) => {
            eos ();
        });
        bus.message["error"].connect ((bus, message) => {
            Error err;
            string debug;

            message.parse_error (out err, out debug);
            error (err.message);
        });

        bind_property ("volume", playbin, "volume", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
        bind_property ("mute", playbin, "mute", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
    }

    public override void set_uri (string? uri) {
        if (uri == null) {
            playbin.set_property ("uri", Value (Type.STRING));
        } else {
            playbin.set_property ("uri", uri);
        }
    }

    public override void play () {
        playbin.set_state (Gst.State.PLAYING);
    }

    public override void pause () {
        playbin.set_state (Gst.State.PAUSED);
    }

    public override void stop () {
        playbin.set_state (Gst.State.NULL);
    }

    public override void seek (int64 ms) {
        playbin.seek_simple (Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.KEY_UNIT, ms * Gst.MSECOND);
    }
}
