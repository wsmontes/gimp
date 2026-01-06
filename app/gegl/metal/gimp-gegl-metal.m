/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-gegl-metal.m
 * Metal GPU acceleration backend for GEGL operations
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#include "config.h"

#ifdef HAVE_METAL

#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

#include <glib.h>
#include <gegl.h>

#include "gimp-gegl-metal.h"


struct _GimpMetalContext
{
  id<MTLDevice>                device;
  id<MTLCommandQueue>          command_queue;
  id<MTLLibrary>               library;
  id<MTLComputePipelineState>  brightness_contrast_pipeline;
  id<MTLComputePipelineState>  desaturate_pipeline;
  id<MTLComputePipelineState>  invert_pipeline;
  id<MTLComputePipelineState>  hue_saturation_pipeline;
  id<MTLComputePipelineState>  convolve_3x3_pipeline;
  id<MTLComputePipelineState>  threshold_pipeline;
  gboolean                     initialized;
};


struct _GimpMetalBuffer
{
  id<MTLTexture> texture;
  gint           width;
  gint           height;
  gint           bytes_per_pixel;
  MTLPixelFormat pixel_format;
};


static gboolean metal_enabled = TRUE;
static GimpMetalContext *global_context = NULL;


/* ============================================================================
 * Context Management
 * ============================================================================ */

/**
 * gimp_metal_context_is_available:
 *
 * Check if Metal is available on this system
 *
 * Returns: TRUE if Metal is available
 */
gboolean
gimp_metal_context_is_available (void)
{
#ifdef PLATFORM_OSX
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device != nil)
      {
        return TRUE;
      }
  }
#endif
  return FALSE;
}


/**
 * gimp_metal_context_new:
 *
 * Create a new Metal context
 *
 * Returns: (nullable): A new #GimpMetalContext or NULL on failure
 */
GimpMetalContext *
gimp_metal_context_new (void)
{
  @autoreleasepool {
    GimpMetalContext *context;

    if (!gimp_metal_context_is_available())
      {
        g_warning ("Metal is not available on this system");
        return NULL;
      }

    context = g_new0 (GimpMetalContext, 1);

    context->device = MTLCreateSystemDefaultDevice();
    if (context->device == nil)
      {
        g_warning ("Failed to create Metal device");
        g_free (context);
        return NULL;
      }

    [context->device retain];

    context->command_queue = [context->device newCommandQueue];
    if (context->command_queue == nil)
      {
        g_warning ("Failed to create Metal command queue");
        [context->device release];
        g_free (context);
        return NULL;
      }

    [context->command_queue retain];

    // Load Metal library (pre-compiled or runtime compilation)
    NSError *library_error = nil;
    context->library = nil;

    // Try 1: Load pre-compiled metallib (if Xcode was available during build)
    NSString *metallib_path = @"/opt/homebrew/lib/gimp/" GIMP_APP_VERSION "/metal/default.metallib";
    if ([[NSFileManager defaultManager] fileExistsAtPath:metallib_path])
      {
        NSURL *library_url = [NSURL fileURLWithPath:metallib_path];
        context->library = [context->device newLibraryWithURL:library_url error:&library_error];
        if (context->library != nil)
          g_message ("✅ Loaded pre-compiled Metal library (optimal performance)");
        else
          g_warning ("Failed to load pre-compiled Metal library: %s",
                    [[library_error localizedDescription] UTF8String]);
      }

    // Try 2: Runtime compilation from installed shader source
    if (context->library == nil)
      {
        NSString *shader_path = @"/opt/homebrew/share/gimp/3.2/metal/shaders.metal";
        if ([[NSFileManager defaultManager] fileExistsAtPath:shader_path])
          {
            NSString *shader_source = [NSString stringWithContentsOfFile:shader_path
                                                                encoding:NSUTF8StringEncoding
                                                                   error:&library_error];
            if (shader_source != nil)
              {
                MTLCompileOptions *options = [[MTLCompileOptions alloc] init];
                options.languageVersion = MTLLanguageVersion3_0;
                // Use mathMode instead of deprecated fastMathEnabled
                if (@available(macOS 15.0, *))
                  options.mathMode = MTLMathModeFast;

                context->library = [context->device newLibraryWithSource:shader_source
                                                                 options:options
                                                                   error:&library_error];
                [options release];

                if (context->library != nil)
                  {
                    g_message ("✅ Compiled Metal shaders at runtime from %s", [shader_path UTF8String]);
                    g_message ("   For optimal performance, install Xcode to pre-compile shaders");
                  }
                else
                  {
                    g_warning ("Failed to compile Metal shaders: %s",
                              [[library_error localizedDescription] UTF8String]);
                  }
              }
          }
      }

    // Try 3: Fallback to default library (if somehow embedded)
    if (context->library == nil)
      {
        context->library = [context->device newDefaultLibrary];
        if (context->library != nil)
          g_message ("Loaded default Metal library");
      }

    if (context->library == nil)
      {
        g_warning ("❌ Failed to load Metal shader library - Metal backend disabled");
        g_warning ("   Install shaders.metal to: /opt/homebrew/share/gimp/" GIMP_APP_VERSION "/metal/");
        [context->command_queue release];
        [context->device release];
        g_free (context);
        return NULL;
      }
    [context->library retain];

    // Create compute pipeline states for all shaders
    NSError *error = nil;
    id<MTLFunction> function;

    // Brightness/Contrast pipeline
    function = [context->library newFunctionWithName:@"brightness_contrast"];
    if (function)
      {
        context->brightness_contrast_pipeline =
          [context->device newComputePipelineStateWithFunction:function error:&error];
        if (error != nil)
          g_warning ("Failed to create brightness_contrast pipeline: %s",
                     [[error localizedDescription] UTF8String]);
        [function release];
      }

    // Desaturate pipeline
    function = [context->library newFunctionWithName:@"desaturate"];
    if (function)
      {
        context->desaturate_pipeline =
          [context->device newComputePipelineStateWithFunction:function error:&error];
        if (error != nil)
          g_warning ("Failed to create desaturate pipeline: %s",
                     [[error localizedDescription] UTF8String]);
        [function release];
      }

    // Invert pipeline
    function = [context->library newFunctionWithName:@"invert"];
    if (function)
      {
        context->invert_pipeline =
          [context->device newComputePipelineStateWithFunction:function error:&error];
        if (error != nil)
          g_warning ("Failed to create invert pipeline: %s",
                     [[error localizedDescription] UTF8String]);
        [function release];
      }

    // Hue/Saturation pipeline
    function = [context->library newFunctionWithName:@"hue_saturation"];
    if (function)
      {
        context->hue_saturation_pipeline =
          [context->device newComputePipelineStateWithFunction:function error:&error];
        if (error != nil)
          g_warning ("Failed to create hue_saturation pipeline: %s",
                     [[error localizedDescription] UTF8String]);
        [function release];
      }

    // Convolution 3x3 pipeline
    function = [context->library newFunctionWithName:@"convolve_3x3"];
    if (function)
      {
        context->convolve_3x3_pipeline =
          [context->device newComputePipelineStateWithFunction:function error:&error];
        if (error != nil)
          g_warning ("Failed to create convolve_3x3 pipeline: %s",
                     [[error localizedDescription] UTF8String]);
        [function release];
      }

    // Threshold pipeline
    function = [context->library newFunctionWithName:@"threshold"];
    if (function)
      {
        context->threshold_pipeline =
          [context->device newComputePipelineStateWithFunction:function error:&error];
        if (error != nil)
          g_warning ("Failed to create threshold pipeline: %s",
                     [[error localizedDescription] UTF8String]);
        [function release];
      }

    context->initialized = TRUE;

    g_message ("Metal context initialized: %s (pipelines: %d/6 loaded)",
               [[context->device name] UTF8String],
               (context->brightness_contrast_pipeline != nil ? 1 : 0) +
               (context->desaturate_pipeline != nil ? 1 : 0) +
               (context->invert_pipeline != nil ? 1 : 0) +
               (context->hue_saturation_pipeline != nil ? 1 : 0) +
               (context->convolve_3x3_pipeline != nil ? 1 : 0) +
               (context->threshold_pipeline != nil ? 1 : 0));

    return context;
  }
}


/**
 * gimp_metal_context_free:
 * @context: A #GimpMetalContext
 *
 * Free a Metal context and release all resources
 */
void
gimp_metal_context_free (GimpMetalContext *context)
{
  @autoreleasepool {
    if (context == NULL)
      return;

    if (context->brightness_contrast_pipeline != nil)
      [context->brightness_contrast_pipeline release];
    if (context->desaturate_pipeline != nil)
      [context->desaturate_pipeline release];
    if (context->invert_pipeline != nil)
      [context->invert_pipeline release];
    if (context->hue_saturation_pipeline != nil)
      [context->hue_saturation_pipeline release];
    if (context->convolve_3x3_pipeline != nil)
      [context->convolve_3x3_pipeline release];
    if (context->threshold_pipeline != nil)
      [context->threshold_pipeline release];

    if (context->library != nil)
      [context->library release];

    if (context->command_queue != nil)
      [context->command_queue release];

    if (context->device != nil)
      [context->device release];

    g_free (context);
  }
}


const gchar *
gimp_metal_context_get_device_name (GimpMetalContext *context)
{
  @autoreleasepool {
    if (context == NULL || context->device == nil)
      return "Unknown";

    return [[context->device name] UTF8String];
  }
}


/**
 * gimp_metal_context_get_name:
 * @context: A #GimpMetalContext
 *
 * Get the name of the Metal device (alias for get_device_name)
 *
 * Returns: Device name string
 */
const gchar *
gimp_metal_context_get_name (GimpMetalContext *context)
{
  return gimp_metal_context_get_device_name (context);
}


/* ============================================================================
 * Buffer Management
 * ============================================================================ */

/**
 * gimp_metal_buffer_new:
 * @context: A #GimpMetalContext
 * @width: Buffer width
 * @height: Buffer height
 *
 * Create a new empty Metal buffer
 *
 * Returns: (nullable): A new #GimpMetalBuffer or NULL on failure
 */
GimpMetalBuffer *
gimp_metal_buffer_new (GimpMetalContext *context,
                       gint              width,
                       gint              height)
{
  @autoreleasepool {
    GimpMetalBuffer *metal_buffer;
    MTLTextureDescriptor *descriptor;
    MTLPixelFormat pixel_format = MTLPixelFormatRGBA32Float;

    if (context == NULL)
      return NULL;

    metal_buffer = g_new0 (GimpMetalBuffer, 1);
    metal_buffer->width = width;
    metal_buffer->height = height;
    metal_buffer->bytes_per_pixel = 16; // RGBA Float32
    metal_buffer->pixel_format = pixel_format;

    descriptor = [MTLTextureDescriptor
                  texture2DDescriptorWithPixelFormat:pixel_format
                  width:width
                  height:height
                  mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

    // Use Private storage mode for GPU-only buffers (faster)
    // Use Managed only if we need CPU access
    descriptor.storageMode = MTLStorageModePrivate;

    metal_buffer->texture = [context->device newTextureWithDescriptor:descriptor];
    if (metal_buffer->texture == nil)
      {
        g_warning ("Failed to create Metal texture");
        g_free (metal_buffer);
        return NULL;
      }

    [metal_buffer->texture retain];

    return metal_buffer;
  }
}


/**
 * gimp_metal_buffer_copy_to_gegl:
 * @metal_buffer: A #GimpMetalBuffer
 * @gegl_buffer: Target GeglBuffer
 * @rect: Region to copy to
 *
 * Copy Metal buffer data back to GEGL buffer
 */
void
gimp_metal_buffer_copy_to_gegl (GimpMetalBuffer     *metal_buffer,
                                GeglBuffer          *gegl_buffer,
                                const GeglRectangle *rect)
{
  @autoreleasepool {
    const Babl *format;
    guchar *pixels;
    MTLRegion region;

    if (metal_buffer == NULL || gegl_buffer == NULL)
      return;

    format = gegl_buffer_get_format (gegl_buffer);

    pixels = g_malloc (rect->width * rect->height * metal_buffer->bytes_per_pixel);

    region = MTLRegionMake2D (0, 0, rect->width, rect->height);
    [metal_buffer->texture getBytes:pixels
                        bytesPerRow:rect->width * metal_buffer->bytes_per_pixel
                         fromRegion:region
                        mipmapLevel:0];

    gegl_buffer_set (gegl_buffer, rect, 0, format, pixels, GEGL_AUTO_ROWSTRIDE);

    g_free (pixels);
  }
}



/**
 * gimp_metal_buffer_new_from_gegl:
 * @context: A #GimpMetalContext
 * @buffer: Source GeglBuffer
 * @rect: Region to transfer (or NULL for entire buffer)
 *
 * Create a Metal texture from a GEGL buffer
 *
 * Returns: (nullable): A new #GimpMetalBuffer or NULL on failure
 */
GimpMetalBuffer *
gimp_metal_buffer_new_from_gegl (GimpMetalContext    *context,
                                 GeglBuffer          *buffer,
                                 const GeglRectangle *rect)
{
  @autoreleasepool {
    GimpMetalBuffer *metal_buffer;
    GeglRectangle    extent;
    const Babl      *format;
    gint             bpp;
    guchar          *pixels;
    MTLTextureDescriptor *descriptor;
    MTLPixelFormat   pixel_format;

    if (context == NULL || buffer == NULL)
      return NULL;

    if (rect == NULL)
      extent = *gegl_buffer_get_extent (buffer);
    else
      extent = *rect;

    format = gegl_buffer_get_format (buffer);
    bpp = babl_format_get_bytes_per_pixel (format);

    // Determine pixel format based on bytes per pixel
    switch (bpp)
      {
      case 4:  // RGBA8
        pixel_format = MTLPixelFormatRGBA8Unorm;
        break;
      case 16: // RGBA Float32
        pixel_format = MTLPixelFormatRGBA32Float;
        break;
      default:
        g_warning ("Unsupported pixel format: %d bytes per pixel", bpp);
        return NULL;
      }

    metal_buffer = g_new0 (GimpMetalBuffer, 1);
    metal_buffer->width = extent.width;
    metal_buffer->height = extent.height;
    metal_buffer->bytes_per_pixel = bpp;
    metal_buffer->pixel_format = pixel_format;

    // Create texture descriptor
    descriptor = [MTLTextureDescriptor
                  texture2DDescriptorWithPixelFormat:pixel_format
                  width:extent.width
                  height:extent.height
                  mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

    // Use Shared storage mode for data transfer between CPU and GPU
    descriptor.storageMode = MTLStorageModeShared;

    metal_buffer->texture = [context->device newTextureWithDescriptor:descriptor];
    if (metal_buffer->texture == nil)
      {
        g_warning ("Failed to create Metal texture");
        g_free (metal_buffer);
        return NULL;
      }

    [metal_buffer->texture retain];

    // Transfer data from GEGL to Metal
    pixels = g_malloc (extent.width * extent.height * bpp);
    gegl_buffer_get (buffer, &extent, 1.0, format, pixels,
                     GEGL_AUTO_ROWSTRIDE, GEGL_ABYSS_NONE);

    MTLRegion region = MTLRegionMake2D (0, 0, extent.width, extent.height);
    [metal_buffer->texture replaceRegion:region
                             mipmapLevel:0
                               withBytes:pixels
                             bytesPerRow:extent.width * bpp];

    g_free (pixels);

    return metal_buffer;
  }
}


/**
 * gimp_metal_buffer_to_gegl:
 * @metal_buffer: A #GimpMetalBuffer
 * @format: Target format
 *
 * Convert a Metal buffer back to a GEGL buffer
 *
 * Returns: (transfer full): A new GeglBuffer
 */
GeglBuffer *
gimp_metal_buffer_to_gegl (GimpMetalBuffer *metal_buffer,
                           const Babl      *format)
{
  @autoreleasepool {
    GeglBuffer *buffer;
    guchar     *pixels;
    gint        bytes_per_row;
    MTLRegion   region;

    if (metal_buffer == NULL || metal_buffer->texture == nil)
      return NULL;

    buffer = gegl_buffer_new (GEGL_RECTANGLE (0, 0,
                                              metal_buffer->width,
                                              metal_buffer->height),
                              format);

    bytes_per_row = metal_buffer->width * metal_buffer->bytes_per_pixel;
    pixels = g_malloc (metal_buffer->height * bytes_per_row);

    region = MTLRegionMake2D (0, 0, metal_buffer->width, metal_buffer->height);
    [metal_buffer->texture getBytes:pixels
                        bytesPerRow:bytes_per_row
                         fromRegion:region
                        mipmapLevel:0];

    gegl_buffer_set (buffer,
                     GEGL_RECTANGLE (0, 0, metal_buffer->width, metal_buffer->height),
                     0, format, pixels, GEGL_AUTO_ROWSTRIDE);

    g_free (pixels);

    return buffer;
  }
}


/**
 * gimp_metal_buffer_free:
 * @buffer: A #GimpMetalBuffer
 *
 * Free a Metal buffer
 */
void
gimp_metal_buffer_free (GimpMetalBuffer *buffer)
{
  @autoreleasepool {
    if (buffer == NULL)
      return;

    if (buffer->texture != nil)
      [buffer->texture release];

    g_free (buffer);
  }
}


/* ============================================================================
 * Core Operations
 * ============================================================================ */

/**
 * gimp_metal_blur_gaussian:
 * @context: A #GimpMetalContext
 * @src: Source buffer
 * @dest: Destination buffer
 * @sigma: Blur sigma (standard deviation)
 *
 * Apply Gaussian blur using Metal Performance Shaders
 *
 * Returns: TRUE on success
 */
gboolean
gimp_metal_blur_gaussian (GimpMetalContext *context,
                          GimpMetalBuffer  *src,
                          GimpMetalBuffer  *dest,
                          gfloat            sigma)
{
  @autoreleasepool {
    if (context == NULL || src == NULL || dest == NULL)
      return FALSE;

    id<MTLCommandBuffer> command_buffer = [context->command_queue commandBuffer];

    // Use Metal Performance Shaders for efficient Gaussian blur
    MPSImageGaussianBlur *blur = [[MPSImageGaussianBlur alloc]
                                  initWithDevice:context->device
                                  sigma:sigma];

    [blur encodeToCommandBuffer:command_buffer
                   sourceTexture:src->texture
              destinationTexture:dest->texture];

    [command_buffer commit];
    [command_buffer waitUntilCompleted];

    [blur release];

    return [command_buffer status] == MTLCommandBufferStatusCompleted;
  }
}


/**
 * gimp_metal_brightness_contrast:
 * @context: A #GimpMetalContext
 * @src: Source buffer
 * @dest: Destination buffer
 * @brightness: Brightness adjustment (-1.0 to 1.0)
 * @contrast: Contrast adjustment (-1.0 to 1.0)
 *
 * Adjust brightness and contrast using compute shader
 *
 * Returns: TRUE on success
 */
gboolean
gimp_metal_brightness_contrast (GimpMetalContext *context,
                                GimpMetalBuffer  *src,
                                GimpMetalBuffer  *dest,
                                gfloat            brightness,
                                gfloat            contrast)
{
  @autoreleasepool {
    if (context == NULL || src == NULL || dest == NULL)
      return FALSE;

    if (context->brightness_contrast_pipeline == nil)
      {
        g_warning ("Brightness/contrast pipeline not available");
        return FALSE;
      }

    id<MTLCommandBuffer> command_buffer = [context->command_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];

    [encoder setComputePipelineState:context->brightness_contrast_pipeline];
    [encoder setTexture:src->texture atIndex:0];
    [encoder setTexture:dest->texture atIndex:1];
    [encoder setBytes:&brightness length:sizeof(float) atIndex:0];
    [encoder setBytes:&contrast length:sizeof(float) atIndex:1];

    MTLSize threadgroup_size = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
      (src->width + threadgroup_size.width - 1) / threadgroup_size.width,
      (src->height + threadgroup_size.height - 1) / threadgroup_size.height,
      1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroup_size];
    [encoder endEncoding];
    [command_buffer commit];
    [command_buffer waitUntilCompleted];

    return [command_buffer status] == MTLCommandBufferStatusCompleted;
  }
}


/**
 * gimp_metal_buffer_copy:
 * @context: A #GimpMetalContext
 * @src: Source buffer
 * @dest: Destination buffer
 *
 * Copy buffer using Metal blit encoder
 *
 * Returns: TRUE on success
 */
gboolean
gimp_metal_buffer_copy (GimpMetalContext *context,
                        GimpMetalBuffer  *src,
                        GimpMetalBuffer  *dest)
{
  @autoreleasepool {
    if (context == NULL || src == NULL || dest == NULL)
      return FALSE;

    if (src->width != dest->width || src->height != dest->height)
      {
        g_warning ("Buffer dimensions must match for copy");
        return FALSE;
      }

    id<MTLCommandBuffer> command_buffer = [context->command_queue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [command_buffer blitCommandEncoder];

    MTLOrigin origin = MTLOriginMake (0, 0, 0);
    MTLSize size = MTLSizeMake (src->width, src->height, 1);

    [blit copyFromTexture:src->texture
             sourceSlice:0
             sourceLevel:0
            sourceOrigin:origin
              sourceSize:size
               toTexture:dest->texture
        destinationSlice:0
        destinationLevel:0
       destinationOrigin:origin];

    [blit endEncoding];
    [command_buffer commit];
    [command_buffer waitUntilCompleted];

    return [command_buffer status] == MTLCommandBufferStatusCompleted;
  }
}


/* Stub implementations for operations to be implemented */
gboolean
gimp_metal_desaturate (GimpMetalContext *context,
                       GimpMetalBuffer  *src,
                       GimpMetalBuffer  *dest)
{
  @autoreleasepool {
    if (context == NULL || src == NULL || dest == NULL)
      return FALSE;

    if (context->desaturate_pipeline == nil)
      return FALSE;

    id<MTLCommandBuffer> command_buffer = [context->command_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];

    [encoder setComputePipelineState:context->desaturate_pipeline];
    [encoder setTexture:src->texture atIndex:0];
    [encoder setTexture:dest->texture atIndex:1];

    MTLSize threadgroup_size = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
      (src->width + 15) / 16,
      (src->height + 15) / 16,
      1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroup_size];
    [encoder endEncoding];
    [command_buffer commit];
    [command_buffer waitUntilCompleted];

    return [command_buffer status] == MTLCommandBufferStatusCompleted;
  }
}

gboolean
gimp_metal_invert (GimpMetalContext *context,
                   GimpMetalBuffer  *src,
                   GimpMetalBuffer  *dest)
{
  @autoreleasepool {
    if (context == NULL || src == NULL || dest == NULL)
      return FALSE;

    if (context->invert_pipeline == nil)
      return FALSE;

    id<MTLCommandBuffer> command_buffer = [context->command_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];

    [encoder setComputePipelineState:context->invert_pipeline];
    [encoder setTexture:src->texture atIndex:0];
    [encoder setTexture:dest->texture atIndex:1];

    MTLSize threadgroup_size = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
      (src->width + 15) / 16,
      (src->height + 15) / 16,
      1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroup_size];
    [encoder endEncoding];
    [command_buffer commit];
    [command_buffer waitUntilCompleted];

    return [command_buffer status] == MTLCommandBufferStatusCompleted;
  }
}

gboolean
gimp_metal_hue_saturation (GimpMetalContext *context,
                           GimpMetalBuffer  *src,
                           GimpMetalBuffer  *dest,
                           gfloat            hue_offset,
                           gfloat            saturation,
                           gfloat            lightness)
{
  @autoreleasepool {
    if (context == NULL || src == NULL || dest == NULL)
      return FALSE;

    if (context->hue_saturation_pipeline == nil)
      return FALSE;

    id<MTLCommandBuffer> command_buffer = [context->command_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];

    [encoder setComputePipelineState:context->hue_saturation_pipeline];
    [encoder setTexture:src->texture atIndex:0];
    [encoder setTexture:dest->texture atIndex:1];
    [encoder setBytes:&hue_offset length:sizeof(float) atIndex:0];
    [encoder setBytes:&saturation length:sizeof(float) atIndex:1];
    [encoder setBytes:&lightness length:sizeof(float) atIndex:2];

    MTLSize threadgroup_size = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
      (src->width + 15) / 16,
      (src->height + 15) / 16,
      1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroup_size];
    [encoder endEncoding];
    [command_buffer commit];
    [command_buffer waitUntilCompleted];

    return [command_buffer status] == MTLCommandBufferStatusCompleted;
  }
}

gboolean
gimp_metal_convolve_3x3 (GimpMetalContext *context,
                         GimpMetalBuffer  *src,
                         GimpMetalBuffer  *dest,
                         const gfloat     *kernel)
{
  @autoreleasepool {
    if (context == NULL || src == NULL || dest == NULL || kernel == NULL)
      return FALSE;

    if (context->convolve_3x3_pipeline == nil)
      return FALSE;

    id<MTLCommandBuffer> command_buffer = [context->command_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];

    float divisor = 1.0f;
    for (int i = 0; i < 9; i++)
      divisor += kernel[i];
    if (divisor == 0.0f)
      divisor = 1.0f;

    [encoder setComputePipelineState:context->convolve_3x3_pipeline];
    [encoder setTexture:src->texture atIndex:0];
    [encoder setTexture:dest->texture atIndex:1];
    [encoder setBytes:kernel length:9 * sizeof(float) atIndex:0];
    [encoder setBytes:&divisor length:sizeof(float) atIndex:1];

    MTLSize threadgroup_size = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
      (src->width + 15) / 16,
      (src->height + 15) / 16,
      1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroup_size];
    [encoder endEncoding];
    [command_buffer commit];
    [command_buffer waitUntilCompleted];

    return [command_buffer status] == MTLCommandBufferStatusCompleted;
  }
}

gboolean
gimp_metal_threshold (GimpMetalContext *context,
                      GimpMetalBuffer  *src,
                      GimpMetalBuffer  *dest,
                      gfloat            lower,
                      gfloat            upper)
{
  @autoreleasepool {
    if (context == NULL || src == NULL || dest == NULL)
      return FALSE;

    if (context->threshold_pipeline == nil)
      return FALSE;

    id<MTLCommandBuffer> command_buffer = [context->command_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];

    [encoder setComputePipelineState:context->threshold_pipeline];
    [encoder setTexture:src->texture atIndex:0];
    [encoder setTexture:dest->texture atIndex:1];
    [encoder setBytes:&lower length:sizeof(float) atIndex:0];
    [encoder setBytes:&upper length:sizeof(float) atIndex:1];

    MTLSize threadgroup_size = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
      (src->width + 15) / 16,
      (src->height + 15) / 16,
      1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroup_size];
    [encoder endEncoding];
    [command_buffer commit];
    [command_buffer waitUntilCompleted];

    return [command_buffer status] == MTLCommandBufferStatusCompleted;
  }
}


/* ============================================================================
 * Integration
 * ============================================================================ */

/**
 * gimp_gegl_loops_use_metal:
 *
 * Check if Metal acceleration is enabled
 *
 * Returns: TRUE if Metal should be used
 */
gboolean
gimp_gegl_loops_use_metal (void)
{
  return metal_enabled && gimp_metal_context_is_available();
}


/**
 * gimp_gegl_loops_set_use_metal:
 * @use_metal: TRUE to enable Metal acceleration
 *
 * Enable or disable Metal acceleration
 */
void
gimp_gegl_loops_set_use_metal (gboolean use_metal)
{
  metal_enabled = use_metal;

  if (use_metal && global_context == NULL)
    {
      global_context = gimp_metal_context_new();
    }
  else if (!use_metal && global_context != NULL)
    {
      gimp_metal_context_free (global_context);
      global_context = NULL;
    }
}

#endif /* HAVE_METAL */
