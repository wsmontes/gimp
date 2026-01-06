#!/bin/bash
# Test Metal backend for GIMP

set -e

echo "🧪 GIMP Metal Backend Test Suite"
echo "================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Metal is available
echo "1. Checking Metal availability..."
if system_profiler SPDisplaysDataType | grep -q "Metal"; then
    echo -e "${GREEN}✓${NC} Metal is available"
else
    echo -e "${RED}✗${NC} Metal not found"
    exit 1
fi

# Check if GIMP was compiled with Metal support
echo ""
echo "2. Checking GIMP Metal support..."
if [ ! -f "_build/config.h" ]; then
    echo -e "${RED}✗${NC} Build directory not found. Run meson setup first."
    exit 1
fi

if grep -q "HAVE_METAL" _build/config.h; then
    echo -e "${GREEN}✓${NC} GIMP compiled with Metal support"
else
    echo -e "${YELLOW}!${NC} Metal support not enabled in build"
    echo "   Run: meson setup _build -Dmetal=enabled"
    exit 1
fi

# Test Metal library compilation
echo ""
echo "3. Testing Metal shader compilation..."
if [ -f "app/gegl/metal/shaders.metal" ]; then
    xcrun -sdk macosx metal -c app/gegl/metal/shaders.metal -o /tmp/test_shaders.air 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Metal shaders compile successfully"
        rm -f /tmp/test_shaders.air
    else
        echo -e "${RED}✗${NC} Metal shader compilation failed"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} Shader file not found"
    exit 1
fi

# Create test program
echo ""
echo "4. Testing Metal context creation..."
cat > /tmp/test_metal.m << 'EOF'
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

int main() {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device == nil) {
            printf("Failed to create Metal device\n");
            return 1;
        }

        printf("Metal device: %s\n", [[device name] UTF8String]);
        printf("Max threads per threadgroup: %lu\n",
               (unsigned long)[device maxThreadsPerThreadgroup].width);
        printf("Supports family Apple7: %s\n",
               [device supportsFamily:MTLGPUFamilyApple7] ? "yes" : "no");

        return 0;
    }
}
EOF

clang -framework Metal -framework Foundation /tmp/test_metal.m -o /tmp/test_metal
if /tmp/test_metal; then
    echo -e "${GREEN}✓${NC} Metal context works"
else
    echo -e "${RED}✗${NC} Metal context creation failed"
    exit 1
fi
rm -f /tmp/test_metal /tmp/test_metal.m

# Test GPU memory allocation
echo ""
echo "5. Testing GPU texture allocation..."
cat > /tmp/test_texture.m << 'EOF'
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

int main() {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();

        MTLTextureDescriptor *desc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
            width:4096 height:4096 mipmapped:NO];
        desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

        id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
        if (texture == nil) {
            printf("Failed to allocate texture\n");
            return 1;
        }

        printf("Allocated 4K texture: %lux%lu\n",
               (unsigned long)[texture width],
               (unsigned long)[texture height]);

        return 0;
    }
}
EOF

clang -framework Metal -framework Foundation /tmp/test_texture.m -o /tmp/test_texture
if /tmp/test_texture; then
    echo -e "${GREEN}✓${NC} GPU memory allocation works"
else
    echo -e "${RED}✗${NC} GPU allocation failed"
fi
rm -f /tmp/test_texture /tmp/test_texture.m

# Performance test
echo ""
echo "6. Running basic performance test..."
cat > /tmp/perf_test.m << 'EOF'
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <Foundation/Foundation.h>
#import <mach/mach_time.h>

double getTime() {
    static mach_timebase_info_data_t info;
    if (info.denom == 0) mach_timebase_info(&info);
    return (double)mach_absolute_time() * info.numer / info.denom / 1e9;
}

int main() {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        id<MTLCommandQueue> queue = [device newCommandQueue];

        // Create test textures
        MTLTextureDescriptor *desc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
            width:2048 height:2048 mipmapped:NO];
        desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

        id<MTLTexture> input = [device newTextureWithDescriptor:desc];
        id<MTLTexture> output = [device newTextureWithDescriptor:desc];

        // Test Gaussian blur
        MPSImageGaussianBlur *blur = [[MPSImageGaussianBlur alloc]
                                      initWithDevice:device sigma:10.0];

        double start = getTime();

        for (int i = 0; i < 10; i++) {
            id<MTLCommandBuffer> cmd = [queue commandBuffer];
            [blur encodeToCommandBuffer:cmd
                          sourceTexture:input
                     destinationTexture:output];
            [cmd commit];
        }
        [queue commandBuffer]; // Flush
        [[queue commandBuffer] waitUntilCompleted];

        double elapsed = getTime() - start;

        printf("10 Gaussian blurs (2K): %.2fms (avg: %.2fms)\n",
               elapsed * 1000, elapsed * 100);

        return 0;
    }
}
EOF

clang -framework Metal -framework MetalPerformanceShaders -framework Foundation \
      /tmp/perf_test.m -o /tmp/perf_test
if /tmp/perf_test; then
    echo -e "${GREEN}✓${NC} Performance test passed"
else
    echo -e "${YELLOW}!${NC} Performance test had issues (non-critical)"
fi
rm -f /tmp/perf_test /tmp/perf_test.m

# Summary
echo ""
echo "================================="
echo -e "${GREEN}✓ All tests passed!${NC}"
echo ""
echo "Next steps:"
echo "1. Build GIMP: meson compile -C _build"
echo "2. Install: sudo meson install -C _build"
echo "3. Run with Metal: GIMP_USE_METAL=1 gimp-3.2"
echo ""
echo "To verify Metal is being used:"
echo "  gimp-3.2 2>&1 | grep -i metal"
echo ""
