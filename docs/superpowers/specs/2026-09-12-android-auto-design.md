# Cassette in Android Auto — design

Date: 2026-09-12
Branch: `android-auto`
Status: proposed (awaiting review)

## Goal

Make the real Cassette library and player usable in Android Auto: browse
Liked, Playlists, Albums, Artists and Stations in the car, play tracks, and
support the car's voice search — all through the app's existing Player/queue
and Yandex client.

"Cassette in Android Auto" means Cassette's content rendered by Android
Auto's (restricted) media templates, not the GTK UI. Android Auto builds the
car UI itself from a `MediaBrowserService` tree plus the `MediaSession`; an
app cannot draw custom UI.

CarPlay is out of scope here (Apple's `carplay-audio` entitlement gate); it
was designed separately.

## Non-goals

- Custom car UI / CarPlay.
- Offline caching changes or a new library store.
- Changing the phone UI.

## Background: the existing Android media layer

- Playback: `AndroidPlayerBackend` (`src/client/player/android-backend.vala`)
  → `src/android/android-player.c` (JNI) → `PlayerBridge.java` (MediaPlayer,
  audio focus). `PlayerBackend` is the only contract the queue logic sees.
- Session/notification: `src/android/now-playing.vala` (`Cassette.Client.
  AndroidNowPlaying`, a namespace of statics) → `android-now-playing.c` (JNI)
  → `SessionBridge.java` (platform `android.media.session.MediaSession`) +
  `PlaybackService.java` (foreground service, notification). This already
  feeds the lock screen, headset buttons and the media notification.
- Queue: `Player.start_track_list (queue, ctx_type, ctx_id, index, desc)` and
  `Player.start_flow (station_id, queue)`; both reroute to a connected
  Glagol hardware station when one is active.
- Library: `YaMTalker` (`src/client/talkers/yam-talker.vala`) wraps the
  synchronous `YaMClient`; likes via `get_playlist_info_old (null, "3")`,
  playlists via `get_playlist_list`/`get_likes_playlist_list`, album/artist
  via `get_album_info`/`get_artist_info`, search via `search`, rotor stations
  via `get_all_stations`.
- Startup: `CassetteApplication.onCreate` calls `Native.init` and then
  `RuntimeApplication.onCreate`, which starts the GTK thread and Cassette's
  `main ()` — with no Activity. `src/android/android-jni.c` stores the VM,
  Context and app class loader and exposes `cassette_jni_idle` (Java → GLib)
  and `cassette_jni_class` (class loading from native threads).
- Build: pixiewood generates the Gradle project; `patch-android-project.py`
  injects our permissions, `CassetteApplication`, `PlaybackService`,
  `AuthActivity`, draws our icons, and copies `build-aux/android/java/`.
  `src/meson.build` builds `src/android/*.c` + `.vapi` + `*.vala`.

## Spike findings (proven on the AAOS emulator, 2026-09-12)

- The platform `android.media.browse.MediaBrowserService` +
  `android.media.session.MediaSession` are enough; **no AndroidX/Gradle
  dependency** is needed.
- For the car to list the app's media source it must be "opted in": the
  service needs `<meta-data android:name="androidx.car.app.launchable"
  android:value="true"/>` (the built-in local player has it). Without it,
  `MediaUtils` never lists the service and it never appears.
- The car also reads `com.google.android.gms.car.application` →
  `@xml/automotive_app_desc` (`<uses name="media"/>`) on `<application>`.
- A static tree (root → Liked → 3 playable items) browsed, played, and
  rendered Now Playing in the emulator's Media Center; `dumpsys media_session`
  showed `state=PLAYING` and the chosen metadata.

## Architecture

Three layers, mirroring the existing `now-playing.vala` /
`android-now-playing.c` / `SessionBridge.java` triad.

### Java

`build-aux/android/java/space/rirusha/cassette/CassetteAutoService.java`
extends `android.service.media.MediaBrowserService`:

- `onCreate`: ensure the shared session exists (`SessionBridge.ensureSession()`),
  `setSessionToken (SessionBridge.token ())`, keep it active; add
  `onPlayFromMediaId` / `onPlayFromSearch` to the session callback.
- `onGetRoot`: return `new BrowserRoot ("root", null)` (allow any client).
- `onLoadChildren (parentId, result)`: call
  `AutoBridge.nativeBrowse (parentId, requestId)`; the native side replies
  asynchronously via `AutoBridge.browseResult (requestId, json)` →
  `result.sendResult (items)`. Per-request generation guards stale replies;
  `result.detach ()` is called on a new request for the same parent.
- Item JSON fields: `id`, `title`, `subtitle`, `playable`, `icon` (cover URL).
  Build `MediaDescription` + `MediaBrowser.MediaItem` with
  `FLAG_PLAYABLE` or `FLAG_BROWSABLE`.

`SessionBridge` gains `ensureSession ()` (idempotent, main-thread) and the two
new callback methods; `init ()` becomes `ensureSession () + setToken`.

### Native bridge

`src/android/android-auto.c` / `.h` / `.vapi` — JNI, exactly the
`android-now-playing.c` pattern:

- inbound: `Java_..._CassetteAutoService_nativeBrowse (parentId, requestId)`,
  `..._nativePlayMediaId (mediaId)`, `..._nativePlayFromSearch (query)` — each
  hops to GLib with `cassette_jni_idle`.
- outbound: `cassette_android_auto_browse_result (requestId, const char *json)`.

### Vala

`src/android/auto-browser.vala` — `namespace Cassette.Client.AndroidAuto`:

- `init ()` registers the three callbacks; called from `Cassette.Client.init`
  under `#elif ANDROID`, next to `AndroidNowPlaying.init ()`.
- `browse (parentId, requestId)`: builds the JSON on the GLib main loop.
  Root is a static table (no network). Network-backed levels run the
  synchronous `yam_talker` call on a worker thread
  (`threader.add (() => { …; Idle.add (callback); }); yield;`), then reply.
- `play_media_id (mediaId)` / `play_from_search (query)`: run on the GLib
  loop and drive `player.start_track_list` / `player.start_flow`.

## Browse tree and media IDs

```
root
├─ liked                         → track:<collection>…  (playable)
├─ playlists                     → playlist:<uuid>      (browsable)
├─ albums                        → album:<id>           (browsable)
├─ artists                       → artist:<id>          (browsable)
└─ stations                      → station:<id>         (playable)

playlist:<uuid>  → track:playlist:<uuid>:<index>:<trackId>       (playable)
album:<id>       → track:album:<id>:<index>:<trackId>           (playable)
artist:<id>      → track:artist:<id>:<index>:<trackId>          (playable)
liked            → track:liked:3:<index>:<trackId>              (playable)
search:<query>   → track:search:<query>:<index>:<trackId>       (playable)
```

Playable IDs encode their context so `onPlayFromMediaId` can rebuild the queue
without a lookup: `play_media_id` splits the ID and calls
`player.start_track_list (list, ctx_type, ctx_id, index, description)` — the
same entry the UI uses (`TrackRow.form_queue` / `start_playing`). `station:<id>`
maps to `player.start_flow (id)`. The `liked` playlist uses kind `"3"`.

If a Glagol hardware station is active, playback already reroutes to it;
browse stays as-is and the car now-playing follows the station.

## Flows

**Browse.** Java main → `nativeBrowse` → `cassette_jni_idle` → GLib → worker
thread for the `yam_talker` call → `Idle.add` back to GLib → JSON →
`cassette_android_auto_browse_result` → JNI `CallStaticVoidMethod` →
Java main-looper post → `result.sendResult`. Never block the GTK thread.

**Playback.** Car calls `onPlayFromMediaId` (main thread) → `nativePlayMediaId`
→ GLib `play_media_id` → `player.start_track_list`. The existing now-playing
code keeps metadata/queue/artwork flowing into the one shared `MediaSession`,
so the car's Now Playing updates for free.

**Voice.** `onPlayFromSearch (query, extras)` → `nativePlayFromSearch` →
GLib → `yam_talker.search (query)` → play the best match (top tracks as a
`search:<query>` queue). Required for a published Android Auto media app.

**Cold start.** The service can start the process with no Activity;
`CassetteApplication.onCreate` loads the library and starts the GTK thread and
`main ()`. Open question: whether the client/DB and login are ready in a
service-only process, since `activate ()` normally builds and presents the
window. Verify by launching the service before any UI; if not, initialize the
client without a window (guarded by a "headless" flag).

## Build and manifest integration

- `src/meson.build` (android block): add `android/android-auto.c`,
  `android/android-auto.vapi`, `android/auto-browser.vala`.
- `patch-android-project.py`: add a second `<service>` (independent of the
  existing `if app.find("service") is None` guard):
  ```xml
  <service android:name="space.rirusha.cassette.CassetteAutoService"
           android:exported="true" android:foregroundServiceType="mediaPlayback">
    <intent-filter><action android:name="android.media.browse.MediaBrowserService"/></intent-filter>
    <meta-data android:name="androidx.car.app.launchable" android:value="true"/>
  </service>
  ```
  add the `com.google.android.gms.car.application` meta-data on `<application>`
  pointing at `@xml/automotive_app_desc`, and a `write_automotive_xml (res)`
  that writes it. Extend the post-write assertions accordingly.

## Phases

1. Plumbing: service + static tree + session token, on the AAOS emulator
   (already proven as a throwaway; port it into the app).
2. Real tree: Liked/Playlists/Albums/Artists/Stations + play-by-ID via the
   JNI/Vala bridge.
3. Voice search, and error/offline/not-logged-in states.

## Testing / verification

- Build the APK with the pixiewood toolchain (needs Docker + the Matras
  checkout; not available on the current Mac).
- AAOS emulator (`car` AVD) or the DHU for phone Android Auto:
  `adb forward tcp:5277 tcp:5277` + `desktop-head-unit`.
- Check: app appears as a media source; each folder lists real data; a track
  plays through `AndroidPlayerBackend` (audio, notification, lock-screen);
  next/prev/seek; voice search; phone UI unaffected.

## Risks and open questions

- **Build/test**: the real APK can only be built with pixiewood
  (Docker + `matras-android`) — not on this Mac.
- **Headless client**: does the DB/login come up when only the service starts
  the process? (Phase 1 check.)
- **Blocking network**: all `yam_talker` calls are synchronous; the worker +
  `Idle` discipline is mandatory.
- **Not-logged-in / offline**: root may show folders but children fail; return
  empty lists and a clear "sign in on the phone" state.
- **Android Auto review**: a third-party Yandex Music client may be rejected
  for Play distribution; sideload/DHU testing is unaffected.
- **Deep browse trees**: Android Auto has depth/list limits; keep the top
  level to the five folders and cap long lists if needed.
- **Covers**: item icons via cover URLs; if the car cannot load remote icons,
  a first version ships without artwork.
