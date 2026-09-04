[CCode (cname = "CassetteTokenCallback", instance_pos = 1.5, has_target = true)]
public delegate void AndroidTokenCallback (string? token);

[CCode (cname = "cassette_android_auth_start", cheader_filename = "android-auth.h")]
public extern void cassette_android_auth_start (string auth_url, owned AndroidTokenCallback callback);
