/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-operation-metal-edge-sobel.c
 * Metal-accelerated Sobel edge detection operation
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
#include "gimp-operation-metal-edge-sobel.h"


static void     gimp_operation_metal_edge_sobel_prepare (GeglOperation       *operation);
static gboolean gimp_operation_metal_edge_sobel_process (GeglOperation       *operation,
                                                         GeglBuffer          *input,
                                                         GeglBuffer          *output,
                                                         const GeglRectangle *result,
                                                         gint                 level);


G_DEFINE_TYPE (GimpOperationMetalEdgeSobel, gimp_operation_metal_edge_sobel,
               GEGL_TYPE_OPERATION_FILTER)

#define parent_class gimp_operation_metal_edge_sobel_parent_class


static void
gimp_operation_metal_edge_sobel_class_init (GimpOperationMetalEdgeSobelClass *klass)
{
  GeglOperationClass       *operation_class = GEGL_OPERATION_CLASS (klass);
  GeglOperationFilterClass *filter_class    = GEGL_OPERATION_FILTER_CLASS (klass);

  operation_class->prepare = gimp_operation_metal_edge_sobel_prepare;
  filter_class->process    = gimp_operation_metal_edge_sobel_process;

  gegl_operation_class_set_keys (operation_class,
                                  "name",        "gimp:metal-edge-sobel",
                                  "categories",  "edge-detect",
                                  "description", "Sobel edge detection using Metal GPU acceleration",
                                  NULL);
}

static void
gimp_operation_metal_edge_sobel_init (GimpOperationMetalEdgeSobel *self)
{
}

static void
gimp_operation_metal_edge_sobel_prepare (GeglOperation *operation)
{
  const Babl *format = babl_format ("RGBA float");

  gegl_operation_set_format (operation, "input",  format);
  gegl_operation_set_format (operation, "output", format);
}

static gboolean
gimp_operation_metal_edge_sobel_process (GeglOperation       *operation,
                                        GeglBuffer          *input,
                                        GeglBuffer          *output,
                                        const GeglRectangle *result,
                                        gint                 level)
{
#ifdef HAVE_METAL
  /* Try Metal acceleration first */
  if (gimp_gegl_metal_edge_sobel (input, result, output, result))
    return TRUE;
#endif

  /* Fallback: use GEGL's built-in edge-sobel */
  {
    GeglNode *gegl;
    GeglNode *input_node;
    GeglNode *sobel_node;
    GeglNode *output_node;

    gegl = gegl_node_new ();

    input_node = gegl_node_new_child (gegl,
                                      "operation", "gegl:buffer-source",
                                      "buffer",    input,
                                      NULL);

    sobel_node = gegl_node_new_child (gegl,
                                      "operation", "gegl:edge-sobel",
                                      NULL);

    output_node = gegl_node_new_child (gegl,
                                       "operation", "gegl:write-buffer",
                                       "buffer",    output,
                                       NULL);

    gegl_node_link_many (input_node, sobel_node, output_node, NULL);
    gegl_node_process (output_node);

    g_object_unref (gegl);
  }

  return TRUE;
}
