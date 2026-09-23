[CCode (cname = "GdkIosMainFunc", has_target = false)]
public delegate int IosMainFunc (int argc, [CCode (array_length = false)] string[] argv);

[CCode (cname = "gdk_ios_main", cheader_filename = "gdk/ios/gdkios.h")]
public extern int gdk_ios_main (int argc, [CCode (array_length = false)] string[] argv, IosMainFunc app_main);

[CCode (cname = "cassette_ios_setup_env", cheader_filename = "ios-runtime.h")]
public extern void cassette_ios_setup_env ();

[CCode (cname = "cassette_ios_bundle_path", cheader_filename = "ios-runtime.h")]
public extern unowned string cassette_ios_bundle_path ();

[CCode (cname = "gdk_ios_set_bars_colors", cheader_filename = "gdk/ios/gdkios.h")]
public extern void gdk_ios_set_bars_colors (uint32 top_argb, uint32 bottom_argb);

[CCode (cname = "gdk_ios_get_safe_area", cheader_filename = "gdk/ios/gdkios.h")]
public extern void gdk_ios_get_safe_area (out int top, out int bottom, out int left, out int right);

[CCode (cname = "cassette_ios_stalls_start", cheader_filename = "ios-stalls.h")]
public extern void cassette_ios_stalls_start ();
