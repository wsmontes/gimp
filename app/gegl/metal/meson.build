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

  # Note: Metal shaders will be compiled at runtime from source
  # To pre-compile shaders, install Xcode (not just Command Line Tools)
  # and uncomment the shader compilation below

  # metal_compiler = find_program('xcrun')
  # metal_shader_air = custom_target('metal_shaders_air',
  #   input: 'shaders.metal',
  #   output: 'shaders.air',
  #   command: [metal_compiler, '-sdk', 'macosx', 'metal',
  #             '-c', '@INPUT@', '-o', '@OUTPUT@']
  # )
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
