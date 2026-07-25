project(
    'wayfire-gtkdecor',
    'cpp',
    version: '0.1.0',
    license: 'MIT',
    meson_version: '>=0.51.0',
    default_options: [
        'cpp_std=c++17',
        'warning_level=2',
        'werror=false',
    ],
)

wayfire = dependency('wayfire', version: '>=0.10.0')
wlroots = dependency('wlroots-0.19')
wfconfig = dependency('wf-config')
cairo = dependency('cairo')
pango = dependency('pango')
pangocairo = dependency('pangocairo')

add_project_arguments(['-DWLR_USE_UNSTABLE'], language: 'cpp')
add_project_arguments(['-DWAYFIRE_PLUGIN'], language: 'cpp')
add_project_link_arguments(['-rdynamic'], language: 'cpp')

shared_module('gtkdecor',
    ['src/gtkdecor.cpp', 'src/deco-node.cpp', 'src/deco-button.cpp',
      'src/deco-layout.cpp', 'src/deco-theme.cpp'],
    dependencies: [wayfire, wlroots, wfconfig, cairo, pango, pangocairo],
    install: true,
    install_dir: wayfire.get_variable(pkgconfig: 'plugindir'))

install_data('metadata/gtkdecor.xml',
    install_dir: wayfire.get_variable(pkgconfig: 'metadatadir'))
