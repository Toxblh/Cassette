/* Copyright 2023-2024 Anton Palgunov
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

using Cassette.Client.Glagol;

int main (string[] args) {
    if (args.length < 2) {
        stderr.printf ("Usage: %s <host> [token]\n", args[0]);
        stderr.printf ("  host  — IP address of the Yandex Station (port 1961 is used)\n");
        stderr.printf ("  token — Glagol device token (from DeviceTokenProvider)\n");
        return 1;
    }

    string host = args[1];
    int port = 1961;
    string token = args.length >= 3 ? args[2] : "";

    var loop = new MainLoop ();
    var client = new GlagolClient ();

    client.player_state_received.connect ((state) => {
        stdout.printf ("--- Player State ---\n");
        stdout.printf ("  playing:   %s\n", state.playing ? "true" : "false");
        stdout.printf ("  volume:    %.2f\n", state.volume);
        stdout.printf ("  title:     %s\n", state.title);
        stdout.printf ("  artist:    %s\n", state.artist);
        stdout.printf ("  track_id:  %s\n", state.track_id);
        stdout.printf ("  duration:  %.1f s\n", state.duration);
        stdout.printf ("  progress:  %.1f s\n", state.progress);
        stdout.printf ("  alice:     %s\n", state.alice_state);
        stdout.printf ("  repeat:    %s\n", state.repeat_mode);
        stdout.printf ("  shuffled:  %s\n", state.shuffled ? "true" : "false");
        stdout.printf ("  cover_url: %s\n", state.get_cover_url ());
        stdout.printf ("\n");
    });

    client.disconnected.connect (() => {
        stdout.printf ("Disconnected.\n");
        loop.quit ();
    });

    client.error_occurred.connect ((msg) => {
        stderr.printf ("Error: %s\n", msg);
        loop.quit ();
    });

    GLib.Idle.add (() => {
        client.connect_async.begin (host, port, token, (obj, res) => {
            try {
                client.connect_async.end (res);
                stdout.printf ("Connected to %s:%d\n", host, port);
                stdout.printf ("Waiting for player state... (Ctrl+C to quit)\n");
            } catch (Error e) {
                stderr.printf ("Connection failed: %s\n", e.message);
                loop.quit ();
            }
        });
        return GLib.Source.REMOVE;
    });

    loop.run ();
    return 0;
}
