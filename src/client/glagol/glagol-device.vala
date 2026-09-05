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

    public class GlagolDevice : Object {
        public string host { get; set; default = ""; }
        public int port { get; set; default = 1961; }
        public string name { get; set; default = ""; }
        public string device_id { get; set; default = ""; }
        public string platform { get; set; default = ""; }
        public string version { get; set; default = ""; }

        public GlagolDevice (string host, int port, string name,
                             string device_id, string platform, string version) {
            Object (
                host: host,
                port: port,
                name: name,
                device_id: device_id,
                platform: platform,
                version: version
            );
        }

        /*
         * mDNS only exposes the device's platform code, not the room name
         * the user assigned to it in the Yandex app — fall back to a
         * human-readable model name based on the platform.
         */
        public string get_display_name () {
            if (name != "") {
                return name;
            }
            return platform_display_name (platform);
        }

        public static string platform_display_name (string platform) {
            switch (platform) {
                case "yandexstation":
                    return _("Yandex Station");
                case "yandexstation_2":
                    return _("Yandex Station Max");
                case "yandexmini":
                    return _("Yandex Station Mini");
                case "yandexmini_2":
                    return _("Yandex Station Mini 2");
                // Platform codes as quasar reports them for the account's devices.
                case "yandexmidi":
                    return _("Yandex Station 2");
                case "cucumber":
                    return _("Yandex Station Midi");
                case "yandexmicro":
                    return _("Yandex Station Lite");
                case "yandexmodule":
                case "chiron":
                    return _("Yandex Module");
                case "yandexmodule_2":
                case "chiron_2":
                    return _("Yandex Module 2");
                default:
                    return platform != "" ? platform : _("Yandex Station");
            }
        }
    }

    public class PlayerState : Object {
        public bool playing { get; set; default = false; }
        public double volume { get; set; default = 0.0; }
        public string track_id { get; set; default = ""; }
        public string title { get; set; default = ""; }
        public string artist { get; set; default = ""; }
        public double duration { get; set; default = 0.0; }
        public double progress { get; set; default = 0.0; }
        public bool has_prev { get; set; default = false; }
        public bool has_next { get; set; default = false; }
        public string repeat_mode { get; set; default = "None"; }
        public bool shuffled { get; set; default = false; }
        public string cover_uri { get; set; default = ""; }
        public string alice_state { get; set; default = "IDLE"; }

        public static PlayerState from_json (Json.Object state_obj) {
            var ps = new PlayerState ();

            if (state_obj.has_member ("playing"))
                ps.playing = state_obj.get_boolean_member ("playing");

            if (state_obj.has_member ("volume"))
                ps.volume = state_obj.get_double_member ("volume");

            if (state_obj.has_member ("aliceState"))
                ps.alice_state = state_obj.get_string_member ("aliceState");

            if (state_obj.has_member ("playerState")) {
                var player_obj = state_obj.get_object_member ("playerState");

                if (player_obj.has_member ("id"))
                    ps.track_id = player_obj.get_string_member ("id");
                if (player_obj.has_member ("title"))
                    ps.title = player_obj.get_string_member ("title");
                if (player_obj.has_member ("subtitle"))
                    ps.artist = player_obj.get_string_member ("subtitle");
                if (player_obj.has_member ("duration"))
                    ps.duration = player_obj.get_double_member ("duration");
                if (player_obj.has_member ("progress"))
                    ps.progress = player_obj.get_double_member ("progress");
                if (player_obj.has_member ("hasPrev"))
                    ps.has_prev = player_obj.get_boolean_member ("hasPrev");
                if (player_obj.has_member ("hasNext"))
                    ps.has_next = player_obj.get_boolean_member ("hasNext");

                if (player_obj.has_member ("extra")) {
                    var extra_obj = player_obj.get_object_member ("extra");
                    if (extra_obj.has_member ("coverURI"))
                        ps.cover_uri = extra_obj.get_string_member ("coverURI");
                }

                if (player_obj.has_member ("entityInfo")) {
                    var entity_obj = player_obj.get_object_member ("entityInfo");
                    if (entity_obj.has_member ("repeatMode"))
                        ps.repeat_mode = entity_obj.get_string_member ("repeatMode");
                    if (entity_obj.has_member ("shuffled"))
                        ps.shuffled = entity_obj.get_boolean_member ("shuffled");
                }
            }

            return ps;
        }

        public string get_cover_url (int size = 400) {
            if (cover_uri == "")
                return "";
            return "https://" + cover_uri.replace ("%%", "%dx%d".printf (size, size));
        }
    }
}
