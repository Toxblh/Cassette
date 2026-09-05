// ind-check=skip-file

using Cassette.Client;
using Cassette.Client.Cachier;
using Cassette.Client.Glagol;

public static Storager storager;

async void run_e2e (string host, string x_token) throws Error {
    var discovery = new DeviceDiscovery ();
    GlagolDevice? found = null;

    discovery.device_found.connect ((device) => {
        if (device.host == host) {
            found = device;
        }
    });

    yield discovery.scan_async ();

    if (found == null) {
        throw new IOError.NOT_FOUND ("No Glagol device found at %s via mDNS".printf (host));
    }

    stdout.printf ("Found device: %s (%s) platform=%s id=%s port=%d\n",
        found.get_display_name (), found.host, found.platform, found.device_id, found.port);

    var provider = new DeviceTokenProvider ();
    string token = yield provider.get_token (x_token, found.device_id, found.platform);

    var client = new GlagolClient ();
    PlayerState? state = null;
    bool state_received = false;
    PlayerState? latest_state = null;

    client.player_state_received.connect ((s) => {
        latest_state = s;
        if (!state_received) {
            state = s;
            state_received = true;
            Idle.add (run_e2e.callback);
        }
    });

    yield client.connect_async (host, found.port, token);

    yield;

    if (state == null) {
        throw new IOError.FAILED ("Did not receive player state from station");
    }

    stdout.printf ("Now playing: \"%s\" by %s\n", state.title, state.artist);
    stdout.printf ("Playing: %s, progress: %.1f / %.1f sec, volume: %.2f\n",
        state.playing.to_string (), state.progress, state.duration, state.volume);

    // Test "transfer to station": ask the device to (re)play the track that
    // is already playing. If the protocol/command format is correct, the
    // station should restart the track (progress resets close to 0).
    stdout.printf ("Sending playMusic for track_id=%s...\n", state.track_id);
    latest_state = null;
    client.play_track (state.track_id);

    GLib.Timeout.add_seconds (3, () => {
        Idle.add (run_e2e.callback);
        return GLib.Source.REMOVE;
    });
    yield;

    if (latest_state != null) {
        stdout.printf ("After play_track: playing=%s, progress=%.1f / %.1f sec\n",
            latest_state.playing.to_string (), latest_state.progress, latest_state.duration);
    } else {
        stdout.printf ("After play_track: no state update received\n");
    }

    latest_state = null;
    client.pause ();
    stdout.printf ("Sent pause command.\n");

    GLib.Timeout.add_seconds (1, () => {
        Idle.add (run_e2e.callback);
        return GLib.Source.REMOVE;
    });
    yield;

    if (latest_state != null) {
        stdout.printf ("After pause: playing=%s\n", latest_state.playing.to_string ());
    }

    client.close_connection ();
}

async void run_stability (string host, string x_token, int seconds) throws Error {
    var discovery = new DeviceDiscovery ();
    GlagolDevice? found = null;

    discovery.device_found.connect ((device) => {
        if (device.host == host) {
            found = device;
        }
    });

    yield discovery.scan_async ();

    if (found == null) {
        throw new IOError.NOT_FOUND ("No Glagol device found at %s via mDNS".printf (host));
    }

    var provider = new DeviceTokenProvider ();
    string token = yield provider.get_token (x_token, found.device_id, found.platform);

    var client = new GlagolClient ();
    int64 start_time = GLib.get_monotonic_time ();

    client.player_state_received.connect ((s) => {
        stdout.printf ("[%5.1fs] state: playing=%s, progress=%.1f, title=\"%s\"\n",
            (GLib.get_monotonic_time () - start_time) / 1000000.0,
            s.playing.to_string (), s.progress, s.title);
    });
    client.disconnected.connect (() => {
        stdout.printf ("[%5.1fs] DISCONNECTED\n", (GLib.get_monotonic_time () - start_time) / 1000000.0);
    });
    client.error_occurred.connect ((msg) => {
        stdout.printf ("[%5.1fs] ERROR: %s\n", (GLib.get_monotonic_time () - start_time) / 1000000.0, msg);
    });

    yield client.connect_async (host, found.port, token);
    stdout.printf ("[%5.1fs] connected\n", (GLib.get_monotonic_time () - start_time) / 1000000.0);

    GLib.Timeout.add_seconds (seconds, () => {
        Idle.add (run_stability.callback);
        return GLib.Source.REMOVE;
    });
    yield;

    stdout.printf ("[%5.1fs] test finished\n", (GLib.get_monotonic_time () - start_time) / 1000000.0);
    client.close_connection ();
}

/*
 * The whole routing layer against a real station: refresh, connect, send a
 * playlist, transport commands, take the track back to the local player.
 * Needs the app's sign-in (oauth_token in cassette.db) and the station in
 * the account and on this network.
 */
async void run_manager (string host) throws Error {
    var manager = Cassette.Client.Glagol.station_manager;

    yield manager.refresh ();

    Station? target = null;
    for (uint i = 0; i < manager.stations.get_n_items (); i++) {
        var station = (Station) manager.stations.get_item (i);
        stdout.printf ("station: %s (%s) %s %s\n", station.display_name, station.model, station.id,
            station.online ? station.host : "offline");
        stdout.flush ();
        if (station.host == host) {
            target = station;
        }
    }
    if (target == null) {
        throw new IOError.NOT_FOUND ("Station %s is not in the account list or not on the network".printf (host));
    }

    int states = 0;
    manager.state_changed.connect ((state) => {
        states++;
        stdout.printf ("  state #%d: playing=%s \"%s\" %s %.1f/%.1f vol=%.2f\n", states,
            state.playing.to_string (), state.title, state.artist, state.progress, state.duration, state.volume);
        stdout.flush ();
    });

    yield manager.transfer_to (target);
    assert (manager.active == target);
    stdout.printf ("connected to %s, first state received\n", target.display_name);
    stdout.flush ();

    // A queue started from the app goes to the station (Player intercepts).
    string liked_oid;
    var liked = yield fetch_liked (out liked_oid);
    stdout.printf ("liked tracks: %d (%s)\n", liked.size, liked_oid);
    stdout.flush ();
    if (liked.size > 0) {
        player.start_track_list (liked, "playlist", liked_oid, 0, null);
        yield wait_seconds (4);
        assert (manager.state != null);
        stdout.printf ("after playlist: playing=%s \"%s\"\n", manager.state.playing.to_string (), manager.state.title);
        stdout.flush ();

        player.start_track_list (liked, "playlist", null, 1, null);
        yield wait_seconds (4);
        stdout.printf ("after track #2: playing=%s \"%s\"\n", manager.state.playing.to_string (), manager.state.title);
        stdout.flush ();
    }

    manager.pause ();
    yield wait_seconds (2);
    stdout.printf ("after pause: playing=%s\n", manager.state.playing.to_string ());
    manager.play ();
    yield wait_seconds (2);
    stdout.printf ("after play: playing=%s\n", manager.state.playing.to_string ());
    manager.seek (30);
    yield wait_seconds (2);
    stdout.printf ("after seek 30: progress=%.1f\n", manager.state.progress);
    double volume = manager.state.volume;
    manager.set_volume (0.2);
    yield wait_seconds (2);
    stdout.printf ("after volume 0.2: volume=%.2f\n", manager.state.volume);
    manager.set_volume (volume);
    manager.next ();
    yield wait_seconds (3);
    stdout.printf ("after next: \"%s\"\n", manager.state.title);
    stdout.flush ();

    yield manager.take_back ();
    yield wait_seconds (4);
    var local = player.mode.get_current_track_info ();
    stdout.printf ("taken back: active=%s local track=%s state=%s pos=%.1f\n",
        (manager.active == null).to_string (), local != null ? local.title : "none",
        player.state.to_string (), player.playback_pos_sec);
    stdout.flush ();
    assert (manager.active == null);
    assert (local != null);
    player.stop ();
}

async Gee.ArrayList<YaMAPI.Track> fetch_liked (out string oid) {
    Gee.ArrayList<YaMAPI.Track> result = new Gee.ArrayList<YaMAPI.Track> ();
    string playlist_oid = "";
    threader.add (() => {
        try {
            var playlist = yam_talker.get_playlist_info_old (null, "3");
            if (playlist != null) {
                playlist_oid = playlist.oid;
                foreach (var track in playlist.get_filtered_track_list (true, true)) {
                    result.add (track);
                    if (result.size >= 5) {
                        break;
                    }
                }
            }
        } catch (Error e) {
            stdout.printf ("liked: %s\n", e.message);
        }
        Idle.add (fetch_liked.callback);
    });
    yield;
    oid = playlist_oid;
    return result;
}

async void wait_seconds (uint seconds) {
    Timeout.add_seconds (seconds, () => {
        Idle.add (wait_seconds.callback);
        return Source.REMOVE;
    });
    yield;
}

public int main (string[] args) {
    Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.GNOMELOCALEDIR);
    Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
    Intl.textdomain (Config.GETTEXT_PACKAGE);

    Test.init (ref args);

    Test.add_func ("/glagol/e2e/connect_report_pause", () => {
        string? host = Environment.get_variable ("CASSETTE_GLAGOL_E2E_HOST");
        if (host == null || host == "") {
            Test.skip ("Set CASSETTE_GLAGOL_E2E_HOST=<station IP> to run this end-to-end test against a real device");
            return;
        }

        storager = new Storager ();
        string? x_token = storager.db.get_additional_data ("oauth_token");
        if (x_token == null || x_token == "") {
            Test.skip ("No stored oauth_token in cassette.db — sign in via the app first");
            return;
        }

        var loop = new MainLoop ();
        Error? failure = null;

        run_e2e.begin (host, x_token, (obj, res) => {
            try {
                run_e2e.end (res);
            } catch (Error e) {
                failure = e;
            }
            loop.quit ();
        });

        GLib.Timeout.add_seconds (30, () => {
            loop.quit ();
            if (failure == null) {
                failure = new IOError.TIMED_OUT ("E2E test timed out after 30 seconds");
            }
            return GLib.Source.REMOVE;
        });

        loop.run ();

        if (failure != null) {
            Test.fail_printf ("E2E test failed: %s", failure.message);
        }
    });

    Test.add_func ("/glagol/e2e/manager", () => {
        string? host = Environment.get_variable ("CASSETTE_GLAGOL_E2E_HOST");
        if (host == null || host == "") {
            Test.skip ("Set CASSETTE_GLAGOL_E2E_HOST=<station IP> to run this end-to-end test against a real device");
            return;
        }
        Cassette.Client.init (false);
        // The file-level `storager` above belongs to the raw-client tests.
        string? x_token = Cassette.Client.storager.db.get_additional_data ("oauth_token");
        if (x_token == null || x_token == "") {
            Test.skip ("No stored oauth_token in cassette.db — sign in via the app first");
            return;
        }
        try {
            yam_talker.init_if_not ();
        } catch (Error e) {
            Test.fail_printf ("Sign-in failed: %s", e.message);
            return;
        }
        var loop = new MainLoop ();
        Error? failure = null;
        run_manager.begin (host, (obj, res) => {
            try {
                run_manager.end (res);
            } catch (Error e) {
                failure = e;
            }
            loop.quit ();
        });
        GLib.Timeout.add_seconds (90, () => {
            loop.quit ();
            if (failure == null) {
                failure = new IOError.TIMED_OUT ("Manager test timed out after 90 seconds");
            }
            return GLib.Source.REMOVE;
        });
        loop.run ();
        if (failure != null) {
            Test.fail_printf ("Manager test failed: %s", failure.message);
        }
    });

    Test.add_func ("/glagol/e2e/stability", () => {
        string? host = Environment.get_variable ("CASSETTE_GLAGOL_E2E_HOST");
        string? long_run = Environment.get_variable ("CASSETTE_GLAGOL_E2E_LONG");
        if (host == null || host == "" || long_run == null || long_run == "") {
            Test.skip ("Set CASSETTE_GLAGOL_E2E_HOST and CASSETTE_GLAGOL_E2E_LONG=1 to run this long-running stability test");
            return;
        }

        storager = new Storager ();
        string? x_token = storager.db.get_additional_data ("oauth_token");
        if (x_token == null || x_token == "") {
            Test.skip ("No stored oauth_token in cassette.db — sign in via the app first");
            return;
        }

        var loop = new MainLoop ();
        Error? failure = null;

        run_stability.begin (host, x_token, 75, (obj, res) => {
            try {
                run_stability.end (res);
            } catch (Error e) {
                failure = e;
            }
            loop.quit ();
        });

        GLib.Timeout.add_seconds (90, () => {
            loop.quit ();
            if (failure == null) {
                failure = new IOError.TIMED_OUT ("Stability test timed out after 90 seconds");
            }
            return GLib.Source.REMOVE;
        });

        loop.run ();

        if (failure != null) {
            Test.fail_printf ("Stability test failed: %s", failure.message);
        }
    });

    return Test.run ();
}
