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

void cassette_android_now_playing_init (CassetteNowPlayingCmd     on_play,
                                        CassetteNowPlayingCmd     on_pause,
                                        CassetteNowPlayingCmd     on_play_pause,
                                        CassetteNowPlayingCmd     on_next,
                                        CassetteNowPlayingCmd     on_prev,
                                        CassetteNowPlayingSeekCmd on_seek);

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
