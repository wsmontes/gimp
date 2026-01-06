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
    NSString *shader_path = @"/opt/homebrew/share/gimp/3.2/metal/shaders.metallib";

    if ([[NSFileManager defaultManager] fileExistsAtPath:shader_path])
      {
        NSURL *library_url = [NSURL fileURLWithPath:shader_path];
        metal_library = [metal_device newLibraryWithURL:library_url error:&error];

        if (error)
          {
            g_message ("Metal: Failed to load precompiled library, compiling at runtime");
            error = nil;
          }
      }

    if (!metal_library)
      {
        /* Fallback: compile shaders at runtime */
        NSString *source_path = @"/opt/homebrew/share/gimp/3.2/metal/shaders.metal";

        if ([[NSFileManager defaultManager] fileExistsAtPath:source_path])
          {
            NSString *source = [NSString stringWithContentsOfFile:source_path
                                                          encoding:NSUTF8StringEncoding
                                                             error:&error];

            if (!error)
              {
                metal_library = [metal_device newLibraryWithSource:source
                                                            options:nil
                                                              error:&error];

                if (metal_library)
                  g_message ("Metal: ✅ Compiled shaders at runtime");
              }
          }

        if (error || !metal_library)
          {
            g_warning ("Metal: Failed to load/compile shaders");
            metal_queue = nil;
            metal_device = nil;
            return FALSE;
          }
      }

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

#endif /* HAVE_METAL */
