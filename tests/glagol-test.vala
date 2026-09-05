// ind-check=skip-file

using Cassette.Client.Glagol;


uint8[] u16_bytes (uint16 v) {
    return { (uint8) (v >> 8), (uint8) (v & 0xFF) };
}

uint8[] pointer_bytes (uint16 offset) {
    return { (uint8) (0xC0 | (offset >> 8)), (uint8) (offset & 0xFF) };
}

uint8[] encode_name (string name) {
    var b = new ByteArray ();
    foreach (string label in name.split (".")) {
        if (label == "") {
            continue;
        }
        uint8[] len = { (uint8) label.length };
        b.append (len);
        b.append (label.data);
    }
    uint8[] root = { 0 };
    b.append (root);
    return b.data;
}

uint8[] encode_label_with_pointer (string label, uint16 pointer_offset) {
    var b = new ByteArray ();
    uint8[] len = { (uint8) label.length };
    b.append (len);
    b.append (label.data);
    b.append (pointer_bytes (pointer_offset));
    return b.data;
}

uint8[] encode_txt (string[] entries) {
    var b = new ByteArray ();
    foreach (string entry in entries) {
        uint8[] len = { (uint8) entry.length };
        b.append (len);
        b.append (entry.data);
    }
    return b.data;
}


public int main (string[] args) {
    Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.GNOMELOCALEDIR);
    Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
    Intl.textdomain (Config.GETTEXT_PACKAGE);

    Test.init (ref args);

    Test.add_func ("/glagol/discovery/build_query/format", () => {
        // "_yandexio" (9), "_tcp" (4), "local" (5), each length-prefixed, ASCII bytes
        uint8[] expected = {
            0,0, 0,0, 0,1, 0,0, 0,0, 0,0,
            9, 95,121,97,110,100,101,120,105,111,
            4, 95,116,99,112,
            5, 108,111,99,97,108,
            0,
            0,12,
            0x80,1 // PTR, IN with the unicast-response bit
        };

        uint8[] got = DeviceDiscovery.build_query ("_yandexio._tcp.local");

        if (got.length != expected.length) {
            Test.fail_printf ("expected %d bytes, got %d", expected.length, got.length);
            return;
        }

        for (int i = 0; i < expected.length; i++) {
            if (got[i] != expected[i]) {
                Test.fail_printf ("byte %d: expected %u, got %u", i, expected[i], got[i]);
                return;
            }
        }
    });

    Test.add_func ("/glagol/discovery/read_uint16/basic", () => {
        uint8[] data = { 0x01, 0x02 };
        uint16 res = DeviceDiscovery.read_uint16 (data, 0);
        if (res != 0x0102) {
            Test.fail_printf ("got %u", res);
        }
    });

    Test.add_func ("/glagol/discovery/read_name/plain", () => {
        uint8[] data = encode_name ("foo.local");

        string name;
        size_t next = DeviceDiscovery.read_name (data, 0, out name);

        if (name != "foo.local") {
            Test.fail_printf ("got name '%s'", name);
        }
        if (next != data.length) {
            Test.fail_printf ("expected next offset %d, got %zu", data.length, next);
        }
    });

    Test.add_func ("/glagol/discovery/read_name/compression-pointer", () => {
        uint8[] base_name = encode_name ("foo.local");

        var buf = new ByteArray ();
        buf.append (base_name);
        buf.append (pointer_bytes (0));

        uint8[] data = buf.data;

        string name;
        size_t next = DeviceDiscovery.read_name (data, base_name.length, out name);

        if (name != "foo.local") {
            Test.fail_printf ("got name '%s'", name);
        }
        if (next != data.length) {
            Test.fail_printf ("expected next offset %d, got %zu", data.length, next);
        }
    });

    Test.add_func ("/glagol/discovery/strip_service_suffix/found", () => {
        string res = DeviceDiscovery.strip_service_suffix (
            "YandexIOReceiver-abc123._yandexio._tcp.local"
        );
        if (res != "YandexIOReceiver-abc123") {
            Test.fail_printf ("got '%s'", res);
        }
    });

    Test.add_func ("/glagol/discovery/strip_service_suffix/no-match", () => {
        string res = DeviceDiscovery.strip_service_suffix ("something.else");
        if (res != "something.else") {
            Test.fail_printf ("got '%s'", res);
        }
    });

    Test.add_func ("/glagol/discovery/extract_device_id/with-prefix", () => {
        string res = DeviceDiscovery.extract_device_id ("YandexIOReceiver-abc123");
        if (res != "abc123") {
            Test.fail_printf ("got '%s'", res);
        }
    });

    Test.add_func ("/glagol/discovery/extract_device_id/without-prefix", () => {
        string res = DeviceDiscovery.extract_device_id ("SomeOtherName");
        if (res != "SomeOtherName") {
            Test.fail_printf ("got '%s'", res);
        }
    });

    Test.add_func ("/glagol/discovery/parse_response/ptr-srv-txt-a", () => {
        var buf = new ByteArray ();

        // Header: QDCOUNT=0, ANCOUNT=4
        buf.append (new uint8[] { 0,0, 0,0, 0,0, 0,4, 0,0, 0,0 });

        uint16 service_name_offset = (uint16) buf.len;
        buf.append (encode_name ("_yandexio._tcp.local"));

        // Record 1: PTR _yandexio._tcp.local -> YandexIOReceiver-abc123._yandexio._tcp.local
        buf.append (u16_bytes (12)); // TYPE PTR
        buf.append (u16_bytes (1));  // CLASS IN
        buf.append (new uint8[] { 0,0,0,120 }); // TTL

        uint8[] rdata1 = encode_label_with_pointer ("YandexIOReceiver-abc123", service_name_offset);
        uint16 instance_name_offset = (uint16) (buf.len + 2);
        buf.append (u16_bytes ((uint16) rdata1.length));
        buf.append (rdata1);

        // Record 2: SRV YandexIOReceiver-abc123._yandexio._tcp.local -> device-host.local:1961
        buf.append (pointer_bytes (instance_name_offset)); // NAME
        buf.append (u16_bytes (33)); // TYPE SRV
        buf.append (u16_bytes (1));  // CLASS IN
        buf.append (new uint8[] { 0,0,0,120 }); // TTL

        var rdata2 = new ByteArray ();
        rdata2.append (u16_bytes (0)); // priority
        rdata2.append (u16_bytes (0)); // weight
        rdata2.append (u16_bytes (1961)); // port
        rdata2.append (encode_name ("device-host.local"));

        buf.append (u16_bytes ((uint16) rdata2.len));
        buf.append (rdata2.data);

        // Record 3: TXT for the same instance name
        buf.append (pointer_bytes (instance_name_offset)); // NAME
        buf.append (u16_bytes (16)); // TYPE TXT
        buf.append (u16_bytes (1));  // CLASS IN
        buf.append (new uint8[] { 0,0,0,120 }); // TTL

        uint8[] rdata3 = encode_txt ({ "deviceId=abc123", "platform=yandexmini_2" });
        buf.append (u16_bytes ((uint16) rdata3.length));
        buf.append (rdata3);

        // Record 4: A device-host.local -> 192.168.10.99
        buf.append (encode_name ("device-host.local")); // NAME
        buf.append (u16_bytes (1)); // TYPE A
        buf.append (u16_bytes (1)); // CLASS IN
        buf.append (new uint8[] { 0,0,0,120 }); // TTL
        buf.append (u16_bytes (4)); // RDLENGTH
        buf.append (new uint8[] { 192,168,10,99 });

        var ptr_names = new Gee.HashSet<string> ();
        var srv_by_name = new Gee.HashMap<string, DeviceDiscovery.SrvRecord?> ();
        var txt_by_name = new Gee.HashMap<string, Gee.HashMap<string, string>> ();
        var addr_by_host = new Gee.HashMap<string, string> ();

        DeviceDiscovery.parse_response (buf.data, ptr_names, srv_by_name, txt_by_name, addr_by_host);

        string instance_name = "YandexIOReceiver-abc123._yandexio._tcp.local";

        if (!ptr_names.contains (instance_name)) {
            Test.fail_printf ("PTR name not found, got %d entries", ptr_names.size);
            return;
        }

        if (!srv_by_name.has_key (instance_name)) {
            Test.fail_printf ("SRV record not found for instance name");
            return;
        }

        var srv = srv_by_name[instance_name];
        if (srv.port != 1961) {
            Test.fail_printf ("expected port 1961, got %u", srv.port);
        }
        if (srv.target != "device-host.local") {
            Test.fail_printf ("expected target 'device-host.local', got '%s'", srv.target);
        }

        if (!txt_by_name.has_key (instance_name)) {
            Test.fail_printf ("TXT record not found for instance name");
            return;
        }

        var txt = txt_by_name[instance_name];
        if (txt["deviceId"] != "abc123") {
            Test.fail_printf ("expected deviceId 'abc123', got '%s'", txt["deviceId"]);
        }
        if (txt["platform"] != "yandexmini_2") {
            Test.fail_printf ("expected platform 'yandexmini_2', got '%s'", txt["platform"]);
        }

        if (!addr_by_host.has_key ("device-host.local")) {
            Test.fail_printf ("A record not found for device-host.local");
            return;
        }
        if (addr_by_host["device-host.local"] != "192.168.10.99") {
            Test.fail_printf ("expected IP '192.168.10.99', got '%s'", addr_by_host["device-host.local"]);
        }
    });

    Test.add_func ("/glagol/token/parse_token_response/valid", () => {
        try {
            string token = DeviceTokenProvider.parse_token_response ("{\"token\": \"abc123\"}");
            if (token != "abc123") {
                Test.fail_printf ("got '%s'", token);
            }
        } catch (Error e) {
            Test.fail_printf ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/glagol/token/parse_token_response/missing-field", () => {
        try {
            DeviceTokenProvider.parse_token_response ("{\"status\": \"ok\"}");
            Test.fail_printf ("expected PARSE_ERROR, got success");
        } catch (TokenError e) {
            if (!(e is TokenError.PARSE_ERROR)) {
                Test.fail_printf ("unexpected error variant: %s", e.message);
            }
        } catch (Error e) {
            Test.fail_printf ("unexpected error type: %s", e.message);
        }
    });

    Test.add_func ("/glagol/token/parse_token_response/invalid-json", () => {
        try {
            DeviceTokenProvider.parse_token_response ("not json");
            Test.fail_printf ("expected PARSE_ERROR, got success");
        } catch (TokenError e) {
            if (!(e is TokenError.PARSE_ERROR)) {
                Test.fail_printf ("unexpected error variant: %s", e.message);
            }
        } catch (Error e) {
            Test.fail_printf ("unexpected error type: %s", e.message);
        }
    });

    Test.add_func ("/glagol/token/parse_token_response/not-object", () => {
        try {
            DeviceTokenProvider.parse_token_response ("[1, 2, 3]");
            Test.fail_printf ("expected PARSE_ERROR, got success");
        } catch (TokenError e) {
            if (!(e is TokenError.PARSE_ERROR)) {
                Test.fail_printf ("unexpected error variant: %s", e.message);
            }
        } catch (Error e) {
            Test.fail_printf ("unexpected error type: %s", e.message);
        }
    });

    return Test.run ();
}
