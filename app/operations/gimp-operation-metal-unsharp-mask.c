/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-operation-metal-unsharp-mask.c
 * Metal-accelerated unsharp mask using MPS
 * Intercepts gegl:unsharp-mask
 */

#include "config.h"
#include <gegl.h>
#include "../gegl/gimp-gegl-loops-metal.h"
#include "gimp-operation-metal-unsharp-mask.h"

enum
{
  PROP_0,
  PROP_STD_DEV,
  PROP_SCALE,
  PROP_THRESHOLD
};

static void     gimp_operation_metal_unsharp_mask_prepare      (GeglOperation       *operation);
static gboolean gimp_operation_metal_unsharp_mask_process      (GeglOperation       *operation,
                                                                 GeglBuffer          *input,
                                                                 GeglBuffer          *output,
                                                                 const GeglRectangle *result,
                                                                 gint                 level);
static void     gimp_operation_metal_unsharp_mask_get_property (GObject             *object,
                                                                 guint                property_id,
                                                                 GValue              *value,
                                                                 GParamSpec          *pspec);
static void     gimp_operation_metal_unsharp_mask_set_property (GObject             *object,
                                                                 guint                property_id,
                                                                 const GValue        *value,
                                                                 GParamSpec          *pspec);

G_DEFINE_TYPE (GimpOperationMetalUnsharpMask, gimp_operation_metal_unsharp_mask,
               GEGL_TYPE_OPERATION_FILTER)

#define parent_class gimp_operation_metal_unsharp_mask_parent_class

static void
gimp_operation_metal_unsharp_mask_class_init (GimpOperationMetalUnsharpMaskClass *klass)
{
  GObjectClass              *object_class    = G_OBJECT_CLASS (klass);
  GeglOperationClass        *operation_class = GEGL_OPERATION_CLASS (klass);
  GeglOperationFilterClass  *filter_class    = GEGL_OPERATION_FILTER_CLASS (klass);

  object_class->set_property = gimp_operation_metal_unsharp_mask_set_property;
  object_class->get_property = gimp_operation_metal_unsharp_mask_get_property;

  operation_class->prepare = gimp_operation_metal_unsharp_mask_prepare;
  filter_class->process    = gimp_operation_metal_unsharp_mask_process;

  gegl_operation_class_set_keys (operation_class,
                                  "name",        "gegl:unsharp-mask",
                                  "categories",  "enhance:sharpen",
                                  "description", "Unsharp mask using Metal GPU acceleration (MPS)",
                                  NULL);

  g_object_class_install_property (object_class, PROP_STD_DEV,
                                    g_param_spec_double ("std-dev",
                                                         "Std Dev",
                                                         "Standard deviation",
                                                         0.0, 1500.0, 1.0,
                                                         G_PARAM_READWRITE |
                                                         G_PARAM_CONSTRUCT));

  g_object_class_install_property (object_class, PROP_SCALE,
                                    g_param_spec_double ("scale",
                                                         "Scale",
                                                         "Sharpening amount",
                                                         0.0, 5.0, 1.0,
                                                         G_PARAM_READWRITE |
                                                         G_PARAM_CONSTRUCT));

  g_object_class_install_property (object_class, PROP_THRESHOLD,
                                    g_param_spec_double ("threshold",
                                                         "Threshold",
                                                         "Threshold",
                                                         0.0, 1.0, 0.0,
                                                         G_PARAM_READWRITE |
                                                         G_PARAM_CONSTRUCT));
}

static void
gimp_operation_metal_unsharp_mask_init (GimpOperationMetalUnsharpMask *self)
{
  self->std_dev   = 1.0;
  self->scale     = 1.0;
  self->threshold = 0.0;
}

static void
gimp_operation_metal_unsharp_mask_prepare (GeglOperation *operation)
{
  const Babl *format = babl_format ("RGBA float");

  gegl_operation_set_format (operation, "input",  format);
  gegl_operation_set_format (operation, "output", format);
}

static void
gimp_operation_metal_unsharp_mask_get_property (GObject    *object,
                                                 guint       property_id,
                                                 GValue     *value,
                                                 GParamSpec *pspec)
{
  GimpOperationMetalUnsharpMask *self = GIMP_OPERATION_METAL_UNSHARP_MASK (object);

  switch (property_id)
    {
    case PROP_STD_DEV:
      g_value_set_double (value, self->std_dev);
      break;

    case PROP_SCALE:
      g_value_set_double (value, self->scale);
      break;

    case PROP_THRESHOLD:
      g_value_set_double (value, self->threshold);
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
      break;
    }
}

static void
gimp_operation_metal_unsharp_mask_set_property (GObject      *object,
                                                 guint         property_id,
                                                 const GValue *value,
                                                 GParamSpec   *pspec)
{
  GimpOperationMetalUnsharpMask *self = GIMP_OPERATION_METAL_UNSHARP_MASK (object);

  switch (property_id)
    {
    case PROP_STD_DEV:
      self->std_dev = g_value_get_double (value);
      break;

    case PROP_SCALE:
      self->scale = g_value_get_double (value);
      break;

    case PROP_THRESHOLD:
      self->threshold = g_value_get_double (value);
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
      break;
    }
}

static gboolean
gimp_operation_metal_unsharp_mask_process (GeglOperation       *operation,
                                            GeglBuffer          *input,
                                            GeglBuffer          *output,
                                            const GeglRectangle *result,
                                            gint                 level)
{
  GimpOperationMetalUnsharpMask *self = GIMP_OPERATION_METAL_UNSHARP_MASK (operation);

#ifdef HAVE_METAL
  /* Try Metal MPS unsharp mask */
  if (gimp_gegl_metal_is_available ())
    {
      if (gimp_gegl_metal_unsharp_mask (input, result, output, result,
                                         self->std_dev, self->scale))
        return TRUE;
    }
#endif

  /* CPU fallback */
  {
    GeglNode *node;
    GeglNode *input_node;
    GeglNode *blur_node;
    GeglNode *subtract_node;
    GeglNode *multiply_node;
    GeglNode *add_node;
    GeglNode *output_node;

    node = gegl_node_new ();

    input_node = gegl_node_new_child (node,
                                       "operation", "gegl:buffer-source",
                                       "buffer", input,
                                       NULL);

    blur_node = gegl_node_new_child (node,
                                      "operation", "gegl:gaussian-blur",
                                      "std-dev-x", self->std_dev,
                                      "std-dev-y", self->std_dev,
                                      NULL);

    subtract_node = gegl_node_new_child (node,
                                          "operation", "gegl:subtract",
                                          NULL);

    multiply_node = gegl_node_new_child (node,
                                          "operation", "gegl:multiply",
                                          "value", self->scale,
                                          NULL);

    add_node = gegl_node_new_child (node,
                                     "operation", "gegl:add",
                                     NULL);

    output_node = gegl_node_new_child (node,
                                        "operation", "gegl:buffer-sink",
                                        "buffer", output,
                                        NULL);

    gegl_node_link (input_node, blur_node);
    gegl_node_connect_to (input_node, "output", subtract_node, "input");
    gegl_node_connect_to (blur_node, "output", subtract_node, "aux");
    gegl_node_link (subtract_node, multiply_node);
    gegl_node_connect_to (input_node, "output", add_node, "input");
    gegl_node_connect_to (multiply_node, "output", add_node, "aux");
    gegl_node_link (add_node, output_node);

    gegl_node_process (output_node);
    g_object_unref (node);
  }

  return TRUE;
}
