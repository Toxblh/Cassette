[CCode (cname = "CassetteNowPlayingCmd", has_target = false)]
public delegate void AndroidNowPlayingCmd ();

[CCode (cname = "CassetteNowPlayingSeekCmd", has_target = false)]
public delegate void AndroidNowPlayingSeekCmd (double position_sec);

[CCode (cname = "CassetteNowPlayingVolumeCmd", has_target = false)]
public delegate void AndroidNowPlayingVolumeCmd (int percent);

[CCode (cname = "cassette_android_now_playing_init", cheader_filename = "android-now-playing.h")]
public extern void cassette_android_now_playing_init (
    AndroidNowPlayingCmd     on_play,
    AndroidNowPlayingCmd     on_pause,
    AndroidNowPlayingCmd     on_play_pause,
    AndroidNowPlayingCmd     on_next,
    AndroidNowPlayingCmd     on_prev,
    AndroidNowPlayingSeekCmd on_seek,
    AndroidNowPlayingCmd     on_like,
    AndroidNowPlayingVolumeCmd on_volume
);

[CCode (cname = "cassette_android_now_playing_set_remote_volume", cheader_filename = "android-now-playing.h")]
public extern void cassette_android_now_playing_set_remote_volume (bool remote, int percent);

[CCode (cname = "cassette_android_now_playing_set_liked", cheader_filename = "android-now-playing.h")]
public extern void cassette_android_now_playing_set_liked (bool liked);

[CCode (cname = "cassette_android_now_playing_update", cheader_filename = "android-now-playing.h")]
public extern void cassette_android_now_playing_update (
    string  title,
    string  artist,
    string  album,
    double  duration_sec,
    double  elapsed_sec,
    bool    is_playing,
    string? artwork_url
);

[CCode (cname = "cassette_android_now_playing_update_state", cheader_filename = "android-now-playing.h")]
public extern void cassette_android_now_playing_update_state (double elapsed_sec, bool is_playing);

[CCode (cname = "cassette_android_now_playing_clear", cheader_filename = "android-now-playing.h")]
public extern void cassette_android_now_playing_clear ();
