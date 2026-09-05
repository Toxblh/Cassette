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

    /*
     * Yandex Station devices advertise themselves via mDNS/DNS-SD as
     * "<instance>._yandexio._tcp.local" (not SSDP/DIAL), with the device id
     * and platform exposed in the TXT record and the IP/port in the SRV+A
     * records.
     */
    public class DeviceDiscovery : Object {

        public signal void device_found (GlagolDevice device);
        public signal void scan_complete ();

        private const string MDNS_ADDR = "224.0.0.251";
        private const uint16 MDNS_PORT = 5353;
        private const string SERVICE_NAME = "_yandexio._tcp.local";
        private const string INSTANCE_PREFIX = "YandexIOReceiver-";
        private const uint SCAN_DURATION_SECONDS = 3;

        internal struct SrvRecord {
            public uint16 port;
            public string target;
        }

        /**
         * One mDNS query for _yandexio._tcp, answers collected for
         * SCAN_DURATION_SECONDS. Runs on the caller's main loop (no nested
         * loop), so it is safe from the UI. The query asks for unicast
         * replies (QU bit): they then reach us on any port, which matters
         * when 5353 is taken by a resolver daemon and on Android, where
         * receiving multicast needs a wifi multicast lock.
         *
         * @param unicast_hosts addresses to query directly as well: stations
         * seen before, for networks that filter multicast (and emulators).
         */
        public async void scan_async (string[] unicast_hosts = {}) throws Error {
            var socket = new Socket (SocketFamily.IPV4, SocketType.DATAGRAM, SocketProtocol.UDP);

            try {
                socket.bind (new InetSocketAddress (new InetAddress.any (SocketFamily.IPV4), MDNS_PORT), true);
            } catch (Error e) {
                socket.bind (new InetSocketAddress (new InetAddress.any (SocketFamily.IPV4), 0), true);
            }
            try {
                socket.join_multicast_group (new InetAddress.from_string (MDNS_ADDR), false, null);
            } catch (Error e) {
                // Unicast replies still arrive; only other hosts' multicast answers are lost.
            }
            socket.blocking = false;

            var query = build_query (SERVICE_NAME);
            var dest = new InetSocketAddress (new InetAddress.from_string (MDNS_ADDR), MDNS_PORT);
            Error? multicast_error = null;
            try {
                socket.send_to (dest, query);
            } catch (Error e) {
                // "No route to host" while the network is changing (VPN,
                // container bridges): the known stations are still asked
                // directly below.
                multicast_error = e;
            }
            int sent = multicast_error == null ? 1 : 0;
            foreach (var host in unicast_hosts) {
                try {
                    socket.send_to (new InetSocketAddress (new InetAddress.from_string (host), MDNS_PORT), query);
                    sent++;
                } catch (Error e) {
                    Logger.debug ("mDNS unicast to %s: %s".printf (host, e.message));
                }
            }
            if (sent == 0) {
                throw multicast_error;
            }
            if (multicast_error != null) {
                Logger.debug ("mDNS multicast query failed, unicast only: %s".printf (multicast_error.message));
            }

            var ptr_names = new Gee.HashSet<string> ();
            var srv_by_name = new Gee.HashMap<string, SrvRecord?> ();
            var txt_by_name = new Gee.HashMap<string, Gee.HashMap<string, string>> ();
            var addr_by_host = new Gee.HashMap<string, string> ();

            var src = socket.create_source (IOCondition.IN, null);
            src.set_callback ((s, condition) => {
                if ((condition & IOCondition.IN) == 0) {
                    return GLib.Source.CONTINUE;
                }

                uint8[] buf = new uint8[65536];
                SocketAddress sender_addr;
                ssize_t n;
                try {
                    n = socket.receive_from (out sender_addr, buf);
                } catch (Error e) {
                    return GLib.Source.CONTINUE;
                }

                if (n <= 0) {
                    return GLib.Source.CONTINUE;
                }

                parse_response (buf[0:n], ptr_names, srv_by_name, txt_by_name, addr_by_host);
                return GLib.Source.CONTINUE;
            });
            src.attach (MainContext.default ());

            GLib.Timeout.add_seconds (SCAN_DURATION_SECONDS, () => {
                scan_async.callback ();
                return GLib.Source.REMOVE;
            });
            yield;

            src.destroy ();
            try {
                socket.close ();
            } catch (Error e) {
                // nothing to do
            }

            var seen_ids = new Gee.HashSet<string> ();

            foreach (var instance_name in ptr_names) {
                if (!srv_by_name.has_key (instance_name)) {
                    continue;
                }

                var srv = srv_by_name[instance_name];
                if (!addr_by_host.has_key (srv.target)) {
                    continue;
                }

                string ip = addr_by_host[srv.target];

                string device_id = "";
                string platform = "";

                if (txt_by_name.has_key (instance_name)) {
                    var txt = txt_by_name[instance_name];
                    if (txt.has_key ("deviceId")) {
                        device_id = txt["deviceId"];
                    }
                    if (txt.has_key ("platform")) {
                        platform = txt["platform"];
                    }
                }

                string display_name = strip_service_suffix (instance_name);

                if (device_id == "") {
                    device_id = extract_device_id (display_name);
                }

                if (device_id == "" || seen_ids.contains (device_id)) {
                    continue;
                }
                seen_ids.add (device_id);

                device_found (new GlagolDevice (ip, (int) srv.port, display_name, device_id, platform, ""));
            }

            scan_complete ();
        }

        internal static string strip_service_suffix (string instance_name) {
            string suffix = "." + SERVICE_NAME;
            if (instance_name.has_suffix (suffix)) {
                return instance_name[0 : instance_name.length - suffix.length];
            }
            return instance_name;
        }

        internal static string extract_device_id (string display_name) {
            if (display_name.has_prefix (INSTANCE_PREFIX)) {
                return display_name[INSTANCE_PREFIX.length : display_name.length];
            }
            return display_name;
        }

        internal static uint8[] build_query (string service) {
            var buf = new ByteArray ();

            uint8[] header = { 0,0, 0,0, 0,1, 0,0, 0,0, 0,0 };
            buf.append (header);

            foreach (string label in service.split (".")) {
                if (label == "") {
                    continue;
                }
                uint8[] length_byte = { (uint8) label.length };
                buf.append (length_byte);
                buf.append (label.data);
            }

            uint8[] root = { 0 };
            buf.append (root);

            uint8[] qtype_class = { 0,12, 0x80,1 }; // PTR, IN, unicast-response (QU)
            buf.append (qtype_class);

            return buf.data;
        }

        internal static uint16 read_uint16 (uint8[] data, size_t offset) {
            return (uint16) ((data[offset] << 8) | data[offset + 1]);
        }

        /*
         * Reads a (possibly compressed) DNS name starting at `offset` and
         * returns the offset of the byte right after the name *as encoded
         * at `offset`* (i.e. after a compression pointer, not after the
         * jumped-to data) so callers can keep walking the record list.
         */
        internal static size_t read_name (uint8[] data, size_t offset, out string name) {
            var sb = new StringBuilder ();
            size_t pos = offset;
            size_t? return_pos = null;
            int jumps = 0;

            while (pos < data.length) {
                uint8 len = data[pos];

                if (len == 0) {
                    pos += 1;
                    if (return_pos == null) {
                        return_pos = pos;
                    }
                    break;
                }

                if ((len & 0xC0) == 0xC0) {
                    if (pos + 1 >= data.length) {
                        break;
                    }
                    uint16 pointer = (uint16) (((len & 0x3F) << 8) | data[pos + 1]);
                    if (return_pos == null) {
                        return_pos = pos + 2;
                    }
                    pos = pointer;
                    jumps++;
                    if (jumps > 20) {
                        break;
                    }
                    continue;
                }

                pos += 1;
                if (pos + len > data.length) {
                    break;
                }
                if (sb.len > 0) {
                    sb.append_c ('.');
                }
                for (size_t j = 0; j < len; j++) {
                    sb.append_c ((char) data[pos + j]);
                }
                pos += len;
            }

            name = sb.str;
            return return_pos ?? pos;
        }

        internal static void parse_response (
            uint8[] data,
            Gee.HashSet<string> ptr_names,
            Gee.HashMap<string, SrvRecord?> srv_by_name,
            Gee.HashMap<string, Gee.HashMap<string, string>> txt_by_name,
            Gee.HashMap<string, string> addr_by_host
        ) {
            if (data.length < 12) {
                return;
            }

            uint16 qdcount = read_uint16 (data, 4);
            uint16 ancount = read_uint16 (data, 6);
            uint16 nscount = read_uint16 (data, 8);
            uint16 arcount = read_uint16 (data, 10);

            size_t pos = 12;

            for (int i = 0; i < qdcount; i++) {
                string name;
                pos = read_name (data, pos, out name);
                pos += 4; // qtype + qclass
            }

            int total = ancount + nscount + arcount;
            for (int i = 0; i < total; i++) {
                if (pos + 10 > data.length) {
                    return;
                }

                string name;
                pos = read_name (data, pos, out name);

                uint16 rtype = read_uint16 (data, pos);
                pos += 2;
                pos += 2; // class
                pos += 4; // ttl
                uint16 rdlength = read_uint16 (data, pos);
                pos += 2;

                size_t rdata_start = pos;
                if (rdata_start + rdlength > data.length) {
                    return;
                }

                switch (rtype) {
                    case 12: // PTR
                        if (name.down () == SERVICE_NAME.down ()) {
                            string target;
                            read_name (data, rdata_start, out target);
                            ptr_names.add (target);
                        }
                        break;

                    case 33: // SRV
                        if (rdlength >= 6) {
                            uint16 port = read_uint16 (data, rdata_start + 4);
                            string target;
                            read_name (data, rdata_start + 6, out target);
                            srv_by_name[name] = SrvRecord () { port = port, target = target };
                        }
                        break;

                    case 16: // TXT
                        var txt = new Gee.HashMap<string, string> ();
                        size_t tpos = rdata_start;
                        size_t tend = rdata_start + rdlength;

                        while (tpos < tend) {
                            uint8 elen = data[tpos];
                            tpos += 1;
                            if (tpos + elen > tend) {
                                break;
                            }

                            var esb = new StringBuilder ();
                            for (size_t j = 0; j < elen; j++) {
                                esb.append_c ((char) data[tpos + j]);
                            }

                            string entry = esb.str;
                            int eq = entry.index_of ("=");
                            if (eq > 0) {
                                txt[entry[0 : eq]] = entry[eq + 1 : entry.length];
                            } else if (entry != "") {
                                txt[entry] = "";
                            }

                            tpos += elen;
                        }

                        txt_by_name[name] = txt;
                        break;

                    case 1: // A
                        if (rdlength == 4) {
                            string ip = "%u.%u.%u.%u".printf (
                                data[rdata_start], data[rdata_start + 1],
                                data[rdata_start + 2], data[rdata_start + 3]
                            );
                            addr_by_host[name] = ip;
                        }
                        break;

                    default:
                        break;
                }

                pos = rdata_start + rdlength;
            }
        }
    }
}
