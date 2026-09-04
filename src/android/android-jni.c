#include "android-jni.h"

#include <android/log.h>

#define LOG_TAG "Cassette"
#define LOGE(...) __android_log_print (ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static JavaVM *g_vm = NULL;
static jobject g_context = NULL;      /* GlobalRef, Application context */
static jobject g_classloader = NULL;  /* GlobalRef */
static jmethodID g_load_class = NULL;

JNIEXPORT jint JNICALL
JNI_OnLoad (JavaVM *vm, void *reserved)
{
  g_vm = vm;
  return JNI_VERSION_1_6;
}

JNIEnv *
cassette_jni_env (void)
{
  JNIEnv *env = NULL;

  if (!g_vm)
    return NULL;

  jint rc = (*g_vm)->GetEnv (g_vm, (void **) &env, JNI_VERSION_1_6);
  if (rc == JNI_OK)
    return env;

  if (rc == JNI_EDETACHED)
    {
      JavaVMAttachArgs args = { JNI_VERSION_1_6, "cassette-native", NULL };
      if ((*g_vm)->AttachCurrentThreadAsDaemon (g_vm, &env, &args) == JNI_OK)
        return env;
    }

  LOGE ("cassette_jni_env: unable to obtain JNIEnv (rc=%d)", rc);
  return NULL;
}

jobject
cassette_jni_context (void)
{
  return g_context;
}

gboolean
cassette_jni_check (JNIEnv *env, const char *what)
{
  if (!(*env)->ExceptionCheck (env))
    return FALSE;

  LOGE ("Java exception in %s:", what);
  (*env)->ExceptionDescribe (env);
  (*env)->ExceptionClear (env);
  return TRUE;
}

jclass
cassette_jni_class (JNIEnv *env, const char *name)
{
  if (!g_classloader || !g_load_class)
    {
      LOGE ("cassette_jni_class(%s): nativeInit has not run", name);
      return NULL;
    }

  /* ClassLoader.loadClass wants dots, JNI names use slashes. */
  gchar *dotted = g_strdelimit (g_strdup (name), "/", '.');
  jstring jname = (*env)->NewStringUTF (env, dotted);
  g_free (dotted);

  jobject local = (*env)->CallObjectMethod (env, g_classloader, g_load_class, jname);
  (*env)->DeleteLocalRef (env, jname);

  if (cassette_jni_check (env, "ClassLoader.loadClass") || !local)
    {
      LOGE ("cassette_jni_class: class %s not found", name);
      return NULL;
    }

  jclass global = (jclass) (*env)->NewGlobalRef (env, local);
  (*env)->DeleteLocalRef (env, local);
  return global;
}

void
cassette_jni_idle (GSourceFunc fn, gpointer data)
{
  g_idle_add (fn, data);
}

/* Called from CassetteApplication.onCreate() on the Java main thread. */
JNIEXPORT void JNICALL
Java_space_rirusha_cassette_Native_nativeInit (JNIEnv *env, jclass klass, jobject context)
{
  if (g_context)
    return; /* Application.onCreate runs once per process, but be safe. */

  if (!g_vm)
    (*env)->GetJavaVM (env, &g_vm);

  g_context = (*env)->NewGlobalRef (env, context);

  jclass class_class = (*env)->FindClass (env, "java/lang/Class");
  jmethodID get_loader = (*env)->GetMethodID (env, class_class, "getClassLoader", "()Ljava/lang/ClassLoader;");
  jobject loader = (*env)->CallObjectMethod (env, klass, get_loader);
  g_classloader = (*env)->NewGlobalRef (env, loader);
  (*env)->DeleteLocalRef (env, loader);
  (*env)->DeleteLocalRef (env, class_class);

  jclass loader_class = (*env)->FindClass (env, "java/lang/ClassLoader");
  g_load_class = (*env)->GetMethodID (env, loader_class, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;");
  (*env)->DeleteLocalRef (env, loader_class);

  cassette_jni_check (env, "nativeInit");
}
