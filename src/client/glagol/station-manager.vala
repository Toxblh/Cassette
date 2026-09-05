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

namespace Cassette.Client.Glagol {

    public static StationManager station_manager;

    /**
     * A speaker of the account: identity and name from quasar, address
     * from mDNS when it is on this network.
     */
    public class Station : Object {
        public string id { get; construct; }
        public string name { get; set; default = ""; }
        public string platform { get; set; default = ""; }
        public string? host { get; set; default = null; }
        public int port { get; set; default = 1961; }

        public bool online {
            get {
                return host != null;
            }
        }

        public string model {
            owned get {
                return GlagolDevice.platform_display_name (platform);
            }
        }

        public string display_name {
            owned get {
                return name != "" ? name : model;
            }
        }

        /** display_name without the brand prefix: "Станция Миди", not "Яндекс Станция Миди". */
        public string short_name {
            owned get {
                string n = display_name;
                foreach (var prefix in new string[] { "Яндекс ", "Yandex ", "Яндекс.", "Yandex." }) {
                    if (n.has_prefix (prefix) && n.length > prefix.length) {
                        return n.substring (prefix.length);
                    }
                }
                return n;
            }
        }

        public Station (string id) {
            Object (id: id);
        }
    }

    /**
     * Output routing: the app plays either here (Player) or on one
     * station, whose state is mirrored in {@link state}. Playback started
     * from the app while a station is active goes to the station.
     */
    public class StationManager : Object {

        public ListStore stations { get; default = new ListStore (typeof (Station)); }

        public Station? active { get; private set; default = null; }

        public PlayerState? state { get; private set; default = null; }

        public bool scanning { get; private set; default = false; }

        public bool connecting { get; private set; default = false; }

        /** Station state update (progress, volume, track, playing). */
        public signal void state_changed (PlayerState state);

        /** {@link active} changed: connected, switched, or back to local. */
        public signal void connection_changed ();

        /** Something the user should see (toast). */
        public signal void message (string text);

        GlagolClient? client = null;
        HashMap<string, string> device_tokens = new HashMap<string, string> ();
        HashMap<string, Station> by_id = new HashMap<string, Station> ();
        uint pause_after_transfer_source = 0;

        /** Merged list: account speakers, addresses from an mDNS scan. */
        public async void refresh () {
            if (scanning) {
                return;
            }
            scanning = true;

            var provider = new DeviceTokenProvider ();
            ArrayList<AccountDevice>? account = null;

            string? oauth = storager.db.get_additional_data ("oauth_token");
            if (oauth != null && oauth != "") {
                try {
                    account = yield provider.list_devices (oauth);
                } catch (Error e) {
                    Logger.warning ("Station list: %s".printf (e.message));
                }
            }

            var found = new HashMap<string, GlagolDevice> ();
            var discovery = new DeviceDiscovery ();
            discovery.device_found.connect ((device) => {
                found[device.device_id] = device;
            });
            try {
                yield discovery.scan_async (cached_hosts ());
            } catch (Error e) {
                Logger.warning ("Station scan: %s".printf (e.message));
            }

            if (account != null) {
                foreach (var device in account) {
                    Station station;
                    if (by_id.has_key (device.id)) {
                        station = by_id[device.id];
                    } else {
                        station = new Station (device.id);
                        by_id[device.id] = station;
                    }
                    station.name = device.name;
                    station.platform = device.platform;
                }
            }

            foreach (var station in by_id.values) {
                if (found.has_key (station.id)) {
                    var device = found[station.id];
                    station.host = device.host;
                    station.port = device.port;
                    if (station.platform == "" && device.platform != "") {
                        station.platform = device.platform;
                    }
                } else if (station != active) {
                    // A connected station stays reachable even if one scan missed it.
                    station.host = null;
                }
            }

            var sorted = new ArrayList<Station> ();
            sorted.add_all (by_id.values);
            sorted.sort ((a, b) => {
                if (a.online != b.online) {
                    return a.online ? -1 : 1;
                }
                return a.display_name.collate (b.display_name);
            });

            stations.remove_all ();
            foreach (var station in sorted) {
                stations.append (station);
            }

            remember_hosts ();
            scanning = false;
        }

        // "id=host" pairs of stations seen on the network, so the next scan
        // can ask them directly (multicast-filtered wifi, emulators).
        // Plain arrays on purpose: GSettings wants NULL-terminated strv,
        // which Gee's to_array () does not give.
        string[] cached_hosts () {
            string[] hosts = {};
            foreach (var entry in settings.get_strv ("station-hosts")) {
                var parts = entry.split ("=", 2);
                if (parts.length == 2 && parts[1] != "") {
                    hosts += parts[1];
                }
            }
            return hosts;
        }

        void remember_hosts () {
            string[] entries = {};
            foreach (var entry in settings.get_strv ("station-hosts")) {
                var parts = entry.split ("=", 2);
                if (parts.length == 2 && by_id.has_key (parts[0]) && !by_id[parts[0]].online) {
                    entries += entry;
                }
            }
            foreach (var station in by_id.values) {
                if (station.online) {
                    entries += "%s=%s".printf (station.id, station.host);
                }
            }
            settings.set_strv ("station-hosts", entries);
        }

        /**
         * On start-up: if the station playback was last sent to is on the
         * network and currently playing, pick it up again so the app opens
         * on what is actually sounding. Quiet otherwise.
         */
        public async void reconnect_last () {
            string last = settings.get_string ("last-station");
            if (last == "" || active != null) {
                return;
            }

            yield refresh ();

            if (!by_id.has_key (last) || !by_id[last].online || active != null) {
                return;
            }

            var station = by_id[last];
            try {
                yield connect_station (station);
            } catch (Error e) {
                Logger.info ("Not reconnecting to %s: %s".printf (station.display_name, e.message));
                return;
            }

            if (state == null || !state.playing) {
                disconnect_station ();
                return;
            }

            message (_("Playing on %s").printf (station.short_name));
        }

        async string get_device_token (Station station) throws Error {
            if (device_tokens.has_key (station.id)) {
                return device_tokens[station.id];
            }

            string? oauth = storager.db.get_additional_data ("oauth_token");
            if (oauth == null || oauth == "") {
                throw new IOError.PERMISSION_DENIED (_("Sign in to control stations"));
            }

            var provider = new DeviceTokenProvider ();
            string token = yield provider.get_token (oauth, station.id, station.platform);
            device_tokens[station.id] = token;
            return token;
        }

        /**
         * Connects and waits for the first state report. Replaces the
         * current connection if there is one.
         */
        public async void connect_station (Station station) throws Error {
            if (!station.online) {
                throw new IOError.HOST_UNREACHABLE (_("%s is not on this network").printf (station.display_name));
            }
            if (connecting) {
                throw new IOError.BUSY (_("Already connecting"));
            }

            connecting = true;
            try {
                string token = yield get_device_token (station);

                var new_client = new GlagolClient ();
                PlayerState? first_state = null;
                bool waiting = true;
                SourceFunc resume = connect_station.callback;

                new_client.player_state_received.connect ((s) => {
                    if (waiting) {
                        first_state = s;
                        waiting = false;
                        Idle.add ((owned) resume);
                        return;
                    }
                    if (new_client == client) {
                        on_state (s);
                    }
                });
                new_client.disconnected.connect (() => {
                    if (waiting) {
                        waiting = false;
                        Idle.add ((owned) resume);
                        return;
                    }
                    if (new_client == client) {
                        on_lost ();
                    }
                });
                new_client.error_occurred.connect ((text) => {
                    Logger.warning ("Station %s: %s".printf (station.display_name, text));
                });

                yield new_client.connect_async (station.host, station.port, token);

                uint timeout = Timeout.add_seconds (5, () => {
                    if (waiting) {
                        waiting = false;
                        Idle.add ((owned) resume);
                    }
                    return Source.REMOVE;
                });
                yield;
                Source.remove (timeout);

                if (first_state == null) {
                    new_client.close_connection ();
                    // A stale token is the usual reason for silence.
                    device_tokens.unset (station.id);
                    throw new IOError.TIMED_OUT (_("%s did not respond").printf (station.display_name));
                }

                drop_client ();
                client = new_client;
                active = station;
                settings.set_string ("last-station", station.id);
                on_state (first_state);
                connection_changed ();
            } finally {
                connecting = false;
            }
        }

        void drop_client () {
            if (client != null) {
                client.close_connection ();
                client = null;
            }
            cancel_pause_after_transfer ();
        }

        /** Back to local playback. The station keeps doing whatever it does. */
        public void disconnect_station () {
            if (client == null && active == null) {
                return;
            }
            drop_client ();
            active = null;
            state = null;
            connection_changed ();
        }

        void on_lost () {
            var name = active != null ? active.display_name : "";
            client = null;
            active = null;
            state = null;
            connection_changed ();
            message (_("Connection to %s lost").printf (name));
        }

        void on_state (PlayerState new_state) {
            state = new_state;
            state_changed (new_state);
        }

        // ── Moving playback ─────────────────────────────────────────────

        /**
         * Connects to the station and hands it what plays here: the same
         * track from the same position. Local playback pauses.
         */
        public async void transfer_to (Station station) throws Error {
            var current = player.mode.get_current_track_info ();
            double position = player.playback_pos_sec;
            bool was_playing = player.state == Player.State.PLAYING;

            yield connect_station (station);

            if (current == null) {
                return;
            }

            player.pause ();
            play_track (current.id);

            // The station needs a moment to load the track before it takes a seek.
            Timeout.add (700, () => {
                if (client != null && position > 1.0) {
                    client.rewind (position);
                }
                return Source.REMOVE;
            });

            if (!was_playing) {
                cancel_pause_after_transfer ();
                pause_after_transfer_source = Timeout.add (1500, () => {
                    pause_after_transfer_source = 0;
                    pause ();
                    return Source.REMOVE;
                });
            }
        }

        void cancel_pause_after_transfer () {
            if (pause_after_transfer_source != 0) {
                Source.remove (pause_after_transfer_source);
                pause_after_transfer_source = 0;
            }
        }

        /**
         * Takes the station's current track here, from its position, and
         * pauses the station. Falls back to plain disconnect when the
         * station plays nothing the app can load.
         */
        public async void take_back () {
            var last = state;
            var station = active;

            if (station == null) {
                return;
            }

            if (last != null && last.track_id != "" && last.playing) {
                pause ();
            }
            disconnect_station ();

            if (last == null || last.track_id == "") {
                return;
            }

            ArrayList<YaMAPI.Track>? tracks = null;
            threader.add (() => {
                tracks = yam_talker.get_tracks_info ({ last.track_id });
                Idle.add (take_back.callback);
            });
            yield;

            if (tracks == null || tracks.size == 0) {
                message (_("Couldn't load the track from %s").printf (station.display_name));
                return;
            }

            double position = last.progress;
            ulong handler = 0;
            handler = player.current_track_finish_loading.connect (() => {
                player.disconnect (handler);
                if (position > 1.0) {
                    player.seek ((int64) (position * 1000));
                }
                if (!last.playing) {
                    player.pause ();
                }
            });

            var queue = new ArrayList<YaMAPI.Track> ();
            queue.add (tracks[0]);
            player.start_track_list (queue, "various", null, 0, null);
        }

        /**
         * Playback started from the app while a station is active. A whole
         * playlist or album goes as such (the station builds the queue);
         * a single track from inside one goes as a track.
         */
        public void play_from_app (ArrayList<YaMAPI.Track> queue, string context_type, string? context_id, int index) {
            if (client == null) {
                return;
            }

            if (index == 0 && context_id != null && (context_type == "playlist" || context_type == "album" || context_type == "artist")) {
                play_context (context_type, context_id);
                return;
            }

            if (index >= 0 && index < queue.size) {
                play_track (queue[index].id);
            }
        }

        // ── Commands ────────────────────────────────────────────────────

        public void play () {
            if (client != null) {
                client.play ();
            }
        }

        public void pause () {
            if (client != null) {
                client.pause ();
            }
        }

        public void play_pause () {
            if (state != null && state.playing) {
                pause ();
            } else {
                play ();
            }
        }

        public void next () {
            if (client != null) {
                client.next ();
            }
        }

        public void prev () {
            if (client != null) {
                client.prev ();
            }
        }

        public void seek (double position_sec) {
            if (client != null) {
                client.rewind (position_sec);
            }
        }

        public void set_volume (double volume) {
            if (client != null) {
                client.set_volume (volume);
            }
        }

        public void play_track (string track_id) {
            if (client != null) {
                client.play_track (track_id);
            }
        }

        public void play_context (string type, string id) {
            if (client == null) {
                return;
            }
            var p = new Json.Object ();
            p.set_string_member ("id", id);
            p.set_string_member ("type", type);
            client.send_command ("playMusic", p);
        }
    }
}
