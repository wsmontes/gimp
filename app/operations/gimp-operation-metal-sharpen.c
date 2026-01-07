/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-operation-metal-sharpen.c
 * Metal-accelerated sharpen operation
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
#include "gimp-operation-metal-sharpen.h"


enum
{
  PROP_0,
  PROP_AMOUNT
};


static void     gimp_operation_metal_sharpen_get_property (GObject         *object,
                                                           guint            property_id,
                                                           GValue          *value,
                                                           GParamSpec      *pspec);
static void     gimp_operation_metal_sharpen_set_property (GObject         *object,
                                                           guint            property_id,
                                                           const GValue    *value,
                                                           GParamSpec      *pspec);

static void     gimp_operation_metal_sharpen_prepare      (GeglOperation       *operation);
static gboolean gimp_operation_metal_sharpen_process      (GeglOperation       *operation,
                                                           GeglBuffer          *input,
                                                           GeglBuffer          *output,
                                                           const GeglRectangle *result,
                                                           gint                 level);


G_DEFINE_TYPE (GimpOperationMetalSharpen, gimp_operation_metal_sharpen,
               GEGL_TYPE_OPERATION_FILTER)

#define parent_class gimp_operation_metal_sharpen_parent_class


static void
gimp_operation_metal_sharpen_class_init (GimpOperationMetalSharpenClass *klass)
{
  GObjectClass               *object_class    = G_OBJECT_CLASS (klass);
  GeglOperationClass         *operation_class = GEGL_OPERATION_CLASS (klass);
  GeglOperationFilterClass   *filter_class    = GEGL_OPERATION_FILTER_CLASS (klass);

  object_class->get_property = gimp_operation_metal_sharpen_get_property;
  object_class->set_property = gimp_operation_metal_sharpen_set_property;

  operation_class->prepare   = gimp_operation_metal_sharpen_prepare;
  filter_class->process      = gimp_operation_metal_sharpen_process;

  gegl_operation_class_set_keys (operation_class,
                                  "name",        "gimp:metal-sharpen",
                                  "categories",  "enhance",
                                  "description", "Sharpen using Metal GPU acceleration",
                                  NULL);

  g_object_class_install_property (object_class, PROP_AMOUNT,
                                    g_param_spec_double ("amount",
                                                        "Amount",
                                                        "Sharpen amount",
                                                        0.0, 10.0, 1.0,
                                                        G_PARAM_READWRITE |
                                                        G_PARAM_CONSTRUCT));
}

static void
gimp_operation_metal_sharpen_init (GimpOperationMetalSharpen *self)
{
  self->amount = 1.0;
}

static void
gimp_operation_metal_sharpen_get_property (GObject    *object,
                                          guint       property_id,
                                          GValue     *value,
                                          GParamSpec *pspec)
{
  GimpOperationMetalSharpen *self = GIMP_OPERATION_METAL_SHARPEN (object);

  switch (property_id)
    {
    case PROP_AMOUNT:
      g_value_set_double (value, self->amount);
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
      break;
    }
}

static void
gimp_operation_metal_sharpen_set_property (GObject      *object,
                                          guint         property_id,
                                          const GValue *value,
                                          GParamSpec   *pspec)
{
  GimpOperationMetalSharpen *self = GIMP_OPERATION_METAL_SHARPEN (object);

  switch (property_id)
    {
    case PROP_AMOUNT:
      self->amount = g_value_get_double (value);
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
      break;
    }
}

static void
gimp_operation_metal_sharpen_prepare (GeglOperation *operation)
{
  const Babl *format = babl_format ("RGBA float");

  gegl_operation_set_format (operation, "input",  format);
  gegl_operation_set_format (operation, "output", format);
}

static gboolean
gimp_operation_metal_sharpen_process (GeglOperation       *operation,
                                     GeglBuffer          *input,
                                     GeglBuffer          *output,
                                     const GeglRectangle *result,
                                     gint                 level)
{
  GimpOperationMetalSharpen *self = GIMP_OPERATION_METAL_SHARPEN (operation);

#ifdef HAVE_METAL
  /* Try Metal acceleration first */
  if (gimp_gegl_metal_sharpen (input, result, output, result, self->amount))
    return TRUE;
#endif

  /* Fallback: use GEGL's built-in sharpen */
  {
    GeglNode *gegl;
    GeglNode *input_node;
    GeglNode *sharpen_node;
    GeglNode *output_node;

    gegl = gegl_node_new ();

    input_node = gegl_node_new_child (gegl,
                                      "operation", "gegl:buffer-source",
                                      "buffer",    input,
                                      NULL);

    sharpen_node = gegl_node_new_child (gegl,
                                        "operation", "gegl:unsharp-mask",
                                        "scale",     self->amount,
                                        NULL);

    output_node = gegl_node_new_child (gegl,
                                       "operation", "gegl:write-buffer",
                                       "buffer",    output,
                                       NULL);

    gegl_node_link_many (input_node, sharpen_node, output_node, NULL);
    gegl_node_process (output_node);

    g_object_unref (gegl);
  }

  return TRUE;
}
