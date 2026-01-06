/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 1995 Spencer Kimball and Peter Mattis
 *
 * gimp-gegl-loops-metal.m
 * Metal GPU acceleration backend for GIMP
 * Copyright (C) 2026 GIMP Metal Development Team
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 */

#include "config.h"

#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

#include <gegl.h>
#include <glib.h>

#include "gimp-gegl-loops-metal.h"
#include "gimp-gegl-metal.h"

/* Global Metal context */
static GimpMetalContext *metal_ctx = NULL;

void
gimp_gegl_init_metal (void)
{
    if (metal_ctx != NULL)
        return;

    metal_ctx = gimp_metal_context_new ();

    if (metal_ctx)
    {
        g_message ("Metal backend initialized successfully");
        g_message ("GPU: %s", gimp_metal_context_get_name (metal_ctx));
        g_message ("Metal acceleration: ENABLED");
    }
    else
    {
        g_warning ("Failed to initialize Metal backend");
    }
}

void
gimp_gegl_exit_metal (void)
{
    if (metal_ctx)
    {
        gimp_metal_context_free (metal_ctx);
        metal_ctx = NULL;
    }
}

gboolean
gimp_gegl_metal_is_available (void)
{
    return (metal_ctx != NULL);
}

const char*
gimp_gegl_metal_get_device_name (void)
{
    if (metal_ctx)
        return gimp_metal_context_get_name (metal_ctx);

    return "No Metal device";
}

void
gimp_gegl_metal_blur_gaussian (GeglBuffer          *src_buffer,
                               const GeglRectangle *src_rect,
                               GeglBuffer          *dest_buffer,
                               const GeglRectangle *dest_rect,
                               gdouble              std_dev_x,
                               gdouble              std_dev_y)
{
    if (!metal_ctx)
    {
        g_warning ("Metal not initialized, falling back to CPU");
        return;
    }

    GimpMetalBuffer *src_metal = gimp_metal_buffer_new_from_gegl (metal_ctx, src_buffer, src_rect);
    GimpMetalBuffer *dst_metal = gimp_metal_buffer_new (metal_ctx,
                                                         dest_rect->width,
                                                         dest_rect->height);

    if (src_metal && dst_metal)
    {
        gdouble sigma = (std_dev_x + std_dev_y) / 2.0;
        gimp_metal_blur_gaussian (metal_ctx, src_metal, dst_metal, sigma);
        gimp_metal_buffer_copy_to_gegl (dst_metal, dest_buffer, dest_rect);

        g_debug ("Metal Gaussian Blur: %.1f sigma, %dx%d",
                 sigma, dest_rect->width, dest_rect->height);
    }

    if (src_metal) gimp_metal_buffer_free (src_metal);
    if (dst_metal) gimp_metal_buffer_free (dst_metal);
}

void
gimp_gegl_metal_brightness_contrast (GeglBuffer          *src_buffer,
                                     const GeglRectangle *src_rect,
                                     GeglBuffer          *dest_buffer,
                                     const GeglRectangle *dest_rect,
                                     gdouble              brightness,
                                     gdouble              contrast)
{
    if (!metal_ctx)
        return;

    GimpMetalBuffer *src_metal = gimp_metal_buffer_new_from_gegl (metal_ctx, src_buffer, src_rect);
    GimpMetalBuffer *dst_metal = gimp_metal_buffer_new (metal_ctx,
                                                         dest_rect->width,
                                                         dest_rect->height);

    if (src_metal && dst_metal)
    {
        gimp_metal_brightness_contrast (metal_ctx, src_metal, dst_metal,
                                        brightness, contrast);
        gimp_metal_buffer_copy_to_gegl (dst_metal, dest_buffer, dest_rect);

        g_debug ("Metal Brightness/Contrast: b=%.2f c=%.2f", brightness, contrast);
    }

    if (src_metal) gimp_metal_buffer_free (src_metal);
    if (dst_metal) gimp_metal_buffer_free (dst_metal);
}

void
gimp_gegl_metal_desaturate (GeglBuffer          *src_buffer,
                            const GeglRectangle *src_rect,
                            GeglBuffer          *dest_buffer,
                            const GeglRectangle *dest_rect)
{
    if (!metal_ctx)
        return;

    GimpMetalBuffer *src_metal = gimp_metal_buffer_new_from_gegl (metal_ctx, src_buffer, src_rect);
    GimpMetalBuffer *dst_metal = gimp_metal_buffer_new (metal_ctx,
                                                         dest_rect->width,
                                                         dest_rect->height);

    if (src_metal && dst_metal)
    {
        gimp_metal_desaturate (metal_ctx, src_metal, dst_metal);
        gimp_metal_buffer_copy_to_gegl (dst_metal, dest_buffer, dest_rect);

        g_debug ("Metal Desaturate: %dx%d", dest_rect->width, dest_rect->height);
    }

    if (src_metal) gimp_metal_buffer_free (src_metal);
    if (dst_metal) gimp_metal_buffer_free (dst_metal);
}

void
gimp_gegl_metal_invert (GeglBuffer          *src_buffer,
                        const GeglRectangle *src_rect,
                        GeglBuffer          *dest_buffer,
                        const GeglRectangle *dest_rect)
{
    if (!metal_ctx)
        return;

    GimpMetalBuffer *src_metal = gimp_metal_buffer_new_from_gegl (metal_ctx, src_buffer, src_rect);
    GimpMetalBuffer *dst_metal = gimp_metal_buffer_new (metal_ctx,
                                                         dest_rect->width,
                                                         dest_rect->height);

    if (src_metal && dst_metal)
    {
        gimp_metal_invert (metal_ctx, src_metal, dst_metal);
        gimp_metal_buffer_copy_to_gegl (dst_metal, dest_buffer, dest_rect);

        g_debug ("Metal Invert: %dx%d", dest_rect->width, dest_rect->height);
    }

    if (src_metal) gimp_metal_buffer_free (src_metal);
    if (dst_metal) gimp_metal_buffer_free (dst_metal);
}

void
gimp_gegl_metal_hue_saturation (GeglBuffer          *src_buffer,
                                const GeglRectangle *src_rect,
                                GeglBuffer          *dest_buffer,
                                const GeglRectangle *dest_rect,
                                gdouble              hue_offset,
                                gdouble              saturation,
                                gdouble              lightness)
{
    if (!metal_ctx)
        return;

    GimpMetalBuffer *src_metal = gimp_metal_buffer_new_from_gegl (metal_ctx, src_buffer, src_rect);
    GimpMetalBuffer *dst_metal = gimp_metal_buffer_new (metal_ctx,
                                                         dest_rect->width,
                                                         dest_rect->height);

    if (src_metal && dst_metal)
    {
        gimp_metal_hue_saturation (metal_ctx, src_metal, dst_metal,
                                   hue_offset, saturation, lightness);
        gimp_metal_buffer_copy_to_gegl (dst_metal, dest_buffer, dest_rect);

        g_debug ("Metal Hue/Saturation: h=%.2f s=%.2f l=%.2f",
                 hue_offset, saturation, lightness);
    }

    if (src_metal) gimp_metal_buffer_free (src_metal);
    if (dst_metal) gimp_metal_buffer_free (dst_metal);
}

void
gimp_gegl_metal_convolve (GeglBuffer          *src_buffer,
                          const GeglRectangle *src_rect,
                          GeglBuffer          *dest_buffer,
                          const GeglRectangle *dest_rect,
                          const gfloat        *kernel,
                          gint                 kernel_size,
                          gdouble              divisor)
{
    if (!metal_ctx || kernel_size != 3)
        return;

    GimpMetalBuffer *src_metal = gimp_metal_buffer_new_from_gegl (metal_ctx, src_buffer, src_rect);
    GimpMetalBuffer *dst_metal = gimp_metal_buffer_new (metal_ctx,
                                                         dest_rect->width,
                                                         dest_rect->height);

    if (src_metal && dst_metal)
    {
        gimp_metal_convolve_3x3 (metal_ctx, src_metal, dst_metal, kernel);
        gimp_metal_buffer_copy_to_gegl (dst_metal, dest_buffer, dest_rect);

        g_debug ("Metal Convolve 3x3: %dx%d", dest_rect->width, dest_rect->height);
    }

    if (src_metal) gimp_metal_buffer_free (src_metal);
    if (dst_metal) gimp_metal_buffer_free (dst_metal);
}

void
gimp_gegl_metal_threshold (GeglBuffer          *src_buffer,
                           const GeglRectangle *src_rect,
                           GeglBuffer          *dest_buffer,
                           const GeglRectangle *dest_rect,
                           gdouble              lower,
                           gdouble              upper)
{
    if (!metal_ctx)
        return;

    GimpMetalBuffer *src_metal = gimp_metal_buffer_new_from_gegl (metal_ctx, src_buffer, src_rect);
    GimpMetalBuffer *dst_metal = gimp_metal_buffer_new (metal_ctx,
                                                         dest_rect->width,
                                                         dest_rect->height);

    if (src_metal && dst_metal)
    {
        gimp_metal_threshold (metal_ctx, src_metal, dst_metal, lower, upper);
        gimp_metal_buffer_copy_to_gegl (dst_metal, dest_buffer, dest_rect);

        g_debug ("Metal Threshold: %.2f-%.2f", lower, upper);
    }

    if (src_metal) gimp_metal_buffer_free (src_metal);
    if (dst_metal) gimp_metal_buffer_free (dst_metal);
}
