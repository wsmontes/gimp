/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-operation-metal-gaussian-blur.h
 */

#ifndef __GIMP_OPERATION_METAL_GAUSSIAN_BLUR_H__
#define __GIMP_OPERATION_METAL_GAUSSIAN_BLUR_H__

#include <gegl-plugin.h>

G_BEGIN_DECLS

#define GIMP_TYPE_OPERATION_METAL_GAUSSIAN_BLUR            (gimp_operation_metal_gaussian_blur_get_type ())
#define GIMP_OPERATION_METAL_GAUSSIAN_BLUR(obj)            (G_TYPE_CHECK_INSTANCE_CAST ((obj), GIMP_TYPE_OPERATION_METAL_GAUSSIAN_BLUR, GimpOperationMetalGaussianBlur))
#define GIMP_OPERATION_METAL_GAUSSIAN_BLUR_CLASS(klass)    (G_TYPE_CHECK_CLASS_CAST ((klass),  GIMP_TYPE_OPERATION_METAL_GAUSSIAN_BLUR, GimpOperationMetalGaussianBlurClass))
#define GIMP_IS_OPERATION_METAL_GAUSSIAN_BLUR(obj)         (G_TYPE_CHECK_INSTANCE_TYPE ((obj), GIMP_TYPE_OPERATION_METAL_GAUSSIAN_BLUR))
#define GIMP_IS_OPERATION_METAL_GAUSSIAN_BLUR_CLASS(klass) (G_TYPE_CHECK_CLASS_TYPE ((klass),  GIMP_TYPE_OPERATION_METAL_GAUSSIAN_BLUR))
#define GIMP_OPERATION_METAL_GAUSSIAN_BLUR_GET_CLASS(obj)  (G_TYPE_INSTANCE_GET_CLASS ((obj),  GIMP_TYPE_OPERATION_METAL_GAUSSIAN_BLUR, GimpOperationMetalGaussianBlurClass))

typedef struct _GimpOperationMetalGaussianBlur      GimpOperationMetalGaussianBlur;
typedef struct _GimpOperationMetalGaussianBlurClass GimpOperationMetalGaussianBlurClass;

struct _GimpOperationMetalGaussianBlur
{
  GeglOperationFilter  parent_instance;

  gdouble              std_dev_x;
  gdouble              std_dev_y;
  gchar               *filter;
  gint                 abyss_policy;
};

struct _GimpOperationMetalGaussianBlurClass
{
  GeglOperationFilterClass  parent_class;
};

GType   gimp_operation_metal_gaussian_blur_get_type (void) G_GNUC_CONST;

G_END_DECLS

#endif /* __GIMP_OPERATION_METAL_GAUSSIAN_BLUR_H__ */
