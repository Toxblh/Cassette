#include "android-now-playing.h"
#include "android-jni.h"

#define BRIDGE "space/rirusha/cassette/SessionBridge"

/* Must match SessionBridge.CMD_* */
enum { CMD_PLAY = 0, CMD_PAUSE = 1, CMD_PLAY_PAUSE = 2, CMD_NEXT = 3, CMD_PREV = 4, CMD_STOP = 5, CMD_LIKE = 6 };

static CassetteNowPlayingCmd     g_on_play, g_on_pause, g_on_play_pause, g_on_next, g_on_prev, g_on_like;
static CassetteNowPlayingSeekCmd g_on_seek;
static CassetteNowPlayingVolumeCmd g_on_volume;

static jclass    g_class = NULL;
static jmethodID g_init, g_update, g_update_state, g_clear, g_set_liked, g_set_remote_volume;

static gboolean
ensure (JNIEnv *env)
{
  if (g_class)
    return TRUE;

  g_class = cassette_jni_class (env, BRIDGE);
  if (!g_class)
    return FALSE;

  g_init         = (*env)->GetStaticMethodID (env, g_class, "init",        "()V");
  g_update       = (*env)->GetStaticMethodID (env, g_class, "update",      "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;DDZLjava/lang/String;)V");
  g_update_state = (*env)->GetStaticMethodID (env, g_class, "updateState", "(DZ)V");
  g_clear        = (*env)->GetStaticMethodID (env, g_class, "clear",       "()V");
  g_set_liked    = (*env)->GetStaticMethodID (env, g_class, "setLiked",    "(Z)V");
  g_set_remote_volume = (*env)->GetStaticMethodID (env, g_class, "setRemoteVolume", "(ZI)V");

  if (cassette_jni_check (env, "SessionBridge method lookup"))
    {
      g_class = NULL;
      return FALSE;
    }
  return TRUE;
}

static jstring
jstr (JNIEnv *env, const char *s)
{
  return s ? (*env)->NewStringUTF (env, s) : NULL;
}

static void
jdel (JNIEnv *env, jstring s)
{
  if (s) (*env)->DeleteLocalRef (env, s);
}

void
cassette_android_now_playing_init (CassetteNowPlayingCmd     on_play,
                                   CassetteNowPlayingCmd     on_pause,
                                   CassetteNowPlayingCmd     on_play_pause,
                                   CassetteNowPlayingCmd     on_next,
                                   CassetteNowPlayingCmd     on_prev,
                                   CassetteNowPlayingSeekCmd on_seek,
                                   CassetteNowPlayingCmd     on_like,
                                   CassetteNowPlayingVolumeCmd on_volume)
{
  g_on_volume     = on_volume;
  g_on_like       = on_like;
  g_on_play       = on_play;
  g_on_pause      = on_pause;
  g_on_play_pause = on_play_pause;
  g_on_next       = on_next;
  g_on_prev       = on_prev;
  g_on_seek       = on_seek;

  JNIEnv *env = cassette_jni_env ();
  if (!env || !ensure (env))
    return;
  (*env)->CallStaticVoidMethod (env, g_class, g_init);
  cassette_jni_check (env, "SessionBridge.init");
}

void
cassette_android_now_playing_update (const char *title,
                                     const char *artist,
                                     const char *album,
                                     double      duration_sec,
                                     double      elapsed_sec,
                                     gboolean    is_playing,
                                     const char *artwork_url)
{
  JNIEnv *env = cassette_jni_env ();
  if (!env || !ensure (env))
    return;

  jstring jtitle = jstr (env, title ? title : "");
  jstring jartist = jstr (env, artist ? artist : "");
  jstring jalbum = jstr (env, album ? album : "");
  jstring jart = jstr (env, artwork_url);

  (*env)->CallStaticVoidMethod (env, g_class, g_update,
                                jtitle, jartist, jalbum,
                                (jdouble) duration_sec, (jdouble) elapsed_sec,
                                (jboolean) is_playing, jart);
  cassette_jni_check (env, "SessionBridge.update");

  jdel (env, jtitle); jdel (env, jartist); jdel (env, jalbum); jdel (env, jart);
}

void
cassette_android_now_playing_update_state (double elapsed_sec, gboolean is_playing)
{
  JNIEnv *env = cassette_jni_env ();
  if (!env || !ensure (env))
    return;
  (*env)->CallStaticVoidMethod (env, g_class, g_update_state, (jdouble) elapsed_sec, (jboolean) is_playing);
  cassette_jni_check (env, "SessionBridge.updateState");
}

void
cassette_android_now_playing_set_liked (gboolean liked)
{
  JNIEnv *env = cassette_jni_env ();
  if (!env || !ensure (env))
    return;
  (*env)->CallStaticVoidMethod (env, g_class, g_set_liked, (jboolean) liked);
  cassette_jni_check (env, "SessionBridge.setLiked");
}

void
cassette_android_now_playing_set_remote_volume (gboolean remote, int percent)
{
  JNIEnv *env = cassette_jni_env ();
  if (!env || !ensure (env))
    return;
  (*env)->CallStaticVoidMethod (env, g_class, g_set_remote_volume, (jboolean) remote, (jint) percent);
  cassette_jni_check (env, "SessionBridge.setRemoteVolume");
}

void
cassette_android_now_playing_clear (void)
{
  JNIEnv *env = cassette_jni_env ();
  if (!env || !ensure (env))
    return;
  (*env)->CallStaticVoidMethod (env, g_class, g_clear);
  cassette_jni_check (env, "SessionBridge.clear");
}

/* ── callbacks from MediaSession.Callback (Java main thread) → GLib ─────── */

static gboolean
idle_cmd (gpointer data)
{
  CassetteNowPlayingCmd fn = NULL;
  switch (GPOINTER_TO_INT (data))
    {
    case CMD_PLAY:       fn = g_on_play; break;
    case CMD_PAUSE:      fn = g_on_pause; break;
    case CMD_PLAY_PAUSE: fn = g_on_play_pause; break;
    case CMD_NEXT:       fn = g_on_next; break;
    case CMD_PREV:       fn = g_on_prev; break;
    case CMD_STOP:       fn = g_on_pause; break;
    case CMD_LIKE:       fn = g_on_like; break;
    }
  if (fn) fn ();
  return G_SOURCE_REMOVE;
}

typedef struct { double pos; } SeekData;

static gboolean
idle_seek (gpointer data)
{
  SeekData *d = data;
  if (g_on_seek) g_on_seek (d->pos);
  g_free (d);
  return G_SOURCE_REMOVE;
}

JNIEXPORT void JNICALL
Java_space_rirusha_cassette_SessionBridge_nativeCommand (JNIEnv *env, jclass klass, jint cmd)
{
  cassette_jni_idle (idle_cmd, GINT_TO_POINTER ((int) cmd));
}

static gboolean
idle_volume (gpointer data)
{
  if (g_on_volume)
    g_on_volume (GPOINTER_TO_INT (data));
  return G_SOURCE_REMOVE;
}

JNIEXPORT void JNICALL
Java_space_rirusha_cassette_SessionBridge_nativeVolume (JNIEnv *env, jclass klass, jint percent)
{
  cassette_jni_idle (idle_volume, GINT_TO_POINTER ((int) percent));
}

JNIEXPORT void JNICALL
Java_space_rirusha_cassette_SessionBridge_nativeSeek (JNIEnv *env, jclass klass, jdouble position_sec)
{
  SeekData *d = g_new (SeekData, 1);
  d->pos = position_sec;
  cassette_jni_idle (idle_seek, d);
}
