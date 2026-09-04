#include "android-auth.h"
#include "android-jni.h"

#define ACTIVITY "space/rirusha/cassette/AuthActivity"

typedef struct {
  CassetteTokenCallback callback;
  gpointer              userdata;
  GDestroyNotify        userdata_free;
} Pending;

/* One sign-in at a time; the activity is single-instance on the Java side. */
static Pending *g_pending = NULL;

typedef struct { char *token; Pending *p; } IdleData;

static gboolean
idle_fire (gpointer data)
{
  IdleData *d = data;

  d->p->callback (d->token, d->p->userdata);

  if (d->p->userdata_free && d->p->userdata)
    d->p->userdata_free (d->p->userdata);

  g_free (d->p);
  g_free (d->token);
  g_free (d);
  return G_SOURCE_REMOVE;
}

void
cassette_android_auth_start (const char           *auth_url,
                             CassetteTokenCallback callback,
                             gpointer              userdata,
                             GDestroyNotify        userdata_free)
{
  if (g_pending)
    {
      /* Already showing a sign-in; report cancellation to the new caller. */
      if (userdata_free && userdata)
        userdata_free (userdata);
      return;
    }

  JNIEnv *env = cassette_jni_env ();
  jclass klass = env ? cassette_jni_class (env, ACTIVITY) : NULL;
  if (!klass)
    {
      callback (NULL, userdata);
      if (userdata_free && userdata)
        userdata_free (userdata);
      return;
    }

  g_pending = g_new0 (Pending, 1);
  g_pending->callback = callback;
  g_pending->userdata = userdata;
  g_pending->userdata_free = userdata_free;

  jmethodID start = (*env)->GetStaticMethodID (env, klass, "start", "(Ljava/lang/String;)V");
  jstring jurl = (*env)->NewStringUTF (env, auth_url);
  (*env)->CallStaticVoidMethod (env, klass, start, jurl);
  (*env)->DeleteLocalRef (env, jurl);

  if (cassette_jni_check (env, "AuthActivity.start"))
    {
      Pending *p = g_pending;
      g_pending = NULL;
      IdleData *d = g_new0 (IdleData, 1);
      d->p = p;
      cassette_jni_idle (idle_fire, d);
    }
}

/* Called from AuthActivity (Java main thread) with the token or null. */
JNIEXPORT void JNICALL
Java_space_rirusha_cassette_AuthActivity_nativeToken (JNIEnv *env, jclass klass, jstring token)
{
  Pending *p = g_pending;
  g_pending = NULL;
  if (!p)
    return;

  IdleData *d = g_new0 (IdleData, 1);
  d->p = p;
  if (token)
    {
      const char *utf = (*env)->GetStringUTFChars (env, token, NULL);
      d->token = g_strdup (utf);
      (*env)->ReleaseStringUTFChars (env, token, utf);
    }
  cassette_jni_idle (idle_fire, d);
}
