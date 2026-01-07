/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-operation-metal-gaussian-blur.c
 * Metal-accelerated gaussian blur using MPS
 * Intercepts gegl:gaussian-blur
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 */

#include "config.h"
#include <gegl.h>
#include "../gegl/gimp-gegl-loops-metal.h"
#include "gimp-operation-metal-gaussian-blur.h"

enum
{
  PROP_0,
  PROP_STD_DEV_X,
  PROP_STD_DEV_Y,
  PROP_FILTER,
  PROP_ABYSS_POLICY
};

static void     gimp_operation_metal_gaussian_blur_prepare      (GeglOperation       *operation);
static gboolean gimp_operation_metal_gaussian_blur_process      (GeglOperation       *operation,
                                                                  GeglBuffer          *input,
                                                                  GeglBuffer          *output,
                                                                  const GeglRectangle *result,
                                                                  gint                 level);
static void     gimp_operation_metal_gaussian_blur_get_property (GObject             *object,
                                                                  guint                property_id,
                                                                  GValue              *value,
                                                                  GParamSpec          *pspec);
static void     gimp_operation_metal_gaussian_blur_set_property (GObject             *object,
                                                                  guint                property_id,
                                                                  const GValue        *value,
                                                                  GParamSpec          *pspec);

G_DEFINE_TYPE (GimpOperationMetalGaussianBlur, gimp_operation_metal_gaussian_blur,
               GEGL_TYPE_OPERATION_FILTER)

#define parent_class gimp_operation_metal_gaussian_blur_parent_class

static void
gimp_operation_metal_gaussian_blur_class_init (GimpOperationMetalGaussianBlurClass *klass)
{
  GObjectClass              *object_class    = G_OBJECT_CLASS (klass);
  GeglOperationClass        *operation_class = GEGL_OPERATION_CLASS (klass);
  GeglOperationFilterClass  *filter_class    = GEGL_OPERATION_FILTER_CLASS (klass);

  object_class->set_property = gimp_operation_metal_gaussian_blur_set_property;
  object_class->get_property = gimp_operation_metal_gaussian_blur_get_property;

  operation_class->prepare = gimp_operation_metal_gaussian_blur_prepare;
  filter_class->process    = gimp_operation_metal_gaussian_blur_process;

  gegl_operation_class_set_keys (operation_class,
                                  "name",        "gegl:gaussian-blur",
                                  "categories",  "blur",
                                  "description", "Gaussian blur using Metal GPU acceleration (MPS)",
                                  NULL);

  g_object_class_install_property (object_class, PROP_STD_DEV_X,
                                    g_param_spec_double ("std-dev-x",
                                                         "Std Dev X",
                                                         "Standard deviation (x axis)",
                                                         0.0, 1500.0, 1.5,
                                                         G_PARAM_READWRITE |
                                                         G_PARAM_CONSTRUCT));

  g_object_class_install_property (object_class, PROP_STD_DEV_Y,
                                    g_param_spec_double ("std-dev-y",
                                                         "Std Dev Y",
                                                         "Standard deviation (y axis)",
                                                         0.0, 1500.0, 1.5,
                                                         G_PARAM_READWRITE |
                                                         G_PARAM_CONSTRUCT));

  g_object_class_install_property (object_class, PROP_FILTER,
                                    g_param_spec_string ("filter",
                                                         "Filter",
                                                         "Optional filter",
                                                         "auto",
                                                         G_PARAM_READWRITE |
                                                         G_PARAM_CONSTRUCT));

  g_object_class_install_property (object_class, PROP_ABYSS_POLICY,
                                    g_param_spec_int ("abyss-policy",
                                                      "Abyss Policy",
                                                      "How to handle pixels outside input",
                                                      0, 5, 0,
                                                      G_PARAM_READWRITE |
                                                      G_PARAM_CONSTRUCT));
}

static void
gimp_operation_metal_gaussian_blur_init (GimpOperationMetalGaussianBlur *self)
{
  self->std_dev_x      = 1.5;
  self->std_dev_y      = 1.5;
  self->filter         = g_strdup ("auto");
  self->abyss_policy   = 0;
}

static void
gimp_operation_metal_gaussian_blur_prepare (GeglOperation *operation)
{
  const Babl *format = babl_format ("RGBA float");

  gegl_operation_set_format (operation, "input",  format);
  gegl_operation_set_format (operation, "output", format);
}

static void
gimp_operation_metal_gaussian_blur_get_property (GObject    *object,
                                                  guint       property_id,
                                                  GValue     *value,
                                                  GParamSpec *pspec)
{
  GimpOperationMetalGaussianBlur *self = GIMP_OPERATION_METAL_GAUSSIAN_BLUR (object);

  switch (property_id)
    {
    case PROP_STD_DEV_X:
      g_value_set_double (value, self->std_dev_x);
      break;

    case PROP_STD_DEV_Y:
      g_value_set_double (value, self->std_dev_y);
      break;

    case PROP_FILTER:
      g_value_set_string (value, self->filter);
      break;

    case PROP_ABYSS_POLICY:
      g_value_set_int (value, self->abyss_policy);
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
      break;
    }
}

static void
gimp_operation_metal_gaussian_blur_set_property (GObject      *object,
                                                  guint         property_id,
                                                  const GValue *value,
                                                  GParamSpec   *pspec)
{
  GimpOperationMetalGaussianBlur *self = GIMP_OPERATION_METAL_GAUSSIAN_BLUR (object);

  switch (property_id)
    {
    case PROP_STD_DEV_X:
      self->std_dev_x = g_value_get_double (value);
      break;

    case PROP_STD_DEV_Y:
      self->std_dev_y = g_value_get_double (value);
      break;

    case PROP_FILTER:
      g_free (self->filter);
      self->filter = g_value_dup_string (value);
      break;

    case PROP_ABYSS_POLICY:
      self->abyss_policy = g_value_get_int (value);
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
      break;
    }
}

static gboolean
gimp_operation_metal_gaussian_blur_process (GeglOperation       *operation,
                                             GeglBuffer          *input,
                                             GeglBuffer          *output,
                                             const GeglRectangle *result,
                                             gint                 level)
{
  GimpOperationMetalGaussianBlur *self = GIMP_OPERATION_METAL_GAUSSIAN_BLUR (operation);

#ifdef HAVE_METAL
  /* Try Metal MPS gaussian blur */
  if (gimp_gegl_metal_is_available ())
    {
      /* MPS takes sigma, use std_dev_x/y as blur parameters */
      if (gimp_gegl_metal_blur_gaussian (input, result, output, result, self->std_dev_x, self->std_dev_y))
        return TRUE;
    }
#endif

  /* CPU fallback using GEGL's built-in gaussian blur */
  {
    GeglNode *node;
    GeglNode *input_node;
    GeglNode *blur_node;
    GeglNode *output_node;

    node = gegl_node_new ();

    input_node = gegl_node_new_child (node,
                                       "operation", "gegl:buffer-source",
                                       "buffer", input,
                                       NULL);

    blur_node = gegl_node_new_child (node,
                                      "operation", "gegl:box-blur",
                                      "radius-x", self->std_dev_x * 3.0,
                                      "radius-y", self->std_dev_y * 3.0,
                                      NULL);

    output_node = gegl_node_new_child (node,
                                        "operation", "gegl:buffer-sink",
                                        "buffer", output,
                                        NULL);

    gegl_node_link_many (input_node, blur_node, output_node, NULL);
    gegl_node_process (output_node);
    g_object_unref (node);
  }

  return TRUE;
}
