/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-gegl-loops-metal.m
 * Metal-accelerated versions of GEGL operations
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

#ifdef HAVE_METAL

#include <gegl.h>

#include "gimp-gegl-loops.h"
#include "metal/gimp-gegl-metal.h"


static GimpMetalContext *metal_context = NULL;


/**
 * gimp_gegl_init_metal:
 *
 * Initialize Metal backend for GEGL operations
 */
void
gimp_gegl_init_metal (void)
{
  if (metal_context == NULL && gimp_metal_context_is_available())
    {
      metal_context = gimp_metal_context_new();

      if (metal_context != NULL)
        {
          g_message ("GIMP Metal backend initialized: %s",
                     gimp_metal_context_get_device_name (metal_context));
          gimp_gegl_loops_set_use_metal (TRUE);
        }
    }
}


/**
 * gimp_gegl_shutdown_metal:
 *
 * Shutdown Metal backend
 */
void
gimp_gegl_shutdown_metal (void)
{
  if (metal_context != NULL)
    {
      gimp_metal_context_free (metal_context);
      metal_context = NULL;
      gimp_gegl_loops_set_use_metal (FALSE);
    }
}


/**
 * gimp_gegl_metal_blur_gaussian:
 * @src_buffer: Source buffer
 * @src_rect: Source rectangle
 * @dest_buffer: Destination buffer
 * @dest_rect: Destination rectangle
 * @radius_x: Horizontal blur radius
 * @radius_y: Vertical blur radius
 *
 * Metal-accelerated Gaussian blur
 *
 * Returns: TRUE if Metal was used, FALSE to fall back to CPU
 */
gboolean
gimp_gegl_metal_blur_gaussian (GeglBuffer          *src_buffer,
                               const GeglRectangle *src_rect,
                               GeglBuffer          *dest_buffer,
                               const GeglRectangle *dest_rect,
                               gfloat               radius_x,
                               gfloat               radius_y)
{
  GimpMetalBuffer *src_metal = NULL;
  GimpMetalBuffer *dest_metal = NULL;
  gboolean         success = FALSE;

  if (!gimp_gegl_loops_use_metal() || metal_context == NULL)
    return FALSE;

  // Transfer to GPU
  src_metal = gimp_metal_buffer_new_from_gegl (metal_context, src_buffer, src_rect);
  if (src_metal == NULL)
    goto cleanup;

  dest_metal = gimp_metal_buffer_new_from_gegl (metal_context, dest_buffer, dest_rect);
  if (dest_metal == NULL)
    goto cleanup;

  // Execute on GPU
  success = gimp_metal_blur_gaussian (metal_context, src_metal, dest_metal,
                                      radius_x, radius_y);

  if (success)
    {
      // Transfer back to CPU
      GeglBuffer *result = gimp_metal_buffer_to_gegl (dest_metal,
                                                      gegl_buffer_get_format (dest_buffer));
      if (result != NULL)
        {
          gegl_buffer_copy (result, dest_rect, GEGL_ABYSS_NONE,
                           dest_buffer, dest_rect);
          g_object_unref (result);
        }
      else
        {
          success = FALSE;
        }
    }

cleanup:
  if (src_metal != NULL)
    gimp_metal_buffer_free (src_metal);
  if (dest_metal != NULL)
    gimp_metal_buffer_free (dest_metal);

  return success;
}


#endif /* HAVE_METAL */
