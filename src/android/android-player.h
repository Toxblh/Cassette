/* One MediaPlayer behind a C contract. Java side: PlayerBridge.java.
 *
 * Callbacks always arrive on the GLib main loop (g_idle_add inside the
 * shim), never on the Java thread that produced them.
 */
#pragma once

#include <glib.h>

G_BEGIN_DECLS

typedef enum {
  CASSETTE_PLAYER_EVENT_EOS = 0,
  CASSETTE_PLAYER_EVENT_FOCUS_LOST = 1,
  CASSETTE_PLAYER_EVENT_FOCUS_GAINED = 2,
} CassettePlayerEventType;

typedef void (*CassettePlayerEvent) (int event);
typedef void (*CassettePlayerError) (const char *message);

void    cassette_android_player_init     (CassettePlayerEvent on_event,
                                          CassettePlayerError on_error);
void    cassette_android_player_set_uri  (const char *uri);
void    cassette_android_player_play     (void);
void    cassette_android_player_pause    (void);
void    cassette_android_player_stop     (void);
void    cassette_android_player_seek     (gint64 ms);
gint64  cassette_android_player_position (void);
void    cassette_android_player_volume   (double volume, gboolean mute);

G_END_DECLS
