/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-operation-metal-brightness-contrast.c
 * Metal-accelerated brightness/contrast operation
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
#include "gimp-operation-metal-brightness-contrast.h"


enum
{
  PROP_0,
  PROP_BRIGHTNESS,
  PROP_CONTRAST
};


static void     gimp_operation_metal_brightness_contrast_get_property (GObject         *object,
                                                                       guint            property_id,
                                                                       GValue          *value,
                                                                       GParamSpec      *pspec);
static void     gimp_operation_metal_brightness_contrast_set_property (GObject         *object,
                                                                       guint            property_id,
                                                                       const GValue    *value,
                                                                       GParamSpec      *pspec);

static void     gimp_operation_metal_brightness_contrast_prepare      (GeglOperation       *operation);
static gboolean gimp_operation_metal_brightness_contrast_process      (GeglOperation       *operation,
                                                                       GeglBuffer          *input,
                                                                       GeglBuffer          *output,
                                                                       const GeglRectangle *result,
                                                                       gint                 level);


G_DEFINE_TYPE (GimpOperationMetalBrightnessContrast, gimp_operation_metal_brightness_contrast,
               GEGL_TYPE_OPERATION_FILTER)

#define parent_class gimp_operation_metal_brightness_contrast_parent_class


static void
gimp_operation_metal_brightness_contrast_class_init (GimpOperationMetalBrightnessContrastClass *klass)
{
  GObjectClass               *object_class    = G_OBJECT_CLASS (klass);
  GeglOperationClass         *operation_class = GEGL_OPERATION_CLASS (klass);
  GeglOperationFilterClass   *filter_class    = GEGL_OPERATION_FILTER_CLASS (klass);

  object_class->get_property = gimp_operation_metal_brightness_contrast_get_property;
  object_class->set_property = gimp_operation_metal_brightness_contrast_set_property;

  operation_class->prepare   = gimp_operation_metal_brightness_contrast_prepare;
  filter_class->process      = gimp_operation_metal_brightness_contrast_process;

  gegl_operation_class_set_keys (operation_class,
                                  "name",        "gimp:metal-brightness-contrast",
                                  "categories",  "color",
                                  "description", "Adjust brightness and contrast using Metal GPU acceleration",
                                  NULL);

  g_object_class_install_property (object_class, PROP_BRIGHTNESS,
                                    g_param_spec_double ("brightness",
                                                        "Brightness",
                                                        "Brightness adjustment",
                                                        -1.0, 1.0, 0.0,
                                                        G_PARAM_READWRITE |
                                                        G_PARAM_CONSTRUCT));

  g_object_class_install_property (object_class, PROP_CONTRAST,
                                    g_param_spec_double ("contrast",
                                                        "Contrast",
                                                        "Contrast adjustment",
                                                        0.0, 10.0, 1.0,
                                                        G_PARAM_READWRITE |
                                                        G_PARAM_CONSTRUCT));
}

static void
gimp_operation_metal_brightness_contrast_init (GimpOperationMetalBrightnessContrast *self)
{
  self->brightness = 0.0;
  self->contrast   = 1.0;
}

static void
gimp_operation_metal_brightness_contrast_get_property (GObject    *object,
                                                      guint       property_id,
                                                      GValue     *value,
                                                      GParamSpec *pspec)
{
  GimpOperationMetalBrightnessContrast *self = GIMP_OPERATION_METAL_BRIGHTNESS_CONTRAST (object);

  switch (property_id)
    {
    case PROP_BRIGHTNESS:
      g_value_set_double (value, self->brightness);
      break;

    case PROP_CONTRAST:
      g_value_set_double (value, self->contrast);
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
      break;
    }
}

static void
gimp_operation_metal_brightness_contrast_set_property (GObject      *object,
                                                      guint         property_id,
                                                      const GValue *value,
                                                      GParamSpec   *pspec)
{
  GimpOperationMetalBrightnessContrast *self = GIMP_OPERATION_METAL_BRIGHTNESS_CONTRAST (object);

  switch (property_id)
    {
    case PROP_BRIGHTNESS:
      self->brightness = g_value_get_double (value);
      break;

    case PROP_CONTRAST:
      self->contrast = g_value_get_double (value);
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
      break;
    }
}

static void
gimp_operation_metal_brightness_contrast_prepare (GeglOperation *operation)
{
  const Babl *format = babl_format ("RGBA float");

  gegl_operation_set_format (operation, "input",  format);
  gegl_operation_set_format (operation, "output", format);
}

static gboolean
gimp_operation_metal_brightness_contrast_process (GeglOperation       *operation,
                                                 GeglBuffer          *input,
                                                 GeglBuffer          *output,
                                                 const GeglRectangle *result,
                                                 gint                 level)
{
  GimpOperationMetalBrightnessContrast *self = GIMP_OPERATION_METAL_BRIGHTNESS_CONTRAST (operation);

#ifdef HAVE_METAL
  /* Try Metal acceleration first */
  if (gimp_gegl_metal_brightness_contrast (input, result, output, result,
                                          self->brightness, self->contrast))
    return TRUE;
#endif

  /* Fallback to CPU implementation */
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
            out[0] = CLAMP ((in[0] + self->brightness - 0.5f) * self->contrast + 0.5f, 0.0f, 1.0f);
            out[1] = CLAMP ((in[1] + self->brightness - 0.5f) * self->contrast + 0.5f, 0.0f, 1.0f);
            out[2] = CLAMP ((in[2] + self->brightness - 0.5f) * self->contrast + 0.5f, 0.0f, 1.0f);
            out[3] = in[3];

            in  += 4;
            out += 4;
          }
      }
  }

  return TRUE;
}
