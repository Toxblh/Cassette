[CCode (cname = "CassetteAndroidAutoBrowse", has_target = false)]
public delegate void AndroidAutoBrowse (string parent_id, int64 request_id);

[CCode (cname = "CassetteAndroidAutoPlayMedia", has_target = false)]
public delegate void AndroidAutoPlayMedia (string media_id);

[CCode (cname = "CassetteAndroidAutoPlaySearch", has_target = false)]
public delegate void AndroidAutoPlaySearch (string query);

[CCode (cname = "cassette_android_auto_init", cheader_filename = "android-auto.h")]
public extern void cassette_android_auto_init (
    AndroidAutoBrowse     on_browse,
    AndroidAutoPlayMedia  on_play_media,
    AndroidAutoPlaySearch on_play_search
);

[CCode (cname = "cassette_android_auto_browse_result", cheader_filename = "android-auto.h")]
public extern void cassette_android_auto_browse_result (int64 request_id, string json);
