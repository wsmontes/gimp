/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-gegl-loops-metal.h
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

#ifndef __GIMP_GEGL_LOOPS_METAL_H__
#define __GIMP_GEGL_LOOPS_METAL_H__


#ifdef HAVE_METAL

/* Metal context management */
gboolean   gimp_gegl_metal_init              (void);
void       gimp_gegl_metal_shutdown          (void);
gboolean   gimp_gegl_metal_is_available      (void);

/* Metal-accelerated operations */
gboolean   gimp_gegl_metal_invert            (GeglBuffer          *src,
                                              const GeglRectangle *src_rect,
                                              GeglBuffer          *dest,
                                              const GeglRectangle *dest_rect);

gboolean   gimp_gegl_metal_brightness_contrast (GeglBuffer          *src,
                                                 const GeglRectangle *src_rect,
                                                 GeglBuffer          *dest,
                                                 const GeglRectangle *dest_rect,
                                                 gfloat               brightness,
                                                 gfloat               contrast);

gboolean   gimp_gegl_metal_blur_gaussian     (GeglBuffer          *src,
                                              const GeglRectangle *src_rect,
                                              GeglBuffer          *dest,
                                              const GeglRectangle *dest_rect,
                                              gdouble              std_dev_x,
                                              gdouble              std_dev_y);

gboolean   gimp_gegl_metal_desaturate        (GeglBuffer          *src,
                                              const GeglRectangle *src_rect,
                                              GeglBuffer          *dest,
                                              const GeglRectangle *dest_rect);

gboolean   gimp_gegl_metal_edge_sobel        (GeglBuffer          *src,
                                              const GeglRectangle *src_rect,
                                              GeglBuffer          *dest,
                                              const GeglRectangle *dest_rect);

gboolean   gimp_gegl_metal_sharpen           (GeglBuffer          *src,
                                              const GeglRectangle *src_rect,
                                              GeglBuffer          *dest,
                                              const GeglRectangle *dest_rect,
                                              gfloat               amount);

#endif /* HAVE_METAL */


#endif /* __GIMP_GEGL_LOOPS_METAL_H__ */
