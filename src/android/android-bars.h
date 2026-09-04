/* Colours painted behind the Android status bar and navigation bar.
 * Goes through the patched GTK glue (build-aux/android/patches/
 * gtk-android-bars-colors.patch): ToplevelActivity.setBarsColors(int, int).
 * Colours are 0xAARRGGBB; the app calls this whenever the bottom-most
 * toolbar or the colour scheme changes.
 */
#pragma once

#include <glib.h>

G_BEGIN_DECLS

void cassette_android_set_bars_colors (guint32 top, guint32 bottom);

G_END_DECLS
