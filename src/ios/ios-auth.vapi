[CCode (cname = "CassetteTokenCallback", instance_pos = 1.5, has_target = true)]
public delegate void IosTokenCallback (string? token);

[CCode (cname = "cassette_ios_auth_start", cheader_filename = "ios-auth.h")]
public extern void cassette_ios_auth_start (string auth_url, owned IosTokenCallback callback);
