[CCode (cname = "CassetteIosPlayerEvent", has_target = false)]
public delegate void IosPlayerEvent (int event);

[CCode (cname = "CassetteIosPlayerError", has_target = false)]
public delegate void IosPlayerError (string message);

[CCode (cname = "CassetteIosPlayerEventType", cprefix = "CASSETTE_IOS_PLAYER_EVENT_", cheader_filename = "ios-player.h", has_type_id = false)]
public enum IosPlayerEventType {
    EOS,
    FOCUS_LOST,
    FOCUS_GAINED
}

[CCode (cname = "cassette_ios_player_init", cheader_filename = "ios-player.h")]
public extern void cassette_ios_player_init (IosPlayerEvent on_event, IosPlayerError on_error);

[CCode (cname = "cassette_ios_player_set_uri", cheader_filename = "ios-player.h")]
public extern void cassette_ios_player_set_uri (string? uri);

[CCode (cname = "cassette_ios_player_play", cheader_filename = "ios-player.h")]
public extern void cassette_ios_player_play ();

[CCode (cname = "cassette_ios_player_pause", cheader_filename = "ios-player.h")]
public extern void cassette_ios_player_pause ();

[CCode (cname = "cassette_ios_player_stop", cheader_filename = "ios-player.h")]
public extern void cassette_ios_player_stop ();

[CCode (cname = "cassette_ios_player_seek", cheader_filename = "ios-player.h")]
public extern void cassette_ios_player_seek (int64 ms);

[CCode (cname = "cassette_ios_player_position", cheader_filename = "ios-player.h")]
public extern int64 cassette_ios_player_position ();

[CCode (cname = "cassette_ios_player_volume", cheader_filename = "ios-player.h")]
public extern void cassette_ios_player_volume (double volume, bool mute);
