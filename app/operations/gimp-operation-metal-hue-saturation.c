/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-operation-metal-hue-saturation.c
 * Metal GPU override for gegl:hue-chroma
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

#include "gimp-operation-metal-hue-saturation.h"


enum
{
  PROP_0,
  PROP_HUE,
  PROP_CHROMA,
  PROP_LIGHTNESS
};


static void     gimp_operation_metal_hue_saturation_get_property (GObject      *object,
                                                                   guint         property_id,
                                                                   GValue       *value,
                                                                   GParamSpec   *pspec);
static void     gimp_operation_metal_hue_saturation_set_property (GObject      *object,
                                                                   guint         property_id,
                                                                   const GValue *value,
                                                                   GParamSpec   *pspec);

static gboolean gimp_operation_metal_hue_saturation_process      (GeglOperation       *operation,
                                                                   GeglBuffer          *input,
                                                                   GeglBuffer          *output,
                                                                   const GeglRectangle *roi,
                                                                   gint                 level);


G_DEFINE_TYPE (GimpOperationMetalHueSaturation, gimp_operation_metal_hue_saturation,
               GEGL_TYPE_OPERATION_FILTER)

#define parent_class gimp_operation_metal_hue_saturation_parent_class


static void
gimp_operation_metal_hue_saturation_class_init (GimpOperationMetalHueSaturationClass *klass)
{
  GObjectClass                    *object_class;
  GeglOperationClass              *operation_class;
  GeglOperationFilterClass        *filter_class;

  object_class    = G_OBJECT_CLASS (klass);
  operation_class = GEGL_OPERATION_CLASS (klass);
  filter_class    = GEGL_OPERATION_FILTER_CLASS (klass);

  object_class->set_property = gimp_operation_metal_hue_saturation_set_property;
  object_class->get_property = gimp_operation_metal_hue_saturation_get_property;

  gegl_operation_class_set_keys (operation_class,
                                 "name",        "gegl:hue-chroma",
                                 "categories",  "color",
                                 "description", "Hue-Saturation adjustment (Metal GPU accelerated)",
                                 NULL);

  filter_class->process = gimp_operation_metal_hue_saturation_process;

  g_object_class_install_property (object_class, PROP_HUE,
                                   g_param_spec_double ("hue",
                                                        "Hue",
                                                        "Hue offset (-180 to 180 degrees)",
                                                        -180.0, 180.0, 0.0,
                                                        G_PARAM_READWRITE |
                                                        G_PARAM_CONSTRUCT));

  g_object_class_install_property (object_class, PROP_CHROMA,
                                   g_param_spec_double ("chroma",
                                                        "Chroma",
                                                        "Saturation scale (0.0 to 2.0)",
                                                        0.0, 2.0, 1.0,
                                                        G_PARAM_READWRITE |
                                                        G_PARAM_CONSTRUCT));

  g_object_class_install_property (object_class, PROP_LIGHTNESS,
                                   g_param_spec_double ("lightness",
                                                        "Lightness",
                                                        "Lightness adjustment (-1.0 to 1.0)",
                                                        -1.0, 1.0, 0.0,
                                                        G_PARAM_READWRITE |
                                                        G_PARAM_CONSTRUCT));
}

static void
gimp_operation_metal_hue_saturation_init (GimpOperationMetalHueSaturation *self)
{
}

static void
gimp_operation_metal_hue_saturation_get_property (GObject    *object,
                                                   guint       property_id,
                                                   GValue     *value,
                                                   GParamSpec *pspec)
{
  GimpOperationMetalHueSaturation *self = GIMP_OPERATION_METAL_HUE_SATURATION (object);

  switch (property_id)
    {
    case PROP_HUE:
      g_value_set_double (value, self->hue);
      break;

    case PROP_CHROMA:
      g_value_set_double (value, self->chroma);
      break;

    case PROP_LIGHTNESS:
      g_value_set_double (value, self->lightness);
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
      break;
    }
}

static void
gimp_operation_metal_hue_saturation_set_property (GObject      *object,
                                                   guint         property_id,
                                                   const GValue *value,
                                                   GParamSpec   *pspec)
{
  GimpOperationMetalHueSaturation *self = GIMP_OPERATION_METAL_HUE_SATURATION (object);

  switch (property_id)
    {
    case PROP_HUE:
      self->hue = g_value_get_double (value);
      break;

    case PROP_CHROMA:
      self->chroma = g_value_get_double (value);
      break;

    case PROP_LIGHTNESS:
      self->lightness = g_value_get_double (value);
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
      break;
    }
}

static gboolean
gimp_operation_metal_hue_saturation_process (GeglOperation       *operation,
                                              GeglBuffer          *input,
                                              GeglBuffer          *output,
                                              const GeglRectangle *roi,
                                              gint                 level)
{
  GimpOperationMetalHueSaturation *self = GIMP_OPERATION_METAL_HUE_SATURATION (operation);

#ifdef HAVE_METAL
  if (gimp_gegl_metal_is_available ())
    {
      gdouble hue_norm = self->hue / 360.0;  /* Convert degrees to 0-1 range */
      if (gimp_gegl_metal_hue_saturation (input, roi, output, roi,
                                          hue_norm, self->chroma, self->lightness))
        return TRUE;
    }
#endif

  /* CPU fallback */
  GeglNode *gegl = gegl_node_new ();
  GeglNode *input_node = gegl_node_new_child (gegl,
                                               "operation", "gegl:buffer-source",
                                               "buffer", input,
                                               NULL);
  GeglNode *huesat = gegl_node_new_child (gegl,
                                          "operation", "gegl:hue-chroma",
                                          "hue", self->hue,
                                          "chroma", self->chroma,
                                          "lightness", self->lightness,
                                          NULL);
  GeglNode *output_node = gegl_node_new_child (gegl,
                                                "operation", "gegl:write-buffer",
                                                "buffer", output,
                                                NULL);

  gegl_node_link_many (input_node, huesat, output_node, NULL);
  gegl_node_process (output_node);

  g_object_unref (gegl);

  return TRUE;
}
