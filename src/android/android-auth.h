/* Yandex OAuth sign-in through a WebView activity (AuthActivity.java).
 * Same contract as src/macos/macos-webkit-auth.h: the callback receives the
 * access token, or NULL if the user closed the activity; it runs on the
 * GLib main loop, exactly once.
 */
#pragma once

#include <glib.h>

G_BEGIN_DECLS

typedef void (*CassetteTokenCallback) (const char *token, gpointer userdata);

void cassette_android_auth_start (const char           *auth_url,
                                  CassetteTokenCallback callback,
                                  gpointer              userdata,
                                  GDestroyNotify        userdata_free);

G_END_DECLS
