project(
    'wayfire-ninjaslash',
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

add_project_arguments(['-DWLR_USE_UNSTABLE'], language: 'cpp')
add_project_arguments(['-DWAYFIRE_PLUGIN'], language: 'cpp')
add_project_link_arguments(['-rdynamic'], language: 'cpp')

shared_module('ninjaslash', 'src/ninjaslash.cpp',
    dependencies: [wayfire],
    install: true,
    install_dir: wayfire.get_variable(pkgconfig: 'plugindir'))

install_data('metadata/ninjaslash.xml',
    install_dir: wayfire.get_variable(pkgconfig: 'metadatadir'))

install_data('assets/espada-ninja.mp3',
    install_dir: join_paths(get_option('prefix'), 'share', 'ninjaslash'))
