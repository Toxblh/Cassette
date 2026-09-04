[CCode (cname = "CassettePlayerEvent", has_target = false)]
public delegate void AndroidPlayerEvent (int event);

[CCode (cname = "CassettePlayerError", has_target = false)]
public delegate void AndroidPlayerError (string message);

[CCode (cname = "CassettePlayerEventType", cprefix = "CASSETTE_PLAYER_EVENT_", cheader_filename = "android-player.h", has_type_id = false)]
public enum AndroidPlayerEventType {
    EOS,
    FOCUS_LOST,
    FOCUS_GAINED
}

[CCode (cname = "cassette_android_player_init", cheader_filename = "android-player.h")]
public extern void cassette_android_player_init (AndroidPlayerEvent on_event, AndroidPlayerError on_error);

[CCode (cname = "cassette_android_player_set_uri", cheader_filename = "android-player.h")]
public extern void cassette_android_player_set_uri (string? uri);

[CCode (cname = "cassette_android_player_play", cheader_filename = "android-player.h")]
public extern void cassette_android_player_play ();

[CCode (cname = "cassette_android_player_pause", cheader_filename = "android-player.h")]
public extern void cassette_android_player_pause ();

[CCode (cname = "cassette_android_player_stop", cheader_filename = "android-player.h")]
public extern void cassette_android_player_stop ();

[CCode (cname = "cassette_android_player_seek", cheader_filename = "android-player.h")]
public extern void cassette_android_player_seek (int64 ms);

[CCode (cname = "cassette_android_player_position", cheader_filename = "android-player.h")]
public extern int64 cassette_android_player_position ();

[CCode (cname = "cassette_android_player_volume", cheader_filename = "android-player.h")]
public extern void cassette_android_player_volume (double volume, bool mute);
