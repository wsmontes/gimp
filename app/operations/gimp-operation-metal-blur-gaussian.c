/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-operation-metal-blur-gaussian.c
 * Metal-accelerated gaussian blur operation
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
#include "gimp-operation-metal-blur-gaussian.h"


enum
{
  PROP_0,
  PROP_STD_DEV_X,
  PROP_STD_DEV_Y
};


static void     gimp_operation_metal_blur_gaussian_get_property (GObject         *object,
                                                                 guint            property_id,
                                                                 GValue          *value,
                                                                 GParamSpec      *pspec);
static void     gimp_operation_metal_blur_gaussian_set_property (GObject         *object,
                                                                 guint            property_id,
                                                                 const GValue    *value,
                                                                 GParamSpec      *pspec);

static void     gimp_operation_metal_blur_gaussian_prepare      (GeglOperation       *operation);
static gboolean gimp_operation_metal_blur_gaussian_process      (GeglOperation       *operation,
                                                                 GeglBuffer          *input,
                                                                 GeglBuffer          *output,
                                                                 const GeglRectangle *result,
                                                                 gint                 level);


G_DEFINE_TYPE (GimpOperationMetalBlurGaussian, gimp_operation_metal_blur_gaussian,
               GEGL_TYPE_OPERATION_FILTER)

#define parent_class gimp_operation_metal_blur_gaussian_parent_class


static void
gimp_operation_metal_blur_gaussian_class_init (GimpOperationMetalBlurGaussianClass *klass)
{
  GObjectClass               *object_class    = G_OBJECT_CLASS (klass);
  GeglOperationClass         *operation_class = GEGL_OPERATION_CLASS (klass);
  GeglOperationFilterClass   *filter_class    = GEGL_OPERATION_FILTER_CLASS (klass);

  object_class->get_property = gimp_operation_metal_blur_gaussian_get_property;
  object_class->set_property = gimp_operation_metal_blur_gaussian_set_property;

  operation_class->prepare   = gimp_operation_metal_blur_gaussian_prepare;
  filter_class->process      = gimp_operation_metal_blur_gaussian_process;

  gegl_operation_class_set_keys (operation_class,
                                  "name",        "gimp:metal-blur-gaussian",
                                  "categories",  "blur",
                                  "description", "Gaussian blur using Metal GPU acceleration",
                                  NULL);

  g_object_class_install_property (object_class, PROP_STD_DEV_X,
                                    g_param_spec_double ("std-dev-x",
                                                        "Std Dev X",
                                                        "Standard deviation X",
                                                        0.0, 1000.0, 1.0,
                                                        G_PARAM_READWRITE |
                                                        G_PARAM_CONSTRUCT));

  g_object_class_install_property (object_class, PROP_STD_DEV_Y,
                                    g_param_spec_double ("std-dev-y",
                                                        "Std Dev Y",
                                                        "Standard deviation Y",
                                                        0.0, 1000.0, 1.0,
                                                        G_PARAM_READWRITE |
                                                        G_PARAM_CONSTRUCT));
}

static void
gimp_operation_metal_blur_gaussian_init (GimpOperationMetalBlurGaussian *self)
{
  self->std_dev_x = 1.0;
  self->std_dev_y = 1.0;
}

static void
gimp_operation_metal_blur_gaussian_get_property (GObject    *object,
                                                guint       property_id,
                                                GValue     *value,
                                                GParamSpec *pspec)
{
  GimpOperationMetalBlurGaussian *self = GIMP_OPERATION_METAL_BLUR_GAUSSIAN (object);

  switch (property_id)
    {
    case PROP_STD_DEV_X:
      g_value_set_double (value, self->std_dev_x);
      break;

    case PROP_STD_DEV_Y:
      g_value_set_double (value, self->std_dev_y);
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
      break;
    }
}

static void
gimp_operation_metal_blur_gaussian_set_property (GObject      *object,
                                                guint         property_id,
                                                const GValue *value,
                                                GParamSpec   *pspec)
{
  GimpOperationMetalBlurGaussian *self = GIMP_OPERATION_METAL_BLUR_GAUSSIAN (object);

  switch (property_id)
    {
    case PROP_STD_DEV_X:
      self->std_dev_x = g_value_get_double (value);
      break;

    case PROP_STD_DEV_Y:
      self->std_dev_y = g_value_get_double (value);
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
      break;
    }
}

static void
gimp_operation_metal_blur_gaussian_prepare (GeglOperation *operation)
{
  const Babl *format = babl_format ("RGBA float");

  gegl_operation_set_format (operation, "input",  format);
  gegl_operation_set_format (operation, "output", format);
}

static gboolean
gimp_operation_metal_blur_gaussian_process (GeglOperation       *operation,
                                           GeglBuffer          *input,
                                           GeglBuffer          *output,
                                           const GeglRectangle *result,
                                           gint                 level)
{
  GimpOperationMetalBlurGaussian *self = GIMP_OPERATION_METAL_BLUR_GAUSSIAN (operation);

#ifdef HAVE_METAL
  /* Try Metal acceleration first */
  if (gimp_gegl_metal_blur_gaussian (input, result, output, result,
                                    self->std_dev_x, self->std_dev_y))
    return TRUE;
#endif

  /* Fallback: use GEGL's built-in gaussian blur */
  {
    GeglNode *gegl;
    GeglNode *input_node;
    GeglNode *blur_node;
    GeglNode *output_node;

    gegl = gegl_node_new ();

    input_node = gegl_node_new_child (gegl,
                                      "operation", "gegl:buffer-source",
                                      "buffer",    input,
                                      NULL);

    blur_node = gegl_node_new_child (gegl,
                                     "operation", "gegl:gaussian-blur",
                                     "std-dev-x", self->std_dev_x,
                                     "std-dev-y", self->std_dev_y,
                                     NULL);

    output_node = gegl_node_new_child (gegl,
                                       "operation", "gegl:write-buffer",
                                       "buffer",    output,
                                       NULL);

    gegl_node_link_many (input_node, blur_node, output_node, NULL);
    gegl_node_process (output_node);

    g_object_unref (gegl);
  }

  return TRUE;
}
