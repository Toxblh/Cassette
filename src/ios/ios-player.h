/* One AVPlayer behind the same C contract as src/android/android-player.h.
 * Callbacks arrive on the GLib main loop. */
#pragma once

#include <glib.h>

G_BEGIN_DECLS

typedef enum {
  CASSETTE_IOS_PLAYER_EVENT_EOS = 0,
  CASSETTE_IOS_PLAYER_EVENT_FOCUS_LOST = 1,
  CASSETTE_IOS_PLAYER_EVENT_FOCUS_GAINED = 2,
} CassetteIosPlayerEventType;

typedef void (*CassetteIosPlayerEvent) (int event);
typedef void (*CassetteIosPlayerError) (const char *message);

void    cassette_ios_player_init     (CassetteIosPlayerEvent on_event,
                                      CassetteIosPlayerError on_error);
void    cassette_ios_player_set_uri  (const char *uri);
void    cassette_ios_player_play     (void);
void    cassette_ios_player_pause    (void);
void    cassette_ios_player_stop     (void);
void    cassette_ios_player_seek     (gint64 ms);
gint64  cassette_ios_player_position (void);
void    cassette_ios_player_volume   (double volume, gboolean mute);

G_END_DECLS
