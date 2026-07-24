project(
    'wayfire-intro',
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
cairo = dependency('cairo')

add_project_arguments(['-DWLR_USE_UNSTABLE'], language: 'cpp')
add_project_arguments(['-DWAYFIRE_PLUGIN'], language: 'cpp')
add_project_link_arguments(['-rdynamic'], language: 'cpp')

shared_module('intro', 'src/intro.cpp',
    dependencies: [wayfire, cairo],
    install: true,
    install_dir: wayfire.get_variable(pkgconfig: 'plugindir'))

install_data('metadata/intro.xml',
    install_dir: wayfire.get_variable(pkgconfig: 'metadatadir'))
