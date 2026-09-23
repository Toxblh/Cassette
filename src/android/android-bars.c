#include "android-bars.h"
#include "android-jni.h"

void
cassette_android_set_bars_colors (guint32 top, guint32 bottom)
{
  static jclass klass = NULL;
  static jmethodID mid = NULL;

  JNIEnv *env = cassette_jni_env ();
  if (!env)
    return;

  if (!klass)
    {
      klass = cassette_jni_class (env, "org/gtk/android/ToplevelActivity");
      if (!klass)
        return;
      mid = (*env)->GetStaticMethodID (env, klass, "setBarsColors", "(II)V");
      if (cassette_jni_check (env, "ToplevelActivity.setBarsColors lookup"))
        {
          klass = NULL;
          return;
        }
    }

  (*env)->CallStaticVoidMethod (env, klass, mid, (jint) top, (jint) bottom);
  cassette_jni_check (env, "ToplevelActivity.setBarsColors");
}

gboolean
cassette_android_is_automotive (void)
{
  static jclass klass = NULL;
  static jmethodID mid = NULL;

  JNIEnv *env = cassette_jni_env ();
  if (!env)
    return FALSE;

  if (!klass)
    {
      klass = cassette_jni_class (env, "space/rirusha/cassette/Native");
      if (!klass)
        return FALSE;
      mid = (*env)->GetStaticMethodID (env, klass, "isAutomotive", "()Z");
      if (cassette_jni_check (env, "Native.isAutomotive lookup"))
        {
          klass = NULL;
          return FALSE;
        }
    }

  jboolean result = (*env)->CallStaticBooleanMethod (env, klass, mid);
  if (cassette_jni_check (env, "Native.isAutomotive"))
    return FALSE;
  return result == JNI_TRUE;
}
