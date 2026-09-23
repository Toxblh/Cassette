/* Debug aid: who blocks the GTK thread? (iOS port of android-stalls.c)
 *
 * A 5 ms heartbeat on the GTK main loop and a watchdog thread. When the
 * heartbeat is older than 100 ms the watchdog sends SIGUSR2 to the GTK
 * thread; the handler captures a backtrace of that thread and prints the
 * frames to stderr (tag CassetteStall). Symbolise on the host with
 * llvm-symbolizer against the unstripped binaries if needed.
 * Enabled by CASSETTE_DEBUG_STALLS=1 (debug.env); costs nothing otherwise.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "ios-stalls.h"

#include <execinfo.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <glib.h>

static pthread_t gtk_thread;
static volatile int64_t heartbeat_us = 0;
static volatile int sampling = 0;

static void
on_sample (int sig)
{
  void *frames[64];
  int n = backtrace (frames, 64);
  char **symbols = backtrace_symbols (frames, n);
  fprintf (stderr, "CassetteStall: GTK thread busy; %d frames:\n", n);
  for (int i = 0; i < n; i++)
    fprintf (stderr, "CassetteStall:   #%02d %s\n", i, symbols[i] ? symbols[i] : "?");
  free (symbols);
  sampling = 0;
}

static gboolean
heartbeat (gpointer data)
{
  heartbeat_us = g_get_monotonic_time ();
  return G_SOURCE_CONTINUE;
}

static void *
watchdog (void *data)
{
  int64_t last_reported = 0;
  for (;;)
    {
      usleep (20000);
      int64_t age = g_get_monotonic_time () - heartbeat_us;
      if (age > 100000 && !sampling && heartbeat_us != last_reported)
        {
          sampling = 1;
          last_reported = heartbeat_us;
          pthread_kill (gtk_thread, SIGUSR2);
        }
    }
  return NULL;
}

void
cassette_ios_stalls_start (void)
{
  gtk_thread = pthread_self ();
  heartbeat_us = g_get_monotonic_time ();

  struct sigaction sa;
  memset (&sa, 0, sizeof sa);
  sa.sa_handler = on_sample;
  sigaction (SIGUSR2, &sa, NULL);

  g_timeout_add (5, heartbeat, NULL);

  pthread_t t;
  pthread_create (&t, NULL, watchdog, NULL);
  pthread_detach (t);
  fprintf (stderr, "CassetteStall: stall sampler armed\n");
}
