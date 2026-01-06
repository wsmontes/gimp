#include <metal_stdlib>
using namespace metal;

// Invert shader
kernel void gimp_invert_shader(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) {
        return;
    }
    
    float4 color = input.read(gid);
    color.rgb = 1.0 - color.rgb;
    output.write(color, gid);
}

// Brightness/Contrast shader
kernel void gimp_brightness_contrast_shader(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float &brightness [[buffer(0)]],
    constant float &contrast [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) {
        return;
    }
    
    float4 color = input.read(gid);
    color.rgb += brightness;
    color.rgb = (color.rgb - 0.5) * contrast + 0.5;
    color.rgb = clamp(color.rgb, 0.0, 1.0);
    output.write(color, gid);
}

// Desaturate shader
kernel void gimp_desaturate_shader(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) {
        return;
    }
    
    float4 color = input.read(gid);
    float luminance = dot(color.rgb, float3(0.21, 0.72, 0.07));
    color.rgb = float3(luminance);
    output.write(color, gid);
}

// Sobel edge detection shader
kernel void gimp_sobel_edge_shader(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) {
        return;
    }
    
    float sobelX[9] = {-1, 0, 1, -2, 0, 2, -1, 0, 1};
    float sobelY[9] = {-1, -2, -1, 0, 0, 0, 1, 2, 1};
    
    int2 offsets[9] = {
        int2(-1, -1), int2(0, -1), int2(1, -1),
        int2(-1,  0), int2(0,  0), int2(1,  0),
        int2(-1,  1), int2(0,  1), int2(1,  1)
    };
    
    float gx = 0.0;
    float gy = 0.0;
    
    for (int i = 0; i < 9; i++) {
        uint2 pos = uint2(int2(gid) + offsets[i]);
        if (pos.x < input.get_width() && pos.y < input.get_height()) {
            float4 sample = input.read(pos);
            float luminance = dot(sample.rgb, float3(0.21, 0.72, 0.07));
            gx += luminance * sobelX[i];
            gy += luminance * sobelY[i];
        }
    }
    
    float magnitude = sqrt(gx * gx + gy * gy);
    float4 color = float4(magnitude, magnitude, magnitude, 1.0);
    output.write(color, gid);
}

// Sharpen shader
kernel void gimp_sharpen_shader(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float &amount [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) {
        return;
    }
    
    float4 result = float4(0.0);
    
    int2 offsets[9] = {
        int2(-1, -1), int2(0, -1), int2(1, -1),
        int2(-1,  0), int2(0,  0), int2(1,  0),
        int2(-1,  1), int2(0,  1), int2(1,  1)
    };
    
    float weights[9] = {
        0.0, -amount, 0.0,
        -amount, 1.0 + 4.0 * amount, -amount,
        0.0, -amount, 0.0
    };
    
    for (int i = 0; i < 9; i++) {
        uint2 pos = uint2(int2(gid) + offsets[i]);
        if (pos.x < input.get_width() && pos.y < input.get_height()) {
            float4 sample = input.read(pos);
            result += sample * weights[i];
        }
    }
    
    result.rgb = clamp(result.rgb, 0.0, 1.0);
    result.a = input.read(gid).a;
    output.write(result, gid);
}
