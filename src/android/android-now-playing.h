/* MediaSession behind the same contract as src/macos/macos-now-playing.h.
 * Java side: SessionBridge.java (+ PlaybackService.java for the notification).
 *
 * Command callbacks arrive on the GLib main loop.
 */
#pragma once

#include <glib.h>

G_BEGIN_DECLS

typedef void (*CassetteNowPlayingCmd) (void);
typedef void (*CassetteNowPlayingSeekCmd) (double position_sec);
typedef void (*CassetteNowPlayingVolumeCmd) (int percent);

void cassette_android_now_playing_init (CassetteNowPlayingCmd     on_play,
                                        CassetteNowPlayingCmd     on_pause,
                                        CassetteNowPlayingCmd     on_play_pause,
                                        CassetteNowPlayingCmd     on_next,
                                        CassetteNowPlayingCmd     on_prev,
                                        CassetteNowPlayingSeekCmd on_seek,
                                        CassetteNowPlayingCmd     on_like,
                                        CassetteNowPlayingVolumeCmd on_volume);

/* While playback is on a Yandex station the hardware volume keys and the
 * system volume slider drive the station instead of the phone: the session
 * switches to remote playback with a 0..100 volume; on_volume reports what
 * the user asked for. remote=FALSE returns to local playback. */
void cassette_android_now_playing_set_remote_volume (gboolean remote, int percent);

/* Like state of the current track, shown as a custom action (heart) in the
 * system media controls; on_like is called when the user taps it. */
void cassette_android_now_playing_set_liked (gboolean liked);

void cassette_android_now_playing_update (const char *title,
                                          const char *artist,
                                          const char *album,
                                          double      duration_sec,
                                          double      elapsed_sec,
                                          gboolean    is_playing,
                                          const char *artwork_url);

void cassette_android_now_playing_update_state (double elapsed_sec, gboolean is_playing);

void cassette_android_now_playing_clear (void);

G_END_DECLS
