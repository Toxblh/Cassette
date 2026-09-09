/* AVPlayer behind the PlayerBackend contract.
 *
 * All AVFoundation work happens on the main queue; the GTK thread only
 * posts blocks there. Cassette removes its temporary track file right after
 * play(), so a local file is hard-linked into our own cache before the
 * asset opens it, and unlinked once the next URI arrives.
 */
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

#include <unistd.h>

#include <gio/gio.h>

#include "ios-player.h"

static CassetteIosPlayerEvent g_on_event = NULL;
static CassetteIosPlayerError g_on_error = NULL;

static AVPlayer *g_player = nil;
static id g_end_observer = nil;
static id g_interrupt_observer = nil;
static char *g_linked_file = NULL;
static double g_volume = 1.0;
static BOOL g_muted = NO;
static gint64 g_last_position_ms = 0;
static BOOL g_want_playing = NO;

/* ── callbacks → GLib main loop ─────────────────────────────────────── */

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

static void
post_event (int event)
{
  g_idle_add (idle_event, GINT_TO_POINTER (event));
}

static void
post_error (NSString *message)
{
  g_idle_add (idle_error, g_strdup (message.UTF8String));
}

/* ── main-queue helpers ─────────────────────────────────────────────── */

static void
on_main (void (^block)(void))
{
  if ([NSThread isMainThread])
    block ();
  else
    dispatch_async (dispatch_get_main_queue (), block);
}

static void
on_main_sync (void (^block)(void))
{
  if ([NSThread isMainThread])
    block ();
  else
    dispatch_sync (dispatch_get_main_queue (), block);
}

static void
drop_linked_file (void)
{
  if (g_linked_file != NULL)
    {
      unlink (g_linked_file);
      g_free (g_linked_file);
      g_linked_file = NULL;
    }
}

static void
ensure_player (void)
{
  if (g_player != nil)
    return;

  AVAudioSession *session = [AVAudioSession sharedInstance];
  NSError *error = nil;
  [session setCategory:AVAudioSessionCategoryPlayback error:&error];
  if (error != nil)
    NSLog (@"Cassette: audio session category: %@", error);
  [session setActive:YES error:&error];
  if (error != nil)
    NSLog (@"Cassette: audio session activate: %@", error);

  g_player = [[AVPlayer alloc] init];
  g_player.automaticallyWaitsToMinimizeStalling = NO;

  g_end_observer = [[NSNotificationCenter defaultCenter]
    addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                object:nil
                 queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note) {
              if (note.object == g_player.currentItem)
                post_event (CASSETTE_IOS_PLAYER_EVENT_EOS);
            }];

  g_interrupt_observer = [[NSNotificationCenter defaultCenter]
    addObserverForName:AVAudioSessionInterruptionNotification
                object:nil
                 queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note) {
              NSUInteger type = [note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
              if (type == AVAudioSessionInterruptionTypeBegan)
                post_event (CASSETTE_IOS_PLAYER_EVENT_FOCUS_LOST);
              else if (type == AVAudioSessionInterruptionTypeEnded)
                {
                  NSUInteger options = [note.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
                  if (options & AVAudioSessionInterruptionOptionShouldResume)
                    post_event (CASSETTE_IOS_PLAYER_EVENT_FOCUS_GAINED);
                }
            }];
}

/* ── public API ─────────────────────────────────────────────────────── */

void
cassette_ios_player_init (CassetteIosPlayerEvent on_event, CassetteIosPlayerError on_error)
{
  g_on_event = on_event;
  g_on_error = on_error;
  on_main (^{
    ensure_player ();
  });
}

void
cassette_ios_player_set_uri (const char *uri)
{
  NSString *nsuri = uri != NULL ? [NSString stringWithUTF8String:uri] : nil;
  char *link_path = NULL;

  /* Keep local files alive for as long as we play them. */
  if (uri != NULL && (g_str_has_prefix (uri, "file://") || uri[0] == '/'))
    {
      char *path = uri[0] == '/' ? g_strdup (uri) : g_filename_from_uri (uri, NULL, NULL);
      if (path != NULL)
        {
          char *dir = g_build_filename (g_get_user_cache_dir (), "playing", NULL);
          g_mkdir_with_parents (dir, 0755);
          link_path = g_build_filename (dir, g_path_get_basename (path), NULL);
          unlink (link_path);
          if (link (path, link_path) != 0)
            {
              /* different volume or already gone: fall back to a copy */
              GFile *src = g_file_new_for_path (path);
              GFile *dst = g_file_new_for_path (link_path);
              if (!g_file_copy (src, dst, G_FILE_COPY_OVERWRITE, NULL, NULL, NULL, NULL))
                g_clear_pointer (&link_path, g_free);
              g_object_unref (src);
              g_object_unref (dst);
            }
          g_free (dir);
          g_free (path);
        }
    }

  NSString *play_path = link_path != NULL ? [NSString stringWithUTF8String:link_path] : nil;
  on_main_sync (^{
    ensure_player ();
    g_last_position_ms = 0;
    drop_linked_file ();
    g_linked_file = link_path;

    AVPlayerItem *item = nil;
    if (play_path != nil)
      item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:play_path]];
    else if (nsuri != nil)
      item = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:nsuri]];
    [g_player replaceCurrentItemWithPlayerItem:item];
    if (g_want_playing && item != nil)
      [g_player play];
  });
}

void
cassette_ios_player_play (void)
{
  on_main (^{
    ensure_player ();
    g_want_playing = YES;
    g_player.volume = g_muted ? 0.0f : (float) g_volume;
    [g_player play];
  });
}

void
cassette_ios_player_pause (void)
{
  on_main (^{
    g_want_playing = NO;
    [g_player pause];
  });
}

void
cassette_ios_player_stop (void)
{
  on_main (^{
    g_want_playing = NO;
    [g_player pause];
    [g_player replaceCurrentItemWithPlayerItem:nil];
    g_last_position_ms = 0;
    drop_linked_file ();
  });
}

void
cassette_ios_player_seek (gint64 ms)
{
  on_main (^{
    if (g_player.currentItem == nil)
      return;
    CMTime target = CMTimeMakeWithSeconds (ms / 1000.0, NSEC_PER_SEC);
    [g_player seekToTime:target toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    g_last_position_ms = ms;
  });
}

gint64
cassette_ios_player_position (void)
{
  /* currentTime is safe to read from any thread */
  if (g_player == nil || g_player.currentItem == nil)
    return g_last_position_ms;
  CMTime t = g_player.currentTime;
  if (!CMTIME_IS_NUMERIC (t))
    return g_last_position_ms;
  g_last_position_ms = (gint64) (CMTimeGetSeconds (t) * 1000.0);
  return g_last_position_ms;
}

void
cassette_ios_player_volume (double volume, gboolean mute)
{
  g_volume = volume;
  g_muted = mute;
  on_main (^{
    if (g_player != nil)
      g_player.volume = g_muted ? 0.0f : (float) g_volume;
  });
}
