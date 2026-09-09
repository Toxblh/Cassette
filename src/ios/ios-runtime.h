/* Process environment for Cassette inside an iOS app bundle. */
#pragma once

#include <glib.h>

G_BEGIN_DECLS

/* XDG directories, fonts, CA bundle, schemas: everything GLib and friends
 * expect from a Linux install, mapped onto the bundle and the app container.
 * Call before anything touches GIO, GSettings or fontconfig. */
void cassette_ios_setup_env (void);

/* Absolute path of the app bundle (read-only resources). */
const char *cassette_ios_bundle_path (void);

G_END_DECLS
