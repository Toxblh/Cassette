project('cassette-ios-hello', ['c', 'objc'],
  version: '0.1',
  meson_version: '>= 1.3.0',
  default_options: ['default_library=static', 'c_std=gnu11'],
)

gtk = dependency('gtk4')
uikit = dependency('appleframeworks', modules: ['UIKit', 'Foundation', 'QuartzCore', 'CoreGraphics'])

executable('hello', 'main.c',
  dependencies: [gtk, uikit],
  c_args: ['-xobjective-c'],
  install: false,
)
