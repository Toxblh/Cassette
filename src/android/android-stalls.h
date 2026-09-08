#pragma once
#include <glib.h>

/* Arms the main-loop stall sampler; call on the GTK thread (see android-stalls.c). */
void cassette_android_stalls_start (void);
