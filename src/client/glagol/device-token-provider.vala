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

    public errordomain TokenError {
        HTTP_ERROR,
        PARSE_ERROR,
    }

    /** A speaker registered in the user's Yandex account (quasar device_list). */
    public class AccountDevice : Object {
        public string id { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public string platform { get; set; default = ""; }
    }

    public class DeviceTokenProvider : Object {

        private Soup.Session session;

        construct {
            session = new Soup.Session ();
        }

        public async string get_token (string x_token, string device_id,
                                       string platform = "yandexmini") throws Error {
            var url = "https://quasar.yandex.net/glagol/token?device_id=%s&platform=%s".printf (
                GLib.Uri.escape_string (device_id, null, false),
                GLib.Uri.escape_string (platform, null, false)
            );

            var msg = new Soup.Message ("GET", url);
            msg.request_headers.append ("Authorization", "OAuth " + x_token);

            GLib.Bytes body = yield session.send_and_read_async (msg, Priority.DEFAULT, null);

            if (msg.status_code != 200) {
                throw new TokenError.HTTP_ERROR (
                    "Token request failed: HTTP %u".printf (msg.status_code)
                );
            }

            return parse_token_response ((string) body.get_data ());
        }

        /**
         * Speakers of the account with the names the user gave them in the
         * Yandex app. mDNS only reveals the platform, so this is where the
         * names come from; devices that are not speakers (phone apps) are
         * left out.
         */
        public async Gee.ArrayList<AccountDevice> list_devices (string x_token) throws Error {
            var msg = new Soup.Message ("GET", "https://quasar.yandex.net/glagol/device_list");
            msg.request_headers.append ("Authorization", "OAuth " + x_token);

            GLib.Bytes body = yield session.send_and_read_async (msg, Priority.DEFAULT, null);

            if (msg.status_code != 200) {
                throw new TokenError.HTTP_ERROR (
                    "Device list request failed: HTTP %u".printf (msg.status_code)
                );
            }

            return parse_device_list ((string) body.get_data ());
        }

        internal static Gee.ArrayList<AccountDevice> parse_device_list (string body) throws TokenError {
            var result = new Gee.ArrayList<AccountDevice> ();

            var parser = new Json.Parser ();
            try {
                parser.load_from_data (body);
            } catch (Error e) {
                throw new TokenError.PARSE_ERROR ("Failed to parse device list: " + e.message);
            }

            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT ||
                !root.get_object ().has_member ("devices")) {
                throw new TokenError.PARSE_ERROR ("Unexpected device list format");
            }

            root.get_object ().get_array_member ("devices").foreach_element ((array, index, node) => {
                if (node.get_node_type () != Json.NodeType.OBJECT) {
                    return;
                }
                var obj = node.get_object ();
                var device = new AccountDevice ();
                if (obj.has_member ("id")) {
                    device.id = obj.get_string_member ("id");
                }
                if (obj.has_member ("name")) {
                    device.name = obj.get_string_member ("name");
                }
                if (obj.has_member ("platform")) {
                    device.platform = obj.get_string_member ("platform");
                }
                // Phone/app entries share the account but are not speakers.
                if (device.id == "" || device.platform.has_suffix ("_app_android") || device.platform.has_suffix ("_app_ios")) {
                    return;
                }
                result.add (device);
            });

            return result;
        }

        internal static string parse_token_response (string body) throws TokenError {
            var parser = new Json.Parser ();
            try {
                parser.load_from_data (body);
            } catch (Error e) {
                throw new TokenError.PARSE_ERROR ("Failed to parse token response: " + e.message);
            }

            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                throw new TokenError.PARSE_ERROR ("Unexpected token response format");
            }

            var obj = root.get_object ();
            if (!obj.has_member ("token")) {
                throw new TokenError.PARSE_ERROR ("No 'token' field in response");
            }

            return obj.get_string_member ("token");
        }
    }
}
