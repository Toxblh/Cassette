/* Android Auto media browse bridge. Java side:
 * CassetteAutoService.java (+ the MediaSession in SessionBridge.java).
 *
 * Browse requests arrive on the GLib main loop; replies go back to Java,
 * which posts them to the main looper and calls Result.sendResult.
 */
#pragma once

#include <glib.h>

G_BEGIN_DECLS

typedef void (*CassetteAndroidAutoBrowse)    (const char *parent_id, long request_id);
typedef void (*CassetteAndroidAutoPlayMedia) (const char *media_id);
typedef void (*CassetteAndroidAutoPlaySearch)(const char *query);

void cassette_android_auto_init (CassetteAndroidAutoBrowse     on_browse,
                                 CassetteAndroidAutoPlayMedia  on_play_media,
                                 CassetteAndroidAutoPlaySearch on_play_search);

/* Send a JSON array of items back to CassetteAutoService.deliverBrowse. */
void cassette_android_auto_browse_result (long request_id, const char *json);

G_END_DECLS
