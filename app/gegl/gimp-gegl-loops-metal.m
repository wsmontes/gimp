/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-gegl-loops-metal.m
 * Metal GPU acceleration for GEGL operations
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

#include <gegl.h>
#include <gio/gio.h>

#include "libgimpbase/gimpbase.h"

#include "gimp-gegl-loops-metal.h"


/* Global Metal context */
static id<MTLDevice>       metal_device       = nil;
static id<MTLCommandQueue> metal_queue        = nil;
static id<MTLLibrary>      metal_library      = nil;
static gboolean            metal_initialized  = FALSE;


/* Initialize Metal context */
gboolean
gimp_gegl_metal_init (void)
{
  if (metal_initialized)
    return TRUE;

  @autoreleasepool {
    metal_device = MTLCreateSystemDefaultDevice();

    if (!metal_device)
      {
        g_warning ("Metal: Failed to create device");
        return FALSE;
      }

    metal_queue = [metal_device newCommandQueue];

    if (!metal_queue)
      {
        g_warning ("Metal: Failed to create command queue");
        metal_device = nil;
        return FALSE;
      }

    /* Load shader library */
    NSError *error = nil;

    /* Get GIMP data directory */
    const gchar *data_dir = gimp_data_directory ();
    gchar *metal_dir = g_build_filename (data_dir, "metal", NULL);
    gchar *shader_lib_path = g_build_filename (metal_dir, "shaders.metallib", NULL);
    gchar *shader_src_path = g_build_filename (metal_dir, "shaders.metal", NULL);

    g_message ("Metal: Looking for shaders in: %s", metal_dir);

    NSString *shader_path = [NSString stringWithUTF8String:shader_lib_path];
    NSString *source_path = [NSString stringWithUTF8String:shader_src_path];

    if ([[NSFileManager defaultManager] fileExistsAtPath:shader_path])
      {
        g_message ("Metal: Found precompiled library at %s", shader_lib_path);
        NSURL *library_url = [NSURL fileURLWithPath:shader_path];
        metal_library = [metal_device newLibraryWithURL:library_url error:&error];

        if (error)
          {
            g_message ("Metal: Failed to load precompiled library: %s", [[error localizedDescription] UTF8String]);
            error = nil;
          }
      }

    if (!metal_library)
      {
        /* Fallback: compile shaders at runtime */
        if ([[NSFileManager defaultManager] fileExistsAtPath:source_path])
          {
            g_message ("Metal: Found shader source at %s, compiling...", shader_src_path);
            NSString *source = [NSString stringWithContentsOfFile:source_path
                                                          encoding:NSUTF8StringEncoding
                                                             error:&error];

            if (error)
              {
                g_warning ("Metal: Failed to read shader source: %s", [[error localizedDescription] UTF8String]);
              }
            else
              {
                metal_library = [metal_device newLibraryWithSource:source
                                                            options:nil
                                                              error:&error];

                if (error)
                  {
                    g_warning ("Metal: Failed to compile shaders: %s", [[error localizedDescription] UTF8String]);
                  }
                else if (metal_library)
                  {
                    g_message ("Metal: ✅ Compiled shaders at runtime from %s", shader_src_path);
                  }
              }
          }
        else
          {
            g_warning ("Metal: Shader source not found at %s", shader_src_path);
          }

        if (error || !metal_library)
          {
            g_warning ("Metal: Failed to load/compile shaders");
            g_free (shader_lib_path);
            g_free (shader_src_path);
            g_free (metal_dir);
            metal_queue = nil;
            metal_device = nil;
            return FALSE;
          }
      }

    g_free (shader_lib_path);
    g_free (shader_src_path);
    g_free (metal_dir);

    metal_initialized = TRUE;
    g_message ("Metal: Initialized successfully - %s", [[metal_device name] UTF8String]);
    return TRUE;
  }
}

void
gimp_gegl_metal_shutdown (void)
{
  @autoreleasepool {
    metal_library      = nil;
    metal_queue        = nil;
    metal_device       = nil;
    metal_initialized  = FALSE;
  }
}

gboolean
gimp_gegl_metal_is_available (void)
{
  return metal_initialized;
}


/* Helper: Copy GeglBuffer to Metal texture */
static id<MTLTexture>
buffer_to_metal_texture (GeglBuffer          *buffer,
                        const GeglRectangle *rect,
                        id<MTLDevice>        device)
{
  @autoreleasepool {
    gint width  = rect->width;
    gint height = rect->height;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                     width:width
                                    height:height
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

    id<MTLTexture> texture = [device newTextureWithDescriptor:desc];

    if (!texture)
      return nil;

    /* Read from GeglBuffer */
    gfloat *pixels = g_new (gfloat, width * height * 4);
    gegl_buffer_get (buffer, rect, 1.0, babl_format ("RGBA float"),
                     pixels, GEGL_AUTO_ROWSTRIDE, GEGL_ABYSS_NONE);

    /* Upload to Metal texture */
    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
               mipmapLevel:0
                 withBytes:pixels
               bytesPerRow:width * 4 * sizeof(gfloat)];

    g_free (pixels);
    return texture;
  }
}

/* Helper: Copy Metal texture to GeglBuffer */
static void
metal_texture_to_buffer (id<MTLTexture>       texture,
                        GeglBuffer          *buffer,
                        const GeglRectangle *rect)
{
  @autoreleasepool {
    gint width  = rect->width;
    gint height = rect->height;

    gfloat *pixels = g_new (gfloat, width * height * 4);

    [texture getBytes:pixels
          bytesPerRow:width * 4 * sizeof(gfloat)
           fromRegion:MTLRegionMake2D(0, 0, width, height)
          mipmapLevel:0];

    gegl_buffer_set (buffer, rect, 0, babl_format ("RGBA float"),
                     pixels, GEGL_AUTO_ROWSTRIDE);

    g_free (pixels);
  }
}


/* Metal-accelerated invert */
gboolean
gimp_gegl_metal_invert (GeglBuffer          *src,
                       const GeglRectangle *src_rect,
                       GeglBuffer          *dest,
                       const GeglRectangle *dest_rect)
{
  if (!metal_initialized)
    return FALSE;

  @autoreleasepool {
    /* Convert to Metal textures */
    id<MTLTexture> input_tex = buffer_to_metal_texture (src, src_rect, metal_device);
    if (!input_tex)
      return FALSE;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                     width:dest_rect->width
                                    height:dest_rect->height
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> output_tex = [metal_device newTextureWithDescriptor:desc];

    if (!output_tex)
      return FALSE;

    /* Get shader function */
    id<MTLFunction> function = [metal_library newFunctionWithName:@"gimp_invert_shader"];
    if (!function)
      return FALSE;

    NSError *error = nil;
    id<MTLComputePipelineState> pipeline =
        [metal_device newComputePipelineStateWithFunction:function error:&error];

    if (error || !pipeline)
      return FALSE;

    /* Execute shader */
    id<MTLCommandBuffer> cmd = [metal_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [cmd computeCommandEncoder];

    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:input_tex atIndex:0];
    [encoder setTexture:output_tex atIndex:1];

    MTLSize threads = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
        (dest_rect->width + 15) / 16,
        (dest_rect->height + 15) / 16,
        1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threads];
    [encoder endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];

    /* Copy result back */
    metal_texture_to_buffer (output_tex, dest, dest_rect);

    return TRUE;
  }
}


/* Brightness/Contrast using Metal */
gboolean
gimp_gegl_metal_brightness_contrast (GeglBuffer          *src,
                                    const GeglRectangle *src_rect,
                                    GeglBuffer          *dest,
                                    const GeglRectangle *dest_rect,
                                    gfloat               brightness,
                                    gfloat               contrast)
{
  if (!metal_initialized)
    return FALSE;

  @autoreleasepool {
    id<MTLTexture> input_tex = buffer_to_metal_texture (src, src_rect, metal_device);
    if (!input_tex)
      return FALSE;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                     width:dest_rect->width
                                    height:dest_rect->height
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> output_tex = [metal_device newTextureWithDescriptor:desc];

    if (!output_tex)
      return FALSE;

    id<MTLFunction> function = [metal_library newFunctionWithName:@"gimp_brightness_contrast_shader"];
    if (!function)
      return FALSE;

    NSError *error = nil;
    id<MTLComputePipelineState> pipeline =
        [metal_device newComputePipelineStateWithFunction:function error:&error];

    if (error || !pipeline)
      return FALSE;

    id<MTLCommandBuffer> cmd = [metal_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [cmd computeCommandEncoder];

    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:input_tex atIndex:0];
    [encoder setTexture:output_tex atIndex:1];

    /* Pass parameters */
    float params[2] = { brightness, contrast };
    [encoder setBytes:params length:sizeof(params) atIndex:0];

    MTLSize threads = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
        (dest_rect->width + 15) / 16,
        (dest_rect->height + 15) / 16,
        1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threads];
    [encoder endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];

    metal_texture_to_buffer (output_tex, dest, dest_rect);

    return TRUE;
  }
}


/* Gaussian blur using MPS */
gboolean
gimp_gegl_metal_blur_gaussian (GeglBuffer          *src,
                              const GeglRectangle *src_rect,
                              GeglBuffer          *dest,
                              const GeglRectangle *dest_rect,
                              gdouble              std_dev_x,
                              gdouble              std_dev_y)
{
  if (!metal_initialized)
    return FALSE;

  @autoreleasepool {
    id<MTLTexture> input_tex = buffer_to_metal_texture (src, src_rect, metal_device);
    if (!input_tex)
      return FALSE;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                     width:dest_rect->width
                                    height:dest_rect->height
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> output_tex = [metal_device newTextureWithDescriptor:desc];

    if (!output_tex)
      return FALSE;

    /* Use Metal Performance Shaders for high-quality Gaussian blur */
    MPSImageGaussianBlur *blur = [[MPSImageGaussianBlur alloc]
        initWithDevice:metal_device sigma:std_dev_x];

    id<MTLCommandBuffer> cmd = [metal_queue commandBuffer];
    [blur encodeToCommandBuffer:cmd sourceTexture:input_tex destinationTexture:output_tex];
    [cmd commit];
    [cmd waitUntilCompleted];

    metal_texture_to_buffer (output_tex, dest, dest_rect);

    return TRUE;
  }
}


/* Desaturate */
gboolean
gimp_gegl_metal_desaturate (GeglBuffer          *src,
                           const GeglRectangle *src_rect,
                           GeglBuffer          *dest,
                           const GeglRectangle *dest_rect)
{
  if (!metal_initialized)
    return FALSE;

  @autoreleasepool {
    id<MTLTexture> input_tex = buffer_to_metal_texture (src, src_rect, metal_device);
    if (!input_tex)
      return FALSE;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                     width:dest_rect->width
                                    height:dest_rect->height
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> output_tex = [metal_device newTextureWithDescriptor:desc];

    if (!output_tex)
      return FALSE;

    id<MTLFunction> function = [metal_library newFunctionWithName:@"gimp_desaturate_shader"];
    if (!function)
      return FALSE;

    NSError *error = nil;
    id<MTLComputePipelineState> pipeline =
        [metal_device newComputePipelineStateWithFunction:function error:&error];

    if (error || !pipeline)
      return FALSE;

    id<MTLCommandBuffer> cmd = [metal_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [cmd computeCommandEncoder];

    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:input_tex atIndex:0];
    [encoder setTexture:output_tex atIndex:1];

    MTLSize threads = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
        (dest_rect->width + 15) / 16,
        (dest_rect->height + 15) / 16,
        1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threads];
    [encoder endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];

    metal_texture_to_buffer (output_tex, dest, dest_rect);

    return TRUE;
  }
}


/* Edge detection (Sobel) */
gboolean
gimp_gegl_metal_edge_sobel (GeglBuffer          *src,
                           const GeglRectangle *src_rect,
                           GeglBuffer          *dest,
                           const GeglRectangle *dest_rect)
{
  if (!metal_initialized)
    return FALSE;

  @autoreleasepool {
    id<MTLTexture> input_tex = buffer_to_metal_texture (src, src_rect, metal_device);
    if (!input_tex)
      return FALSE;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                     width:dest_rect->width
                                    height:dest_rect->height
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> output_tex = [metal_device newTextureWithDescriptor:desc];

    if (!output_tex)
      return FALSE;

    /* Use MPS Sobel filter */
    MPSImageSobel *sobel = [[MPSImageSobel alloc] initWithDevice:metal_device];

    id<MTLCommandBuffer> cmd = [metal_queue commandBuffer];
    [sobel encodeToCommandBuffer:cmd sourceTexture:input_tex destinationTexture:output_tex];
    [cmd commit];
    [cmd waitUntilCompleted];

    metal_texture_to_buffer (output_tex, dest, dest_rect);

    return TRUE;
  }
}


/* Sharpen */
gboolean
gimp_gegl_metal_sharpen (GeglBuffer          *src,
                        const GeglRectangle *src_rect,
                        GeglBuffer          *dest,
                        const GeglRectangle *dest_rect,
                        gfloat               amount)
{
  if (!metal_initialized)
    return FALSE;

  @autoreleasepool {
    id<MTLTexture> input_tex = buffer_to_metal_texture (src, src_rect, metal_device);
    if (!input_tex)
      return FALSE;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                     width:dest_rect->width
                                    height:dest_rect->height
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> output_tex = [metal_device newTextureWithDescriptor:desc];

    if (!output_tex)
      return FALSE;

    id<MTLFunction> function = [metal_library newFunctionWithName:@"gimp_sharpen_shader"];
    if (!function)
      return FALSE;

    NSError *error = nil;
    id<MTLComputePipelineState> pipeline =
        [metal_device newComputePipelineStateWithFunction:function error:&error];

    if (error || !pipeline)
      return FALSE;

    id<MTLCommandBuffer> cmd = [metal_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [cmd computeCommandEncoder];

    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:input_tex atIndex:0];
    [encoder setTexture:output_tex atIndex:1];
    [encoder setBytes:&amount length:sizeof(amount) atIndex:0];

    MTLSize threads = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
        (dest_rect->width + 15) / 16,
        (dest_rect->height + 15) / 16,
        1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threads];
    [encoder endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];

    metal_texture_to_buffer (output_tex, dest, dest_rect);

    return TRUE;
  }
}


/* Display rendering with Metal GPU - for canvas rendering to byte buffer */
gboolean
gimp_gegl_metal_render_to_buffer (GeglBuffer          *src,
                                  const GeglRectangle *src_rect,
                                  const Babl          *format,
                                  guchar              *dest_data,
                                  gint                 dest_stride)
{
  if (!metal_initialized)
    return FALSE;

  @autoreleasepool {
    /* Convert to Metal texture */
    id<MTLTexture> input_tex = buffer_to_metal_texture (src, src_rect, metal_device);
    if (!input_tex)
      return FALSE;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                     width:src_rect->width
                                    height:src_rect->height
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> output_tex = [metal_device newTextureWithDescriptor:desc];

    if (!output_tex)
      return FALSE;

    /* Get display render shader */
    id<MTLFunction> function = [metal_library newFunctionWithName:@"gimp_display_render_shader"];
    if (!function)
      return FALSE;

    NSError *error = nil;
    id<MTLComputePipelineState> pipeline =
        [metal_device newComputePipelineStateWithFunction:function error:&error];

    if (error || !pipeline)
      return FALSE;

    id<MTLCommandBuffer> cmd = [metal_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [cmd computeCommandEncoder];

    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:input_tex atIndex:0];
    [encoder setTexture:output_tex atIndex:1];

    MTLSize threads = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
        (src_rect->width + 15) / 16,
        (src_rect->height + 15) / 16,
        1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threads];
    [encoder endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];

    /* Copy from texture to byte buffer */
    [output_tex getBytes:dest_data
             bytesPerRow:dest_stride
              fromRegion:MTLRegionMake2D(0, 0, src_rect->width, src_rect->height)
             mipmapLevel:0];

    g_message ("🚀 Metal: Display render %dx%d (GPU accelerated)",
               src_rect->width, src_rect->height);

    return TRUE;
  }
}


/* Unsharp Mask using MPS - high-quality edge enhancement */
gboolean
gimp_gegl_metal_unsharp_mask (GeglBuffer          *src,
                              const GeglRectangle *src_rect,
                              GeglBuffer          *dest,
                              const GeglRectangle *dest_rect,
                              gdouble              std_dev,
                              gdouble              scale)
{
  if (!metal_initialized)
    return FALSE;

  @autoreleasepool {
    id<MTLTexture> input_tex = buffer_to_metal_texture (src, src_rect, metal_device);
    if (!input_tex)
      return FALSE;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                     width:dest_rect->width
                                    height:dest_rect->height
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

    id<MTLTexture> blur_tex = [metal_device newTextureWithDescriptor:desc];
    if (!blur_tex)
      return FALSE;

    id<MTLTexture> output_tex = [metal_device newTextureWithDescriptor:desc];
    if (!output_tex)
      return FALSE;

    id<MTLCommandBuffer> cmd = [metal_queue commandBuffer];

    MPSImageGaussianBlur *blur = [[MPSImageGaussianBlur alloc]
        initWithDevice:metal_device sigma:std_dev];
    [blur encodeToCommandBuffer:cmd sourceTexture:input_tex destinationTexture:blur_tex];

    id<MTLComputeCommandEncoder> encoder = [cmd computeCommandEncoder];

    id<MTLFunction> function = [metal_library newFunctionWithName:@"gimp_sharpen_shader"];
    if (!function)
      return FALSE;

    NSError *error = nil;
    id<MTLComputePipelineState> pipeline =
        [metal_device newComputePipelineStateWithFunction:function error:&error];

    if (error || !pipeline)
      return FALSE;

    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:input_tex atIndex:0];
    [encoder setTexture:output_tex atIndex:1];

    float amount = (float)scale;
    [encoder setBytes:&amount length:sizeof(float) atIndex:0];

    MTLSize threads = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
        (dest_rect->width + 15) / 16,
        (dest_rect->height + 15) / 16,
        1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threads];
    [encoder endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];

    metal_texture_to_buffer (output_tex, dest, dest_rect);

    return TRUE;
  }
}


/* Hue-Saturation adjustment with Metal GPU */
gboolean
gimp_gegl_metal_hue_saturation (GeglBuffer          *src,
                                const GeglRectangle *src_rect,
                                GeglBuffer          *dest,
                                const GeglRectangle *dest_rect,
                                gdouble              hue,
                                gdouble              saturation,
                                gdouble              lightness)
{
  if (!metal_initialized)
    return FALSE;

  @autoreleasepool {
    id<MTLTexture> input_tex = buffer_to_metal_texture (src, src_rect, metal_device);
    if (!input_tex)
      return FALSE;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                     width:dest_rect->width
                                    height:dest_rect->height
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> output_tex = [metal_device newTextureWithDescriptor:desc];

    if (!output_tex)
      return FALSE;

    id<MTLFunction> function = [metal_library newFunctionWithName:@"gimp_hue_saturation_shader"];
    if (!function)
      return FALSE;

    NSError *error = nil;
    id<MTLComputePipelineState> pipeline =
        [metal_device newComputePipelineStateWithFunction:function error:&error];

    if (error || !pipeline)
      return FALSE;

    id<MTLCommandBuffer> cmd = [metal_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [cmd computeCommandEncoder];

    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:input_tex atIndex:0];
    [encoder setTexture:output_tex atIndex:1];

    float hue_f = (float)hue;
    float sat_f = (float)saturation;
    float light_f = (float)lightness;
    [encoder setBytes:&hue_f length:sizeof(float) atIndex:0];
    [encoder setBytes:&sat_f length:sizeof(float) atIndex:1];
    [encoder setBytes:&light_f length:sizeof(float) atIndex:2];

    MTLSize threads = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
        (dest_rect->width + 15) / 16,
        (dest_rect->height + 15) / 16,
        1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threads];
    [encoder endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];

    metal_texture_to_buffer (output_tex, dest, dest_rect);

    g_message ("🚀 Metal: Hue-Saturation %dx%d h=%.2f s=%.2f l=%.2f (GPU)",
               dest_rect->width, dest_rect->height, hue, saturation, lightness);

    return TRUE;
  }
}


/* Color Temperature adjustment with Metal GPU */
gboolean
gimp_gegl_metal_color_temperature (GeglBuffer          *src,
                                   const GeglRectangle *src_rect,
                                   GeglBuffer          *dest,
                                   const GeglRectangle *dest_rect,
                                   gdouble              temperature)
{
  if (!metal_initialized)
    return FALSE;

  @autoreleasepool {
    id<MTLTexture> input_tex = buffer_to_metal_texture (src, src_rect, metal_device);
    if (!input_tex)
      return FALSE;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                     width:dest_rect->width
                                    height:dest_rect->height
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> output_tex = [metal_device newTextureWithDescriptor:desc];

    if (!output_tex)
      return FALSE;

    id<MTLFunction> function = [metal_library newFunctionWithName:@"gimp_color_temperature_shader"];
    if (!function)
      return FALSE;

    NSError *error = nil;
    id<MTLComputePipelineState> pipeline =
        [metal_device newComputePipelineStateWithFunction:function error:&error];

    if (error || !pipeline)
      return FALSE;

    id<MTLCommandBuffer> cmd = [metal_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [cmd computeCommandEncoder];

    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:input_tex atIndex:0];
    [encoder setTexture:output_tex atIndex:1];

    float temp_f = (float)temperature;
    [encoder setBytes:&temp_f length:sizeof(float) atIndex:0];

    MTLSize threads = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
        (dest_rect->width + 15) / 16,
        (dest_rect->height + 15) / 16,
        1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threads];
    [encoder endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];

    metal_texture_to_buffer (output_tex, dest, dest_rect);

    g_message ("🚀 Metal: Color Temperature %dx%d temp=%.2f (GPU)",
               dest_rect->width, dest_rect->height, temperature);

    return TRUE;
  }
}


/* Scale with bilinear filtering - high quality GPU resize */
gboolean
gimp_gegl_metal_scale (GeglBuffer          *src,
                       const GeglRectangle *src_rect,
                       GeglBuffer          *dest,
                       const GeglRectangle *dest_rect)
{
  if (!metal_initialized)
    return FALSE;

  @autoreleasepool {
    id<MTLTexture> input_tex = buffer_to_metal_texture (src, src_rect, metal_device);
    if (!input_tex)
      return FALSE;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                     width:dest_rect->width
                                    height:dest_rect->height
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> output_tex = [metal_device newTextureWithDescriptor:desc];

    if (!output_tex)
      return FALSE;

    id<MTLFunction> function = [metal_library newFunctionWithName:@"gimp_scale_bilinear_shader"];
    if (!function)
      return FALSE;

    NSError *error = nil;
    id<MTLComputePipelineState> pipeline =
        [metal_device newComputePipelineStateWithFunction:function error:&error];

    if (error || !pipeline)
      return FALSE;

    id<MTLCommandBuffer> cmd = [metal_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [cmd computeCommandEncoder];

    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:input_tex atIndex:0];
    [encoder setTexture:output_tex atIndex:1];

    float scale_x = (float)dest_rect->width / (float)src_rect->width;
    float scale_y = (float)dest_rect->height / (float)src_rect->height;
    float scale_factor[2] = {scale_x, scale_y};
    [encoder setBytes:&scale_factor length:sizeof(float) * 2 atIndex:0];

    MTLSize threads = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
        (dest_rect->width + 15) / 16,
        (dest_rect->height + 15) / 16,
        1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threads];
    [encoder endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];

    metal_texture_to_buffer (output_tex, dest, dest_rect);

    g_message ("🚀 Metal: Scale %dx%d → %dx%d (GPU bilinear)",
               src_rect->width, src_rect->height,
               dest_rect->width, dest_rect->height);

    return TRUE;
  }
}


/* Rotate with arbitrary angle - GPU texture sampling */
gboolean
gimp_gegl_metal_rotate (GeglBuffer          *src,
                        const GeglRectangle *src_rect,
                        GeglBuffer          *dest,
                        const GeglRectangle *dest_rect,
                        gdouble              angle)
{
  if (!metal_initialized)
    return FALSE;

  @autoreleasepool {
    id<MTLTexture> input_tex = buffer_to_metal_texture (src, src_rect, metal_device);
    if (!input_tex)
      return FALSE;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                     width:dest_rect->width
                                    height:dest_rect->height
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> output_tex = [metal_device newTextureWithDescriptor:desc];

    if (!output_tex)
      return FALSE;

    id<MTLFunction> function = [metal_library newFunctionWithName:@"gimp_rotate_shader"];
    if (!function)
      return FALSE;

    NSError *error = nil;
    id<MTLComputePipelineState> pipeline =
        [metal_device newComputePipelineStateWithFunction:function error:&error];

    if (error || !pipeline)
      return FALSE;

    id<MTLCommandBuffer> cmd = [metal_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [cmd computeCommandEncoder];

    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:input_tex atIndex:0];
    [encoder setTexture:output_tex atIndex:1];

    float angle_f = (float)angle;
    float center[2] = {0.5f, 0.5f};
    [encoder setBytes:&angle_f length:sizeof(float) atIndex:0];
    [encoder setBytes:&center length:sizeof(float) * 2 atIndex:1];

    MTLSize threads = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(
        (dest_rect->width + 15) / 16,
        (dest_rect->height + 15) / 16,
        1
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threads];
    [encoder endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];

    metal_texture_to_buffer (output_tex, dest, dest_rect);

    g_message ("🚀 Metal: Rotate %dx%d angle=%.1f° (GPU)",
               dest_rect->width, dest_rect->height, angle * 180.0 / M_PI);

    return TRUE;
  }
}


#endif /* HAVE_METAL */
