/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-gegl-loops-metal.h
 * Metal-accelerated versions of GEGL operations
 */

#pragma once

#ifdef HAVE_METAL

#include <gegl.h>

G_BEGIN_DECLS


void      gimp_gegl_init_metal             (void);
void      gimp_gegl_shutdown_metal         (void);

gboolean  gimp_gegl_metal_blur_gaussian    (GeglBuffer          *src_buffer,
                                            const GeglRectangle *src_rect,
                                            GeglBuffer          *dest_buffer,
                                            const GeglRectangle *dest_rect,
                                            gfloat               radius_x,
                                            gfloat               radius_y);

gboolean  gimp_gegl_metal_brightness_contrast (GeglBuffer          *src_buffer,
                                               const GeglRectangle *src_rect,
                                               GeglBuffer          *dest_buffer,
                                               const GeglRectangle *dest_rect,
                                               gfloat               brightness,
                                               gfloat               contrast);

gboolean  gimp_gegl_metal_desaturate       (GeglBuffer          *src_buffer,
                                            const GeglRectangle *src_rect,
                                            GeglBuffer          *dest_buffer,
                                            const GeglRectangle *dest_rect);

gboolean  gimp_gegl_metal_invert           (GeglBuffer          *src_buffer,
                                            const GeglRectangle *src_rect,
                                            GeglBuffer          *dest_buffer,
                                            const GeglRectangle *dest_rect);

gboolean  gimp_gegl_metal_hue_saturation   (GeglBuffer          *src_buffer,
                                            const GeglRectangle *src_rect,
                                            GeglBuffer          *dest_buffer,
                                            const GeglRectangle *dest_rect,
                                            gfloat               hue_offset,
                                            gfloat               saturation,
                                            gfloat               lightness);


G_END_DECLS

#endif /* HAVE_METAL */
