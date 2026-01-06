/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 1995 Spencer Kimball and Peter Mattis
 *
 * gimp-gegl-loops-metal.h
 * Metal GPU acceleration backend for GIMP
 * Copyright (C) 2026 GIMP Metal Development Team
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 */

#ifndef __GIMP_GEGL_LOOPS_METAL_H__
#define __GIMP_GEGL_LOOPS_METAL_H__

#include <gegl.h>

G_BEGIN_DECLS

/* Initialize Metal backend */
void        gimp_gegl_init_metal                    (void);
void        gimp_gegl_exit_metal                    (void);

/* Query Metal capabilities */
gboolean    gimp_gegl_metal_is_available            (void);
const char* gimp_gegl_metal_get_device_name         (void);

/* Metal-accelerated operations */
void        gimp_gegl_metal_blur_gaussian           (GeglBuffer          *src_buffer,
                                                     const GeglRectangle *src_rect,
                                                     GeglBuffer          *dest_buffer,
                                                     const GeglRectangle *dest_rect,
                                                     gdouble              std_dev_x,
                                                     gdouble              std_dev_y);

void        gimp_gegl_metal_brightness_contrast     (GeglBuffer          *src_buffer,
                                                     const GeglRectangle *src_rect,
                                                     GeglBuffer          *dest_buffer,
                                                     const GeglRectangle *dest_rect,
                                                     gdouble              brightness,
                                                     gdouble              contrast);

void        gimp_gegl_metal_desaturate              (GeglBuffer          *src_buffer,
                                                     const GeglRectangle *src_rect,
                                                     GeglBuffer          *dest_buffer,
                                                     const GeglRectangle *dest_rect);

void        gimp_gegl_metal_invert                  (GeglBuffer          *src_buffer,
                                                     const GeglRectangle *src_rect,
                                                     GeglBuffer          *dest_buffer,
                                                     const GeglRectangle *dest_rect);

void        gimp_gegl_metal_hue_saturation          (GeglBuffer          *src_buffer,
                                                     const GeglRectangle *src_rect,
                                                     GeglBuffer          *dest_buffer,
                                                     const GeglRectangle *dest_rect,
                                                     gdouble              hue_offset,
                                                     gdouble              saturation,
                                                     gdouble              lightness);

void        gimp_gegl_metal_convolve                (GeglBuffer          *src_buffer,
                                                     const GeglRectangle *src_rect,
                                                     GeglBuffer          *dest_buffer,
                                                     const GeglRectangle *dest_rect,
                                                     const gfloat        *kernel,
                                                     gint                 kernel_size,
                                                     gdouble              divisor);

void        gimp_gegl_metal_threshold               (GeglBuffer          *src_buffer,
                                                     const GeglRectangle *src_rect,
                                                     GeglBuffer          *dest_buffer,
                                                     const GeglRectangle *dest_rect,
                                                     gdouble              lower,
                                                     gdouble              upper);

G_END_DECLS

#endif /* __GIMP_GEGL_LOOPS_METAL_H__ */
