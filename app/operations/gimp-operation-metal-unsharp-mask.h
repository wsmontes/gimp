/* GIMP - The GNU Image Manipulation Program
 * Copyright (C) 2026 GIMP Contributors
 *
 * gimp-operation-metal-unsharp-mask.h
 */

#ifndef __GIMP_OPERATION_METAL_UNSHARP_MASK_H__
#define __GIMP_OPERATION_METAL_UNSHARP_MASK_H__

#include <gegl-plugin.h>

G_BEGIN_DECLS

#define GIMP_TYPE_OPERATION_METAL_UNSHARP_MASK            (gimp_operation_metal_unsharp_mask_get_type ())
#define GIMP_OPERATION_METAL_UNSHARP_MASK(obj)            (G_TYPE_CHECK_INSTANCE_CAST ((obj), GIMP_TYPE_OPERATION_METAL_UNSHARP_MASK, GimpOperationMetalUnsharpMask))
#define GIMP_OPERATION_METAL_UNSHARP_MASK_CLASS(klass)    (G_TYPE_CHECK_CLASS_CAST ((klass),  GIMP_TYPE_OPERATION_METAL_UNSHARP_MASK, GimpOperationMetalUnsharpMaskClass))
#define GIMP_IS_OPERATION_METAL_UNSHARP_MASK(obj)         (G_TYPE_CHECK_INSTANCE_TYPE ((obj), GIMP_TYPE_OPERATION_METAL_UNSHARP_MASK))
#define GIMP_IS_OPERATION_METAL_UNSHARP_MASK_CLASS(klass) (G_TYPE_CHECK_CLASS_TYPE ((klass),  GIMP_TYPE_OPERATION_METAL_UNSHARP_MASK))
#define GIMP_OPERATION_METAL_UNSHARP_MASK_GET_CLASS(obj)  (G_TYPE_INSTANCE_GET_CLASS ((obj),  GIMP_TYPE_OPERATION_METAL_UNSHARP_MASK, GimpOperationMetalUnsharpMaskClass))

typedef struct _GimpOperationMetalUnsharpMask      GimpOperationMetalUnsharpMask;
typedef struct _GimpOperationMetalUnsharpMaskClass GimpOperationMetalUnsharpMaskClass;

struct _GimpOperationMetalUnsharpMask
{
  GeglOperationFilter  parent_instance;

  gdouble              std_dev;
  gdouble              scale;
  gdouble              threshold;
};

struct _GimpOperationMetalUnsharpMaskClass
{
  GeglOperationFilterClass  parent_class;
};

GType   gimp_operation_metal_unsharp_mask_get_type (void) G_GNUC_CONST;

G_END_DECLS

#endif /* __GIMP_OPERATION_METAL_UNSHARP_MASK_H__ */
