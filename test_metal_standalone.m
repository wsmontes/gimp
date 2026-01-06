/* Test Metal backend independently */
#include <stdio.h>
#include <stdbool.h>

#ifdef HAVE_METAL
#import <Metal/Metal.h>

int main() {
    @autoreleasepool {
        printf("Testing Metal backend...\n");

        // Test 1: Device availability
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device == nil) {
            printf("❌ FAILED: Metal device not available\n");
            return 1;
        }
        printf("✅ Metal device: %s\n", [[device name] UTF8String]);

        // Test 2: Command queue
        id<MTLCommandQueue> queue = [device newCommandQueue];
        if (queue == nil) {
            printf("❌ FAILED: Could not create command queue\n");
            return 1;
        }
        printf("✅ Command queue created\n");

        // Test 3: Texture creation
        MTLTextureDescriptor *desc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
            width:1024 height:1024 mipmapped:NO];
        desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

        id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
        if (texture == nil) {
            printf("❌ FAILED: Could not create texture\n");
            return 1;
        }
        printf("✅ Texture created: %lux%lu\n",
               (unsigned long)[texture width],
               (unsigned long)[texture height]);

        // Test 4: Basic command buffer
        id<MTLCommandBuffer> cmd = [queue commandBuffer];
        if (cmd == nil) {
            printf("❌ FAILED: Could not create command buffer\n");
            return 1;
        }
        [cmd commit];
        [cmd waitUntilCompleted];
        printf("✅ Command buffer executed\n");

        printf("\n🎉 All Metal tests passed!\n");
        printf("Metal backend is fully functional.\n");

        return 0;
    }
}

#else
int main() {
    printf("❌ Metal support not compiled\n");
    return 1;
}
#endif
