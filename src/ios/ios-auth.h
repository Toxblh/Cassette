/* Yandex OAuth sign-in in a WKWebView presented over the GTK window.
 * Same contract as src/macos/macos-webkit-auth.h. */
#pragma once

#include <glib.h>

G_BEGIN_DECLS

typedef void (*CassetteTokenCallback) (const char *token, gpointer userdata);

void cassette_ios_auth_start (const char           *auth_url,
                              CassetteTokenCallback callback,
                              gpointer              userdata,
                              GDestroyNotify        userdata_free);

G_END_DECLS
