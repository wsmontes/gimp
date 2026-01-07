/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-operation-metal-sharpen.h
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

#ifndef __GIMP_OPERATION_METAL_SHARPEN_H__
#define __GIMP_OPERATION_METAL_SHARPEN_H__


#include <gegl-plugin.h>


#define GIMP_TYPE_OPERATION_METAL_SHARPEN            (gimp_operation_metal_sharpen_get_type ())
#define GIMP_OPERATION_METAL_SHARPEN(obj)            (G_TYPE_CHECK_INSTANCE_CAST ((obj), GIMP_TYPE_OPERATION_METAL_SHARPEN, GimpOperationMetalSharpen))
#define GIMP_OPERATION_METAL_SHARPEN_CLASS(klass)    (G_TYPE_CHECK_CLASS_CAST ((klass),  GIMP_TYPE_OPERATION_METAL_SHARPEN, GimpOperationMetalSharpenClass))
#define GIMP_IS_OPERATION_METAL_SHARPEN(obj)         (G_TYPE_CHECK_INSTANCE_TYPE ((obj), GIMP_TYPE_OPERATION_METAL_SHARPEN))
#define GIMP_IS_OPERATION_METAL_SHARPEN_CLASS(klass) (G_TYPE_CHECK_CLASS_TYPE ((klass),  GIMP_TYPE_OPERATION_METAL_SHARPEN))
#define GIMP_OPERATION_METAL_SHARPEN_GET_CLASS(obj)  (G_TYPE_INSTANCE_GET_CLASS ((obj),  GIMP_TYPE_OPERATION_METAL_SHARPEN, GimpOperationMetalSharpenClass))


typedef struct _GimpOperationMetalSharpen      GimpOperationMetalSharpen;
typedef struct _GimpOperationMetalSharpenClass GimpOperationMetalSharpenClass;

struct _GimpOperationMetalSharpen
{
  GeglOperationFilter  parent_instance;

  gdouble              amount;
};

struct _GimpOperationMetalSharpenClass
{
  GeglOperationFilterClass  parent_class;
};


GType   gimp_operation_metal_sharpen_get_type (void) G_GNUC_CONST;


#endif /* __GIMP_OPERATION_METAL_SHARPEN_H__ */
