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

namespace Cassette.Client.Glagol {

    public class GlagolClient : Object {

        public signal void player_state_received (PlayerState state);
        public signal void device_info_received ();
        public signal void disconnected ();
        public signal void error_occurred (string message);

        private Soup.Session session;
        private Soup.WebsocketConnection? ws_connection = null;
        private string device_token = "";
        private int ping_id = 0;
        private uint keepalive_source_id = 0;

        construct {
            session = new Soup.Session ();
        }

        public async void connect_async (string host, int port, string token) throws Error {
            device_token = token;
            // Glagol devices serve a self-signed TLS certificate on this port.
            var uri = "wss://%s:%d".printf (host, port);
            var msg = new Soup.Message ("GET", uri);
            msg.accept_certificate.connect ((cert, errors) => true);

            ws_connection = yield session.websocket_connect_async (
                msg, null, null, Priority.DEFAULT, null
            );

            // Incoming messages are handled via signals (the GLib main loop is the receive loop).
            ws_connection.message.connect (on_ws_message);
            ws_connection.closed.connect (on_ws_closed);
            ws_connection.error.connect (on_ws_error);

            // The device only pushes its current state in response to a ping,
            // so send one immediately rather than waiting for the keepalive interval.
            do_ping ();

            // Glagol keepalive: send a ping command every 30 seconds.
            keepalive_source_id = GLib.Timeout.add_seconds (30, () => {
                do_ping ();
                return GLib.Source.CONTINUE;
            });
        }

        public void close_connection () {
            stop_keepalive ();
            if (ws_connection != null &&
                ws_connection.state == Soup.WebsocketState.OPEN) {
                ws_connection.close ((ushort) Soup.WebsocketCloseCode.NORMAL, null);
            }
            ws_connection = null;
        }

        // ── JSON helpers ──────────────────────────────────────────────────────

        private string make_message (Json.Object payload) {
            var envelope = new Json.Object ();
            envelope.set_string_member ("conversationToken", device_token);
            envelope.set_string_member ("id", GLib.Uuid.string_random ());
            envelope.set_object_member ("payload", payload);
            envelope.set_int_member ("sentTime", (int64) (GLib.get_real_time () / 1000));

            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (envelope);
            return Json.to_string (node, false);
        }

        // send_command — public API for arbitrary JSON command + optional extra fields
        public void send_command (string command, Json.Object? params = null) {
            var payload = new Json.Object ();
            payload.set_string_member ("command", command);
            if (params != null) {
                params.foreach_member ((obj, name, node) => {
                    payload.set_member (name, node.copy ());
                });
            }
            send_payload (payload);
        }

        private void send_payload (Json.Object payload) {
            if (ws_connection == null ||
                ws_connection.state != Soup.WebsocketState.OPEN) {
                return;
            }
            ws_connection.send_text (make_message (payload));
        }

        // ── Keepalive ─────────────────────────────────────────────────────────

        private void do_ping () {
            var payload = new Json.Object ();
            payload.set_string_member ("command", "ping");
            payload.set_int_member ("pingId", ping_id++);
            send_payload (payload);
        }

        private void stop_keepalive () {
            if (keepalive_source_id > 0) {
                GLib.Source.remove (keepalive_source_id);
                keepalive_source_id = 0;
            }
        }

        // ── WebSocket signal handlers (= receive_loop) ────────────────────────

        private void on_ws_message (int type, GLib.Bytes message) {
            if (type != (int) Soup.WebsocketDataType.TEXT)
                return;

            var parser = new Json.Parser ();
            try {
                parser.load_from_data ((string) message.get_data ());
            } catch (Error e) {
                return;
            }

            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT)
                return;

            var root_obj = root.get_object ();

            if (root_obj.has_member ("state")) {
                var state_obj = root_obj.get_object_member ("state");
                player_state_received (PlayerState.from_json (state_obj));
            }

            if (root_obj.has_member ("deviceInfo")) {
                device_info_received ();
            }
        }

        private void on_ws_closed () {
            stop_keepalive ();
            ws_connection = null;
            disconnected ();
        }

        private void on_ws_error (GLib.Error err) {
            error_occurred (err.message);
        }

        // ── Playback controls ─────────────────────────────────────────────────

        public void play () {
            var p = new Json.Object ();
            p.set_string_member ("command", "play");
            send_payload (p);
        }

        public void pause () {
            // Glagol uses "stop" for pause
            var p = new Json.Object ();
            p.set_string_member ("command", "stop");
            send_payload (p);
        }

        public void next () {
            var p = new Json.Object ();
            p.set_string_member ("command", "next");
            send_payload (p);
        }

        public void prev () {
            var p = new Json.Object ();
            p.set_string_member ("command", "prev");
            send_payload (p);
        }

        public void set_volume (double volume) {
            var p = new Json.Object ();
            p.set_string_member ("command", "setVolume");
            p.set_double_member ("volume", volume.clamp (0.0, 1.0));
            send_payload (p);
        }

        public void rewind (double position) {
            var p = new Json.Object ();
            p.set_string_member ("command", "rewind");
            p.set_double_member ("position", position);
            send_payload (p);
        }

        public void send_text (string text) {
            var p = new Json.Object ();
            p.set_string_member ("command", "sendText");
            p.set_string_member ("text", text);
            send_payload (p);
        }

        public void play_music_url (string url, string format = "mp3") {
            var params_obj = new Json.Object ();
            params_obj.set_string_member ("type", format);

            var p = new Json.Object ();
            p.set_string_member ("command", "playMusic");
            p.set_string_member ("url", url);
            p.set_string_member ("type", "url");
            p.set_object_member ("parameters", params_obj);
            send_payload (p);
        }

        public void play_track (string track_id) {
            var p = new Json.Object ();
            p.set_string_member ("command", "playMusic");
            p.set_string_member ("id", track_id);
            p.set_string_member ("type", "track");
            send_payload (p);
        }

        public void set_repeat (string mode) {
            var p = new Json.Object ();
            p.set_string_member ("command", "repeat");
            p.set_string_member ("mode", mode);
            send_payload (p);
        }

        public void set_shuffle (bool shuffle) {
            var p = new Json.Object ();
            p.set_string_member ("command", "shuffle");
            p.set_boolean_member ("shuffled", shuffle);
            send_payload (p);
        }
    }
}
