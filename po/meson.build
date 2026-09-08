i18n.gettext(meson.project_name(), preset: 'glib')

# pixiewood installs `--tags runtime` only, which skips the i18n tag: copy
# the compiled catalogues ourselves on Android.
if host_machine.system() == 'android'
  meson.add_install_script(
    find_program('python3'), files('install-mo.py'),
    install_tag: 'runtime',
  )
endif
