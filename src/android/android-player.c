#include "android-player.h"
#include "android-jni.h"

#include <string.h>

#define BRIDGE "space/rirusha/cassette/PlayerBridge"

static CassettePlayerEvent g_on_event = NULL;
static CassettePlayerError g_on_error = NULL;

static jclass    g_class = NULL;
static jmethodID g_set_uri, g_play, g_pause, g_stop, g_seek, g_position, g_volume;

static gboolean
ensure (JNIEnv *env)
{
  if (g_class)
    return TRUE;

  g_class = cassette_jni_class (env, BRIDGE);
  if (!g_class)
    return FALSE;

  g_set_uri  = (*env)->GetStaticMethodID (env, g_class, "setUri",   "(Ljava/lang/String;)V");
  g_play     = (*env)->GetStaticMethodID (env, g_class, "play",     "()V");
  g_pause    = (*env)->GetStaticMethodID (env, g_class, "pause",    "()V");
  g_stop     = (*env)->GetStaticMethodID (env, g_class, "stop",     "()V");
  g_seek     = (*env)->GetStaticMethodID (env, g_class, "seek",     "(J)V");
  g_position = (*env)->GetStaticMethodID (env, g_class, "position", "()J");
  g_volume   = (*env)->GetStaticMethodID (env, g_class, "setVolume", "(FZ)V");

  if (cassette_jni_check (env, "PlayerBridge method lookup"))
    {
      g_class = NULL;
      return FALSE;
    }
  return TRUE;
}

#define WITH_ENV(env) \
  JNIEnv *env = cassette_jni_env (); \
  if (!env || !ensure (env)) return

void
cassette_android_player_init (CassettePlayerEvent on_event, CassettePlayerError on_error)
{
  g_on_event = on_event;
  g_on_error = on_error;
}

void
cassette_android_player_set_uri (const char *uri)
{
  WITH_ENV (env);
  jstring s = uri ? (*env)->NewStringUTF (env, uri) : NULL;
  (*env)->CallStaticVoidMethod (env, g_class, g_set_uri, s);
  cassette_jni_check (env, "PlayerBridge.setUri");
  if (s) (*env)->DeleteLocalRef (env, s);
}

void
cassette_android_player_play (void)
{
  WITH_ENV (env);
  (*env)->CallStaticVoidMethod (env, g_class, g_play);
  cassette_jni_check (env, "PlayerBridge.play");
}

void
cassette_android_player_pause (void)
{
  WITH_ENV (env);
  (*env)->CallStaticVoidMethod (env, g_class, g_pause);
  cassette_jni_check (env, "PlayerBridge.pause");
}

void
cassette_android_player_stop (void)
{
  WITH_ENV (env);
  (*env)->CallStaticVoidMethod (env, g_class, g_stop);
  cassette_jni_check (env, "PlayerBridge.stop");
}

void
cassette_android_player_seek (gint64 ms)
{
  WITH_ENV (env);
  (*env)->CallStaticVoidMethod (env, g_class, g_seek, (jlong) ms);
  cassette_jni_check (env, "PlayerBridge.seek");
}

gint64
cassette_android_player_position (void)
{
  JNIEnv *env = cassette_jni_env ();
  if (!env || !ensure (env))
    return 0;
  jlong pos = (*env)->CallStaticLongMethod (env, g_class, g_position);
  if (cassette_jni_check (env, "PlayerBridge.position"))
    return 0;
  return (gint64) pos;
}

void
cassette_android_player_volume (double volume, gboolean mute)
{
  WITH_ENV (env);
  (*env)->CallStaticVoidMethod (env, g_class, g_volume, (jfloat) volume, (jboolean) mute);
  cassette_jni_check (env, "PlayerBridge.setVolume");
}

/* ── callbacks from Java (any thread) → GLib main loop ─────────────────── */

static gboolean
idle_event (gpointer data)
{
  if (g_on_event)
    g_on_event (GPOINTER_TO_INT (data));
  return G_SOURCE_REMOVE;
}

static gboolean
idle_error (gpointer data)
{
  char *message = data;
  if (g_on_error)
    g_on_error (message);
  g_free (message);
  return G_SOURCE_REMOVE;
}

JNIEXPORT void JNICALL
Java_space_rirusha_cassette_PlayerBridge_nativeEvent (JNIEnv *env, jclass klass, jint event)
{
  cassette_jni_idle (idle_event, GINT_TO_POINTER ((int) event));
}

JNIEXPORT void JNICALL
Java_space_rirusha_cassette_PlayerBridge_nativeError (JNIEnv *env, jclass klass, jstring message)
{
  const char *utf = message ? (*env)->GetStringUTFChars (env, message, NULL) : NULL;
  char *copy = g_strdup (utf ? utf : "unknown error");
  if (utf) (*env)->ReleaseStringUTFChars (env, message, utf);
  cassette_jni_idle (idle_error, copy);
}
