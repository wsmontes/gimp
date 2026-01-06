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


G_END_DECLS

#endif /* HAVE_METAL */
