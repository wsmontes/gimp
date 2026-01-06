# Metal backend for GIMP GEGL operations

metal_sources = []
metal_dep = []

if platform_osx
  metal_sources = [
    'gimp-gegl-metal.m',
    'gimp-gegl-metal.h',
    'gimp-gegl-loops-metal.m',
    'gimp-gegl-loops-metal.h',
  ]

  # Declare Metal frameworks as dependencies
  metal_dep = declare_dependency(
    link_args: ['-framework', 'Metal', '-framework', 'MetalPerformanceShaders']
  )

  # Check if we have Xcode for shader pre-compilation
  metal_compiler = find_program('xcrun', required: false)
  has_metal_compiler = false

  if metal_compiler.found()
    # Test if metal compiler is actually available (requires full Xcode, not just CLT)
    result = run_command('xcrun', '-find', 'metal', check: false)
    has_metal_compiler = result.returncode() == 0
  endif

  if has_metal_compiler
    # Compile .metal -> .air (intermediate representation)
    metal_shader_air = custom_target('metal_shaders_air',
      input: 'shaders.metal',
      output: 'shaders.air',
      command: [metal_compiler, '-sdk', 'macosx', 'metal',
                '-c', '@INPUT@', '-o', '@OUTPUT@']
    )

    # Compile .air -> .metallib (Metal library)
    metal_shader_lib = custom_target('metal_shaders_metallib',
      input: metal_shader_air,
      output: 'default.metallib',
      command: [metal_compiler, '-sdk', 'macosx', 'metallib',
                '@INPUT@', '-o', '@OUTPUT@'],
      install: true,
      install_dir: get_option('libdir') / 'gimp' / gimp_app_version / 'metal'
    )

    message('Metal shaders will be pre-compiled (Xcode found)')
  else
    # Install source shaders for runtime compilation
    install_data('shaders.metal',
      install_dir: get_option('datadir') / 'gimp' / gimp_app_version / 'metal')

    message('Metal shaders will be compiled at runtime (Xcode not found)')
    message('For better performance, install Xcode from the App Store')
  endif
endif

libappmetal = static_library('appmetal',
  metal_sources,
  include_directories: [ rootInclude, rootAppInclude, ],
  c_args: '-DG_LOG_DOMAIN="Gimp-Metal"',
  objc_args: ['-DG_LOG_DOMAIN="Gimp-Metal"', '-DHAVE_METAL'],
  dependencies: [
    gegl, gexiv2,
  ],
)
