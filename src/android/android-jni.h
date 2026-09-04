/* Shared JNI plumbing for the Android shims.
 *
 * Bootstrapped from Java: CassetteApplication.onCreate() calls
 * Native.nativeInit(context) before the GTK runtime starts, which stores the
 * JavaVM, the application Context and the app class loader as GlobalRefs.
 * Everything else is resolved lazily through that class loader, because
 * FindClass on a native (attached) thread only sees the system loader.
 */
#pragma once

#include <jni.h>
#include <glib.h>

G_BEGIN_DECLS

/* JNIEnv for the calling thread; attaches it as a daemon thread if needed. */
JNIEnv *cassette_jni_env (void);

/* Application Context (GlobalRef). NULL before nativeInit. */
jobject cassette_jni_context (void);

/* Loads "space/rirusha/cassette/Foo" through the app class loader.
 * Returns a GlobalRef owned by the cache; never released. NULL on failure. */
jclass cassette_jni_class (JNIEnv *env, const char *name);

/* Logs and clears a pending Java exception. Returns TRUE if there was one. */
gboolean cassette_jni_check (JNIEnv *env, const char *what);

/* Runs fn(data) on the GLib main loop. */
void cassette_jni_idle (GSourceFunc fn, gpointer data);

G_END_DECLS
