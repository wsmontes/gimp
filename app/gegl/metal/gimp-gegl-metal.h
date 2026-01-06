/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-gegl-metal.h
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

#pragma once

#ifdef HAVE_METAL

#include <gegl.h>

G_BEGIN_DECLS


/**
 * GimpMetalContext:
 *
 * Opaque structure holding Metal device and command queue
 */
typedef struct _GimpMetalContext GimpMetalContext;


/**
 * GimpMetalBuffer:
 *
 * GPU buffer wrapper for Metal textures/buffers
 */
typedef struct _GimpMetalBuffer GimpMetalBuffer;


/* Context Management */
GimpMetalContext * gimp_metal_context_new              (void);
void               gimp_metal_context_free             (GimpMetalContext *context);
gboolean           gimp_metal_context_is_available     (void);
const gchar      * gimp_metal_context_get_name         (GimpMetalContext *context);
const gchar      * gimp_metal_context_get_device_name  (GimpMetalContext *context);


/* Buffer Management */
GimpMetalBuffer  * gimp_metal_buffer_new               (GimpMetalContext  *context,
                                                        gint               width,
                                                        gint               height);
GimpMetalBuffer  * gimp_metal_buffer_new_from_gegl     (GimpMetalContext  *context,
                                                        GeglBuffer        *buffer,
                                                        const GeglRectangle *rect);
GeglBuffer       * gimp_metal_buffer_to_gegl           (GimpMetalBuffer   *metal_buffer,
                                                        const Babl        *format);
void               gimp_metal_buffer_copy_to_gegl      (GimpMetalBuffer   *metal_buffer,
                                                        GeglBuffer        *gegl_buffer,
                                                        const GeglRectangle *rect);
void               gimp_metal_buffer_free              (GimpMetalBuffer   *buffer);


/* Core Operations */
gboolean           gimp_metal_blur_gaussian            (GimpMetalContext    *context,
                                                        GimpMetalBuffer     *src,
                                                        GimpMetalBuffer     *dest,
                                                        gfloat               sigma);

gboolean           gimp_metal_brightness_contrast      (GimpMetalContext    *context,
                                                        GimpMetalBuffer     *src,
                                                        GimpMetalBuffer     *dest,
                                                        gfloat               brightness,
                                                        gfloat               contrast);

gboolean           gimp_metal_desaturate               (GimpMetalContext    *context,
                                                        GimpMetalBuffer     *src,
                                                        GimpMetalBuffer     *dest);

gboolean           gimp_metal_invert                   (GimpMetalContext    *context,
                                                        GimpMetalBuffer     *src,
                                                        GimpMetalBuffer     *dest);

gboolean           gimp_metal_hue_saturation           (GimpMetalContext    *context,
                                                        GimpMetalBuffer     *src,
                                                        GimpMetalBuffer     *dest,
                                                        gfloat               hue_offset,
                                                        gfloat               saturation,
                                                        gfloat               lightness);

gboolean           gimp_metal_convolve_3x3             (GimpMetalContext    *context,
                                                        GimpMetalBuffer     *src,
                                                        GimpMetalBuffer     *dest,
                                                        const gfloat        *kernel);

gboolean           gimp_metal_threshold                (GimpMetalContext    *context,
                                                        GimpMetalBuffer     *src,
                                                        GimpMetalBuffer     *dest,
                                                        gfloat               lower,
                                                        gfloat               upper);

gboolean           gimp_metal_brightness_contrast      (GimpMetalContext    *context,
                                                        GimpMetalBuffer     *src,
                                                        GimpMetalBuffer     *dest,
                                                        gfloat               brightness,
                                                        gfloat               contrast);

gboolean           gimp_metal_buffer_copy              (GimpMetalContext    *context,
                                                        GimpMetalBuffer     *src,
                                                        GimpMetalBuffer     *dest);


/* Integration with GEGL loops */
gboolean           gimp_gegl_loops_use_metal           (void);
void               gimp_gegl_loops_set_use_metal       (gboolean use_metal);


G_END_DECLS

#endif /* HAVE_METAL */
