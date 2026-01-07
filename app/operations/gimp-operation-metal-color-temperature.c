/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-operation-metal-color-temperature.c
 * Metal GPU override for gegl:color-temperature
 */

#include "config.h"

#include <gegl.h>

#include "../gegl/gimp-gegl-loops-metal.h"

#include "gimp-operation-metal-color-temperature.h"


enum
{
  PROP_0,
  PROP_TEMPERATURE
};


static void     gimp_operation_metal_color_temperature_get_property (GObject      *object,
                                                                      guint         property_id,
                                                                      GValue       *value,
                                                                      GParamSpec   *pspec);
static void     gimp_operation_metal_color_temperature_set_property (GObject      *object,
                                                                      guint         property_id,
                                                                      const GValue *value,
                                                                      GParamSpec   *pspec);

static gboolean gimp_operation_metal_color_temperature_process      (GeglOperation       *operation,
                                                                      GeglBuffer          *input,
                                                                      GeglBuffer          *output,
                                                                      const GeglRectangle *result,
                                                                      gint                 level);


G_DEFINE_TYPE (GimpOperationMetalColorTemperature, gimp_operation_metal_color_temperature,
               GEGL_TYPE_OPERATION_FILTER)

#define parent_class gimp_operation_metal_color_temperature_parent_class


static void
gimp_operation_metal_color_temperature_class_init (GimpOperationMetalColorTemperatureClass *klass)
{
  GObjectClass                    *object_class;
  GeglOperationClass              *operation_class;
  GeglOperationFilterClass        *filter_class;

  object_class    = G_OBJECT_CLASS (klass);
  operation_class = GEGL_OPERATION_CLASS (klass);
  filter_class    = GEGL_OPERATION_FILTER_CLASS (klass);

  object_class->set_property = gimp_operation_metal_color_temperature_set_property;
  object_class->get_property = gimp_operation_metal_color_temperature_get_property;

  gegl_operation_class_set_keys (operation_class,
                                 "name",        "gegl:color-temperature",
                                 "categories",  "color",
                                 "description", "Color Temperature adjustment (Metal GPU accelerated)",
                                 NULL);

  filter_class->process = gimp_operation_metal_color_temperature_process;

  g_object_class_install_property (object_class, PROP_TEMPERATURE,
                                   g_param_spec_double ("temperature",
                                                        "Temperature",
                                                        "Color temperature (-1.0 to 1.0)",
                                                        -1.0, 1.0, 0.0,
                                                        G_PARAM_READWRITE |
                                                        G_PARAM_CONSTRUCT));
}

static void
gimp_operation_metal_color_temperature_init (GimpOperationMetalColorTemperature *self)
{
}

static void
gimp_operation_metal_color_temperature_get_property (GObject    *object,
                                                      guint       property_id,
                                                      GValue     *value,
                                                      GParamSpec *pspec)
{
  GimpOperationMetalColorTemperature *self = GIMP_OPERATION_METAL_COLOR_TEMPERATURE (object);

  switch (property_id)
    {
    case PROP_TEMPERATURE:
      g_value_set_double (value, self->temperature);
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
      break;
    }
}

static void
gimp_operation_metal_color_temperature_set_property (GObject      *object,
                                                      guint         property_id,
                                                      const GValue *value,
                                                      GParamSpec   *pspec)
{
  GimpOperationMetalColorTemperature *self = GIMP_OPERATION_METAL_COLOR_TEMPERATURE (object);

  switch (property_id)
    {
    case PROP_TEMPERATURE:
      self->temperature = g_value_get_double (value);
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
      break;
    }
}

static gboolean
gimp_operation_metal_color_temperature_process (GeglOperation       *operation,
                                                 GeglBuffer          *input,
                                                 GeglBuffer          *output,
                                                 const GeglRectangle *result,
                                                 gint                 level)
{
  GimpOperationMetalColorTemperature *self = GIMP_OPERATION_METAL_COLOR_TEMPERATURE (operation);

#ifdef HAVE_METAL
  if (gimp_gegl_metal_is_available ())
    {
      if (gimp_gegl_metal_color_temperature (input, result, output, result,
                                             self->temperature))
        return TRUE;
    }
#endif

  /* CPU fallback - simple copy */
  gegl_buffer_copy (input, result, GEGL_ABYSS_NONE, output, result);

  return TRUE;
}
