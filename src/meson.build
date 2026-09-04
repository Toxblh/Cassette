vapi_sources = files(
  'config.vapi',
)

cassette_gui_sources = files(
  'widgets/action-cards/custom.vala',
  'widgets/action-cards/station.vala',

  'widgets/begin/begin-dialog.vala',
  'widgets/begin/begin-view.vala',

  'widgets/buttons/just/play-buttons/abstract-play-button-default.vala',
  'widgets/buttons/just/play-buttons/abstract-play-button.vala',
  'widgets/buttons/just/play-buttons/play-button-action.vala',
  'widgets/buttons/just/play-buttons/play-button-context.vala',
  'widgets/buttons/just/play-buttons/play-button-track.vala',
  'widgets/buttons/just/abstract-custom-button.vala',
  'widgets/buttons/just/like-button.vala',
  'widgets/buttons/just/dislike-button.vala',
  'widgets/buttons/menu/abstract-menu-button.vala',
  'widgets/buttons/menu/menu-dialog.vala',
  'widgets/buttons/menu/primary-menu-button.vala',
  'widgets/buttons/menu/playlist-options-button.vala',
  'widgets/buttons/menu/track-options-button.vala',
  'widgets/buttons/menu/track-playlist-options-button.vala',
  'widgets/buttons/menu/track-queue-options-button.vala',
  'widgets/buttons/menu/volume-button.vala',
  'widgets/buttons/label-button.vala',
  'widgets/buttons/playlist-create-button.vala',

  'widgets/cache-indicator/cache-indicator.vala',
  'widgets/cache-indicator/job-info-badge.vala',

  'widgets/lyrics/lyrics-line.vala',
  'widgets/lyrics/lyrics-panel.vala',

  'widgets/pages/abstract-loadable-page.vala',
  'widgets/pages/loading-page.vala',

  'widgets/play-mark/abstract-play-mark-default.vala',
  'widgets/play-mark/abstract-play-mark.vala',
  'widgets/play-mark/play-mark-context.vala',
  'widgets/play-mark/play-mark-global.vala',
  'widgets/play-mark/play-mark-track.vala',

  'widgets/preferences/cache-deletion-preferences.vala',
  'widgets/preferences/custom-page-preferences.vala',
  'widgets/preferences/custom-pages-preferences.vala',
  'widgets/preferences/preferences-dialog.vala',

  'widgets/shrinkable/application-window.vala',
  'widgets/shrinkable/bin.vala',

  'widgets/sidebar/childs/history.vala',
  'widgets/sidebar/childs/player-queue.vala',
  'widgets/sidebar/childs/track-info.vala',
  'widgets/sidebar/childs/wave-settings.vala',
  'widgets/sidebar/sidebar-child-bin.vala',
  'widgets/sidebar/sidebar.vala',

  'widgets/track-list/track-list.vala',
  'widgets/track-list/track-row-base.vala',
  'widgets/track-list/tracks-model.vala',
  'widgets/track-list/tracks-view.vala',

  'widgets/track-rows/base.vala',
  'widgets/track-rows/default.vala',
  'widgets/track-rows/local.vala',
  'widgets/track-rows/placeholder.vala',
  'widgets/track-rows/queue.vala',
  'widgets/track-rows/track-row.vala',

  'widgets/views/abstract-base.vala',
  'widgets/views/abstract-cachiable.vala',
  'widgets/views/abstract-with-tracks.vala',
  'widgets/views/cant-show.vala',
  'widgets/views/devel.vala',
  'widgets/views/disliked.vala',
  'widgets/views/playlist.vala',
  'widgets/views/playlists.vala',
  'widgets/views/stations.vala',
  
  'widgets/abstract-reactable.vala',
  'widgets/account-info-dialog.vala',
  'widgets/equalaizer.vala',
  'widgets/cover-image.vala',
  'widgets/header-bar.vala',
  'widgets/headered-scrolled-window.vala',
  'widgets/info-marks.vala',
  'widgets/loadable-widget.vala',
  'widgets/loading-spinner.vala',
  'widgets/narrow-toggle-button.vala',
  'widgets/no-plus-dialog.vala',
  'widgets/page-root.vala',
  'widgets/player-bar.vala',
  'widgets/playlist-choose-dialog.vala',
  'widgets/playlist-micro.vala',
  'widgets/playlist-row.vala',
  'widgets/save-stack.vala',
  'widgets/theme-switcher.vala',
  'widgets/track-carousel.vala',
  'widgets/track-info-panel.vala',

  'about.vala',
  'application.vala',
  'authenticator.vala',
  'window.vala',
  'main.vala',
  'pager.vala',
  'utils.vala',
)

subdir('client')

cassette_sources = [
  vapi_sources,
  blueprints,
  cassette_gui_sources,
  cassette_client_sources,
  resources
]

cassette_vala_args = [
  '--target-glib', '2.76',
  '--vapidir', meson.current_source_dir()
] + webkit_vala_args

if is_android
  # The libraries come from subprojects, so meson passes no --pkg for them;
  # valac finds the vapis in its own vapidir, except libadwaita-1 and
  # libsoup-3.0 which the libraries themselves ship — snapshots of those
  # live in build-aux/android/vapi.
  cassette_vala_args += [
    '--define=ANDROID',
    '--vapidir', meson.project_source_root() / 'build-aux' / 'android' / 'vapi',
    '--pkg=gtk4',
    '--pkg=libadwaita-1',
    '--pkg=libsoup-3.0',
    '--pkg=json-glib-1.0',
    '--pkg=gdk-pixbuf-2.0',
    '--pkg=sqlite3',
    '--pkg=libxml-2.0',
    '--pkg=gio-2.0',
  ]
endif

cassette_c_args = [
  '-include', 'config.h',
]

# GCC14 COMPILE ERROR
cassette_c_args += [
  '-Wno-int-conversion',
]
# END GCC14

cassette_link_args = ['-lm']

macos_inc = []
if host_machine.system() == 'darwin'
  cassette_vala_args += ['--define=MACOS']
  cassette_sources += files(
    'macos/macos-now-playing.m',
    'macos/macos-now-playing.vapi',
    'macos/now-playing.vala',
  )
  cassette_link_args += ['-framework', 'MediaPlayer', '-framework', 'AppKit', '-framework', 'Foundation']
  cassette_c_args += ['-fobjc-arc']
  macos_inc = include_directories('macos')
  if not get_option('with_webkit')
    cassette_sources += files(
      'macos/macos-webkit-auth.m',
      'macos/macos-webkit-auth.vapi',
    )
    cassette_link_args += ['-framework', 'WebKit']
  endif
endif

android_inc = []
exe_kwargs = {}
if is_android
  cassette_sources += files(
    'android/android-auth.c',
    'android/android-auth.vapi',
    'android/android-bars.c',
    'android/android-bars.vapi',
    'android/android-jni.c',
    'android/android-now-playing.c',
    'android/android-now-playing.vapi',
    'android/android-player.c',
    'android/android-player.vapi',
    'android/now-playing.vala',
  )
  cassette_link_args += ['-llog']
  android_inc = include_directories('android')
  # pixiewood: the executable becomes lib<name>.so and its main() is looked
  # up by the GTK Android runtime.
  exe_kwargs = {'android_exe_type': 'application'}
endif

executable(
  meson.project_name(),
  cassette_sources,
  include_directories: [config_h_dir, macos_inc, android_inc],
  vala_args: cassette_vala_args,
  c_args: cassette_c_args,
  link_args: cassette_link_args,
  dependencies: cassette_dependencies,
  install: true,
  kwargs: exe_kwargs,
)