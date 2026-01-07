/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-operation-metal-color-temperature.h
 */

#ifndef __GIMP_OPERATION_METAL_COLOR_TEMPERATURE_H__
#define __GIMP_OPERATION_METAL_COLOR_TEMPERATURE_H__

#include <gegl-plugin.h>

#define GIMP_TYPE_OPERATION_METAL_COLOR_TEMPERATURE            (gimp_operation_metal_color_temperature_get_type ())
#define GIMP_OPERATION_METAL_COLOR_TEMPERATURE(obj)            (G_TYPE_CHECK_INSTANCE_CAST ((obj), GIMP_TYPE_OPERATION_METAL_COLOR_TEMPERATURE, GimpOperationMetalColorTemperature))
#define GIMP_OPERATION_METAL_COLOR_TEMPERATURE_CLASS(klass)    (G_TYPE_CHECK_CLASS_CAST ((klass),  GIMP_TYPE_OPERATION_METAL_COLOR_TEMPERATURE, GimpOperationMetalColorTemperatureClass))
#define GIMP_IS_OPERATION_METAL_COLOR_TEMPERATURE(obj)         (G_TYPE_CHECK_INSTANCE_TYPE ((obj), GIMP_TYPE_OPERATION_METAL_COLOR_TEMPERATURE))
#define GIMP_IS_OPERATION_METAL_COLOR_TEMPERATURE_CLASS(klass) (G_TYPE_CHECK_CLASS_TYPE ((klass),  GIMP_TYPE_OPERATION_METAL_COLOR_TEMPERATURE))
#define GIMP_OPERATION_METAL_COLOR_TEMPERATURE_GET_CLASS(obj)  (G_TYPE_INSTANCE_GET_CLASS ((obj),  GIMP_TYPE_OPERATION_METAL_COLOR_TEMPERATURE, GimpOperationMetalColorTemperatureClass))


typedef struct _GimpOperationMetalColorTemperature      GimpOperationMetalColorTemperature;
typedef struct _GimpOperationMetalColorTemperatureClass GimpOperationMetalColorTemperatureClass;

struct _GimpOperationMetalColorTemperature
{
  GeglOperationFilter  parent_instance;

  gdouble  temperature;
};

struct _GimpOperationMetalColorTemperatureClass
{
  GeglOperationFilterClass  parent_class;
};


GType   gimp_operation_metal_color_temperature_get_type (void) G_GNUC_CONST;


#endif /* __GIMP_OPERATION_METAL_COLOR_TEMPERATURE_H__ */
