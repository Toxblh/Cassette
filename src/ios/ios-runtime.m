#import <Foundation/Foundation.h>

#include "ios-runtime.h"

static char *bundle_path = NULL;

const char *
cassette_ios_bundle_path (void)
{
  if (bundle_path == NULL)
    bundle_path = g_strdup ([[[NSBundle mainBundle] bundlePath] UTF8String]);
  return bundle_path;
}

static const char *
container_dir (NSSearchPathDirectory which)
{
  NSArray *paths = NSSearchPathForDirectoriesInDomains (which, NSUserDomainMask, YES);
  return [[paths firstObject] UTF8String];
}

void
cassette_ios_setup_env (void)
{
  const char *bundle = cassette_ios_bundle_path ();
  const char *support = container_dir (NSApplicationSupportDirectory);
  const char *caches = container_dir (NSCachesDirectory);

  /* Read-only data from the bundle: schemas, icons, locale, fonts. */
  g_setenv ("XDG_DATA_DIRS", g_build_filename (bundle, "share", NULL), TRUE);
  g_setenv ("XDG_CONFIG_DIRS", g_build_filename (bundle, "etc", NULL), TRUE);
  g_setenv ("GSETTINGS_SCHEMA_DIR", g_build_filename (bundle, "share", "glib-2.0", "schemas", NULL), TRUE);

  /* Writable state in the app container. */
  g_setenv ("XDG_DATA_HOME", g_build_filename (support, "cassette", "share", NULL), TRUE);
  g_setenv ("XDG_CONFIG_HOME", g_build_filename (support, "cassette", "config", NULL), TRUE);
  g_setenv ("XDG_CACHE_HOME", g_build_filename (caches, "cassette", NULL), TRUE);
  g_setenv ("HOME", support, FALSE);
  g_mkdir_with_parents (g_getenv ("XDG_DATA_HOME"), 0755);
  g_mkdir_with_parents (g_getenv ("XDG_CONFIG_HOME"), 0755);
  g_mkdir_with_parents (g_getenv ("XDG_CACHE_HOME"), 0755);

  /* Translations: gettext reads LANGUAGE/LANG, iOS keeps the preference
   * in NSLocale ("ru-RU", "en-US", ...). */
  NSString *preferred = [[NSLocale preferredLanguages] firstObject];
  if (preferred.length > 0 && g_getenv ("LANGUAGE") == NULL)
    {
      NSString *lang = [[preferred componentsSeparatedByString:@"-"] firstObject];
      char *posix = g_strdup_printf ("%s_%s.UTF-8", lang.UTF8String,
                                     [[[preferred stringByReplacingOccurrencesOfString:@"-" withString:@"_"]
                                        componentsSeparatedByString:@"_"] count] > 1
                                       ? [[[preferred componentsSeparatedByString:@"-"] objectAtIndex:1] UTF8String]
                                       : [[lang uppercaseString] UTF8String]);
      g_setenv ("LANGUAGE", lang.UTF8String, TRUE);
      g_setenv ("LC_MESSAGES", posix, TRUE);
      g_setenv ("LANG", posix, TRUE);
      g_free (posix);
    }

  /* OpenSSL has no CA store on iOS; the bundle carries Mozilla's. */
  char *cacert = g_build_filename (bundle, "cacert.pem", NULL);
  if (g_file_test (cacert, G_FILE_TEST_EXISTS))
    g_setenv ("SSL_CERT_FILE", cacert, FALSE);
  g_free (cacert);

  /* Static GIO: no module directory compiled in. */
  g_setenv ("GIO_MODULE_DIR", bundle, FALSE);

  /* Debug switches for the simulator: KEY=VALUE lines in the container. */
  char *debug_env = g_build_filename (support, "debug.env", NULL);
  if (g_file_test (debug_env, G_FILE_TEST_EXISTS))
    {
      char *contents = NULL;
      if (g_file_get_contents (debug_env, &contents, NULL, NULL))
        {
          char **lines = g_strsplit (contents, "\n", -1);
          for (int i = 0; lines[i] != NULL; i++)
            {
              char **kv = g_strsplit (g_strstrip (lines[i]), "=", 2);
              if (kv[0] != NULL && kv[1] != NULL && kv[0][0] != '\0')
                g_setenv (kv[0], kv[1], TRUE);
              g_strfreev (kv);
            }
          g_strfreev (lines);
          g_free (contents);
        }
    }
  g_free (debug_env);
}
