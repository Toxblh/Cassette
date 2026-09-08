/* Debug aid: who blocks the GTK thread?
 *
 * A 5 ms heartbeat on the GTK main loop and a watchdog thread. When the
 * heartbeat is older than 80 ms the watchdog sends SIGUSR2 to the GTK
 * thread; the handler captures a backtrace of that thread and prints the
 * raw frames (module + offset) to logcat. Symbolise on the host with
 * llvm-symbolizer against the unstripped libraries in .pixiewood/bin-aarch64.
 * Enabled by CASSETTE_DEBUG_STALLS=1 (debug.env); costs nothing otherwise.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "android-stalls.h"

#include <android/log.h>
#include <dlfcn.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

typedef int (*backtrace_fn) (void **buffer, int size);

static backtrace_fn   p_backtrace = NULL;
static pthread_t      gtk_thread;
static volatile int64_t heartbeat_us = 0;
static volatile int   sampling = 0;

static int64_t
now_us (void)
{
  struct timespec ts;
  clock_gettime (CLOCK_MONOTONIC, &ts);
  return (int64_t) ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

/* Signal handler on the GTK thread: async-signal-safety is best effort;
 * dladdr and __android_log_print are what we have. */
static void
on_sample (int sig)
{
  void *frames[48];
  int n = p_backtrace ? p_backtrace (frames, 48) : 0;
  __android_log_print (ANDROID_LOG_WARN, "CassetteStall", "GTK thread busy; %d frames:", n);
  for (int i = 0; i < n; i++)
    {
      Dl_info info;
      if (dladdr (frames[i], &info) && info.dli_fname)
        {
          const char *name = strrchr (info.dli_fname, '/');
          name = name ? name + 1 : info.dli_fname;
          __android_log_print (ANDROID_LOG_WARN, "CassetteStall", "  #%02d %s+0x%lx %s", i, name,
                               (unsigned long) ((uintptr_t) frames[i] - (uintptr_t) info.dli_fbase),
                               info.dli_sname ? info.dli_sname : "");
        }
      else
        __android_log_print (ANDROID_LOG_WARN, "CassetteStall", "  #%02d %p", i, frames[i]);
    }
  sampling = 0;
}

static gboolean
heartbeat (gpointer data)
{
  heartbeat_us = now_us ();
  return G_SOURCE_CONTINUE;
}

/* /proc/self/task/<tid>/schedstat: time on cpu, time runnable-but-waiting (ns). */
static void
schedstat (pid_t tid, unsigned long long *run, unsigned long long *wait)
{
  char path[64], buf[128];
  snprintf (path, sizeof path, "/proc/self/task/%d/schedstat", (int) tid);
  FILE *f = fopen (path, "r");
  *run = *wait = 0;
  if (f)
    {
      if (fgets (buf, sizeof buf, f))
        sscanf (buf, "%llu %llu", run, wait);
      fclose (f);
    }
}

static pid_t gtk_tid;

static void *
watchdog (void *data)
{
  int64_t last_reported = 0;
  int64_t last_loop = now_us ();
  int64_t stall_started = 0;
  unsigned long long gtk_run0 = 0, gtk_wait0 = 0, ui_run0 = 0, ui_wait0 = 0;
  pid_t ui_tid = getpid ();
  for (;;)
    {
      usleep (20000);
      int64_t now = now_us ();
      int64_t loop_gap = now - last_loop;
      last_loop = now;
      int64_t age = now - heartbeat_us;
      if (age > 40000 && stall_started == 0)
        {
          stall_started = now;
          schedstat (gtk_tid, &gtk_run0, &gtk_wait0);
          schedstat (ui_tid, &ui_run0, &ui_wait0);
          __android_log_print (ANDROID_LOG_WARN, "CassetteStall",
                               "stall begins: heartbeat age %lld ms, watchdog loop gap %lld ms",
                               (long long) (age / 1000), (long long) (loop_gap / 1000));
        }
      else if (age < 40000 && stall_started != 0)
        {
          unsigned long long gr, gw, ur, uw;
          schedstat (gtk_tid, &gr, &gw);
          schedstat (ui_tid, &ur, &uw);
          __android_log_print (ANDROID_LOG_WARN, "CassetteStall",
                               "stall over after %lld ms; gtk thread ran %llu ms, waited for cpu %llu ms; ui thread ran %llu ms, waited %llu ms; watchdog loop gap %lld ms",
                               (long long) ((now - stall_started) / 1000),
                               (gr - gtk_run0) / 1000000ULL, (gw - gtk_wait0) / 1000000ULL,
                               (ur - ui_run0) / 1000000ULL, (uw - ui_wait0) / 1000000ULL,
                               (long long) (loop_gap / 1000));
          stall_started = 0;
        }
      if (age > 80000 && !sampling && heartbeat_us != last_reported)
        {
          sampling = 1;
          last_reported = heartbeat_us;
          pthread_kill (gtk_thread, SIGUSR2);
        }
    }
  return NULL;
}

void
cassette_android_stalls_start (void)
{
  p_backtrace = (backtrace_fn) dlsym (RTLD_DEFAULT, "backtrace");
  if (p_backtrace == NULL)
    __android_log_print (ANDROID_LOG_WARN, "CassetteStall", "backtrace() unavailable; frames will be empty");

  gtk_thread = pthread_self ();
  gtk_tid = gettid ();
  heartbeat_us = now_us ();

  struct sigaction sa;
  memset (&sa, 0, sizeof sa);
  sa.sa_handler = on_sample;
  sigaction (SIGUSR2, &sa, NULL);

  g_timeout_add (5, heartbeat, NULL);

  pthread_t t;
  pthread_create (&t, NULL, watchdog, NULL);
  pthread_detach (t);
  __android_log_print (ANDROID_LOG_INFO, "CassetteStall", "stall sampler armed");
}
