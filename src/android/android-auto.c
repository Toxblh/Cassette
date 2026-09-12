#include "android-auto.h"
#include "android-jni.h"

#define SERVICE "space/rirusha/cassette/CassetteAutoService"

static CassetteAndroidAutoBrowse     g_on_browse;
static CassetteAndroidAutoPlayMedia  g_on_play_media;
static CassetteAndroidAutoPlaySearch g_on_play_search;

static jclass    g_class = NULL;
static jmethodID g_deliver;

static gboolean
ensure (JNIEnv *env)
{
  if (g_class)
    return TRUE;

  g_class = cassette_jni_class (env, SERVICE);
  if (!g_class)
    return FALSE;

  g_deliver = (*env)->GetStaticMethodID (env, g_class, "deliverBrowse", "(JLjava/lang/String;)V");
  if (cassette_jni_check (env, "CassetteAutoService method lookup"))
    {
      g_class = NULL;
      return FALSE;
    }
  return TRUE;
}

void
cassette_android_auto_init (CassetteAndroidAutoBrowse     on_browse,
                            CassetteAndroidAutoPlayMedia  on_play_media,
                            CassetteAndroidAutoPlaySearch on_play_search)
{
  g_on_browse = on_browse;
  g_on_play_media = on_play_media;
  g_on_play_search = on_play_search;
}

void
cassette_android_auto_browse_result (long request_id, const char *json)
{
  JNIEnv *env = cassette_jni_env ();
  if (!env || !ensure (env))
    {
      g_warning ("auto result: no JNI env / class (#%ld)", request_id);
      return;
    }

  jstring jjson = (*env)->NewStringUTF (env, json ? json : "[]");
  (*env)->CallStaticVoidMethod (env, g_class, g_deliver, (jlong) request_id, jjson);
  cassette_jni_check (env, "CassetteAutoService.deliverBrowse");
  if (jjson)
    (*env)->DeleteLocalRef (env, jjson);
}

/* ── callbacks from Java (main thread) → GLib ───────────────────────────── */

typedef struct { char *parent; long request; } BrowseData;

static gboolean
idle_browse (gpointer data)
{
  BrowseData *d = data;
  if (g_on_browse)
    g_on_browse (d->parent, d->request);
  g_free (d->parent);
  g_free (d);
  return G_SOURCE_REMOVE;
}

JNIEXPORT void JNICALL
Java_space_rirusha_cassette_CassetteAutoService_nativeBrowse (JNIEnv *env, jclass klass, jstring parent, jlong request)
{
  const char *p = parent ? (*env)->GetStringUTFChars (env, parent, NULL) : NULL;
  BrowseData *d = g_new0 (BrowseData, 1);
  d->parent = g_strdup (p ? p : "root");
  d->request = (long) request;
  if (p)
    (*env)->ReleaseStringUTFChars (env, parent, p);
  cassette_jni_idle (idle_browse, d);
}

/* which: 0 = play media id, 1 = play from search */
typedef struct { char *s; int which; } StrData;

static gboolean
idle_str (gpointer data)
{
  StrData *d = data;
  if (d->which == 0)
    {
      if (g_on_play_media) g_on_play_media (d->s);
    }
  else
    {
      if (g_on_play_search) g_on_play_search (d->s);
    }
  g_free (d->s);
  g_free (d);
  return G_SOURCE_REMOVE;
}

static void
post_string (JNIEnv *env, jstring s, int which)
{
  const char *p = s ? (*env)->GetStringUTFChars (env, s, NULL) : NULL;
  StrData *d = g_new0 (StrData, 1);
  d->s = g_strdup (p ? p : "");
  d->which = which;
  if (p)
    (*env)->ReleaseStringUTFChars (env, s, p);
  cassette_jni_idle (idle_str, d);
}

JNIEXPORT void JNICALL
Java_space_rirusha_cassette_CassetteAutoService_nativePlayMediaId (JNIEnv *env, jclass klass, jstring id)
{
  post_string (env, id, 0);
}

JNIEXPORT void JNICALL
Java_space_rirusha_cassette_CassetteAutoService_nativePlayFromSearch (JNIEnv *env, jclass klass, jstring query)
{
  post_string (env, query, 1);
}
