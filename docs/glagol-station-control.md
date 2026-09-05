# Yandex Station control (Glagol)

Playback can be sent to a Yandex station on the local network and taken back.
Transport: the Glagol WebSocket protocol (`wss://<host>:1961`, self-signed TLS),
device discovery over mDNS (`_yandexio._tcp`), device names and tokens from
`quasar.yandex.net` with the account's OAuth token.

## Layers

| Piece | File | Role |
|---|---|---|
| `GlagolClient` | `src/client/glagol/glagol-client.vala` | WebSocket session: commands, keepalive ping, `player_state_received` |
| `PlayerState`, `GlagolDevice` | `glagol-device.vala` | Parsed station state; mDNS record; platform → model name |
| `DeviceDiscovery` | `device-discovery.vala` | One mDNS query with the unicast-response bit, 3 s of answers, no nested main loop |
| `DeviceTokenProvider` | `device-token-provider.vala` | `glagol/device_list` (names, platforms) and `glagol/token` (per-device token) |
| `StationManager` | `station-manager.vala` | The one object the UI talks to: merged station list, connection, state, transfer both ways, commands |
| `OutputButton` | `src/widgets/station/output-button.vala` | "Play on…" button in the player bar, lit while remote |
| `StationPickerDialog` | `station-picker-dialog.vala` | This device + account stations (online first); bottom sheet on phones |
| `StationBar` | `station-bar.vala` | Replaces the player bar while remote: cover, title, transport, seek, volume, "play here" |

`Player` (`src/client/player/player.vala`) checks `Glagol.station_manager.active` in
`start_track_list`, `start_flow` and `change_track`: while a station is the
output, playback started anywhere in the app goes to the station (a whole
playlist/album/artist as a context, a single track otherwise).

## Flows

* **To the station**: picker → `StationManager.transfer_to`: device token (cached
  per id) → connect → wait for the first state (5 s) → `playMusic` the current
  track → `rewind` to the local position → local `Player.pause`. If nothing was
  playing locally it only connects.
* **Back**: "play here" or the picker's "This device" → `take_back`: pause the
  station, load its current track into `Player`, seek to the station's position.
* **State**: the station pushes state on changes and on each keepalive ping;
  `StationBar` advances the position locally between updates.
* **Start-up**: after sign-in `StationManager.reconnect_last` scans, and if the
  station from `last-station` is on the network *and playing*, connects to it
  (toast "Playing on …"), so the app opens on what is actually sounding. A
  paused or absent station is left alone.
* **Scan** queries multicast and, additionally, the addresses of stations seen
  before (`station-hosts`, "id=host" pairs) as unicast — for wifi that filters
  multicast and for the Android emulator behind NAT.
* **Android media session** mirrors the station while one is active: its
  track/position/like state, play/pause/next/prev/seek forwarded to it, and the
  hardware volume keys set the station's volume (`MediaSession.setPlaybackToRemote`
  with a `VolumeProvider`, 0..100, ±5 per key press). Back to the phone's stream
  when disconnected (`src/android/now-playing.vala`, `SessionBridge.setRemoteVolume`).

## Testing

* Unit: `build/tests/glagol-test` (query/response parsing, token parsing).
* End-to-end (real device, needs the app's sign-in): `CASSETTE_GLAGOL_E2E_HOST=<ip> build/tests/glagol-e2e-test -p /glagol/e2e/manager`
  — list, connect, playlist from the app, transport, seek, volume, reconnect on
  start (playing vs paused), take back. Helpers: `-p /glagol/e2e/discovery`
  (scan only, no account), `-p /glagol/e2e/leave` leaves the station playing
  (`CASSETTE_GLAGOL_E2E_ACTION=pause|status`) for testing other clients.
  Test station: the Lite (192.168.10.35).
* Android emulator: seed `last-station` and `station-hosts` in the app's GSettings
  keyfile (`files/etc/glib-2.0/settings/keyfile` under the app's external dir),
  leave the station playing from the desktop, start the app: the station bar must
  show its track and `dumpsys media_session` must report `volumeType=REMOTE`;
  `input keyevent KEYCODE_VOLUME_UP` / `KEYCODE_MEDIA_PAUSE` must change the
  station (check with the `leave` helper's `status` action).
* UI without clicking: `CASSETTE_DEBUG_STATION=<device id>` connects after start,
  `CASSETTE_DEBUG_PICKER=1` opens the picker, `CASSETTE_DEBUG_SHOT=<png>` renders
  the window from inside GTK 9 s later.
* CLI: `tools/test-glagol.sh <host> <device token>` prints the raw state stream.

## Protocol notes

* Token: `GET https://quasar.yandex.net/glagol/token?device_id=<id>&platform=<platform>`
  with `Authorization: OAuth <token>`; 404 "Unknown device" means the station
  is not in this account (it can still be on the network).
* Commands: `play`, `stop` (pause), `next`, `prev`, `setVolume` (0..1), `rewind`
  (seconds), `playMusic` (`type` track/album/artist/playlist/radio + `id`),
  `sendText`, `repeat`, `shuffle`.
* Cover: `https://` + `coverURI` with `%%` replaced by a size that exists
  (`200x200`, `400x400`).
