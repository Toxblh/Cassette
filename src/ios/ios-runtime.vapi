[CCode (cname = "GdkIosMainFunc", has_target = false)]
public delegate int IosMainFunc (int argc, [CCode (array_length = false)] string[] argv);

[CCode (cname = "gdk_ios_main", cheader_filename = "gdk/ios/gdkios.h")]
public extern int gdk_ios_main (int argc, [CCode (array_length = false)] string[] argv, IosMainFunc app_main);

[CCode (cname = "cassette_ios_setup_env", cheader_filename = "ios-runtime.h")]
public extern void cassette_ios_setup_env ();

[CCode (cname = "cassette_ios_bundle_path", cheader_filename = "ios-runtime.h")]
public extern unowned string cassette_ios_bundle_path ();
