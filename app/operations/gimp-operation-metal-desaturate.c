/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-operation-metal-desaturate.c
 * Metal-accelerated desaturate operation
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

#include <gegl.h>

#include "../gegl/gimp-gegl-loops-metal.h"
#include "gimp-operation-metal-desaturate.h"


static void     gimp_operation_metal_desaturate_prepare (GeglOperation       *operation);
static gboolean gimp_operation_metal_desaturate_process (GeglOperation       *operation,
                                                         GeglBuffer          *input,
                                                         GeglBuffer          *output,
                                                         const GeglRectangle *result,
                                                         gint                 level);


G_DEFINE_TYPE (GimpOperationMetalDesaturate, gimp_operation_metal_desaturate,
               GEGL_TYPE_OPERATION_FILTER)

#define parent_class gimp_operation_metal_desaturate_parent_class


static void
gimp_operation_metal_desaturate_class_init (GimpOperationMetalDesaturateClass *klass)
{
  GeglOperationClass       *operation_class = GEGL_OPERATION_CLASS (klass);
  GeglOperationFilterClass *filter_class    = GEGL_OPERATION_FILTER_CLASS (klass);

  operation_class->prepare = gimp_operation_metal_desaturate_prepare;
  filter_class->process    = gimp_operation_metal_desaturate_process;

  gegl_operation_class_set_keys (operation_class,
                                  "name",        "gimp:metal-desaturate",
                                  "categories",  "color",
                                  "description", "Desaturate using Metal GPU acceleration",
                                  NULL);
}

static void
gimp_operation_metal_desaturate_init (GimpOperationMetalDesaturate *self)
{
}

static void
gimp_operation_metal_desaturate_prepare (GeglOperation *operation)
{
  const Babl *format = babl_format ("RGBA float");

  gegl_operation_set_format (operation, "input",  format);
  gegl_operation_set_format (operation, "output", format);
}

static gboolean
gimp_operation_metal_desaturate_process (GeglOperation       *operation,
                                        GeglBuffer          *input,
                                        GeglBuffer          *output,
                                        const GeglRectangle *result,
                                        gint                 level)
{
#ifdef HAVE_METAL
  /* Try Metal acceleration first */
  if (gimp_gegl_metal_desaturate (input, result, output, result))
    return TRUE;
#endif

  /* Fallback to CPU: simple luminance-based desaturation */
  {
    GeglBufferIterator *iter;

    iter = gegl_buffer_iterator_new (input, result, level,
                                     babl_format ("RGBA float"),
                                     GEGL_ACCESS_READ, GEGL_ABYSS_NONE, 2);

    gegl_buffer_iterator_add (iter, output, result, level,
                             babl_format ("RGBA float"),
                             GEGL_ACCESS_WRITE, GEGL_ABYSS_NONE);

    while (gegl_buffer_iterator_next (iter))
      {
        gfloat *in  = iter->items[0].data;
        gfloat *out = iter->items[1].data;
        glong   n   = iter->length;

        while (n--)
          {
            gfloat luminance = in[0] * 0.21f + in[1] * 0.72f + in[2] * 0.07f;

            out[0] = luminance;
            out[1] = luminance;
            out[2] = luminance;
            out[3] = in[3];

            in  += 4;
            out += 4;
          }
      }
  }

  return TRUE;
}
