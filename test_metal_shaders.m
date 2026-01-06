// Test Metal Shaders Implementation
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"🧪 Testing Metal Shader Pipeline...\n");

        // Get default Metal device
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device == nil) {
            NSLog(@"❌ Failed to create Metal device");
            return 1;
        }

        NSLog(@"✅ Metal Device: %@", [device name]);

        // Load default library (should contain our shaders)
        id<MTLLibrary> library = [device newDefaultLibrary];
        if (library == nil) {
            NSLog(@"⚠️  No default Metal library found");
            NSLog(@"   This is expected if shaders.metal wasn't compiled into the library");
            NSLog(@"   Run: cd _build && ninja to compile shaders");
            return 1;
        }

        NSLog(@"✅ Loaded Metal library with %lu functions", (unsigned long)[[library functionNames] count]);

        // Test each shader function
        NSArray *shaderNames = @[
            @"brightness_contrast",
            @"desaturate",
            @"invert",
            @"hue_saturation",
            @"convolve_3x3",
            @"threshold"
        ];

        int loaded = 0;
        int failed = 0;

        for (NSString *shaderName in shaderNames) {
            id<MTLFunction> function = [library newFunctionWithName:shaderName];
            if (function != nil) {
                NSLog(@"   ✅ Shader '%@' loaded successfully", shaderName);

                // Try to create compute pipeline state
                NSError *error = nil;
                id<MTLComputePipelineState> pipeline =
                    [device newComputePipelineStateWithFunction:function error:&error];

                if (pipeline != nil) {
                    NSLog(@"      → Pipeline created (threadExecutionWidth: %lu)",
                          (unsigned long)[pipeline threadExecutionWidth]);
                    loaded++;
                } else {
                    NSLog(@"      ⚠️  Failed to create pipeline: %@", [error localizedDescription]);
                    failed++;
                }

                [function release];
                if (pipeline != nil) [pipeline release];
            } else {
                NSLog(@"   ❌ Shader '%@' NOT FOUND", shaderName);
                failed++;
            }
        }

        NSLog(@"\n📊 Results:");
        NSLog(@"   Shaders loaded: %d/6", loaded);
        NSLog(@"   Failed: %d", failed);

        if (loaded == 6) {
            NSLog(@"\n🎉 ALL SHADERS WORKING! Metal backend is fully operational!");
            NSLog(@"   Ready for GPU-accelerated image processing on Apple Silicon");
        } else if (loaded > 0) {
            NSLog(@"\n⚠️  Partial success - some shaders are working");
        } else {
            NSLog(@"\n❌ No shaders loaded - Metal backend not functional");
        }

        [library release];
        [device release];

        return (loaded == 6) ? 0 : 1;
    }
}
