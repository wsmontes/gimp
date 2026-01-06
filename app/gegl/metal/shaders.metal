//
// GIMP Metal Shaders
// Copyright (C) 2026 GIMP Contributors
//
// Optimized for Metal 3 on Apple Silicon
//

#include <metal_stdlib>
using namespace metal;


// ============================================================================
// Brightness/Contrast Shader (Metal 3 optimized)
// ============================================================================

kernel void brightness_contrast(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant float &brightness [[buffer(0)]],
    constant float &contrast [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= src.get_width() || gid.y >= src.get_height())
        return;

    float4 color = src.read(gid);

    // Apply brightness: color = color + brightness
    color.rgb += brightness;

    // Apply contrast: color = (color - 0.5) * contrast + 0.5
    // Optimized formula avoiding division
    float factor = (1.0 + contrast) / (1.0001 - contrast);
    color.rgb = fma(color.rgb - 0.5, factor, 0.5);

    // Clamp to valid range
    color = clamp(color, 0.0, 1.0);

    dst.write(color, gid);
}


// ============================================================================
// Desaturate Shader
// ============================================================================

kernel void desaturate(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= src.get_width() || gid.y >= src.get_height())
        return;

    float4 color = src.read(gid);

    // Luminance method
    float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));

    color.rgb = float3(gray);

    dst.write(color, gid);
}


// ============================================================================
// Invert Shader
// ============================================================================

kernel void invert(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= src.get_width() || gid.y >= src.get_height())
        return;

    float4 color = src.read(gid);

    color.rgb = 1.0 - color.rgb;

    dst.write(color, gid);
}


// ============================================================================
// Hue/Saturation Shader
// ============================================================================

float3 rgb_to_hsl(float3 rgb)
{
    float maxc = max(max(rgb.r, rgb.g), rgb.b);
    float minc = min(min(rgb.r, rgb.g), rgb.b);
    float delta = maxc - minc;

    float l = (maxc + minc) / 2.0;
    float s = 0.0;
    float h = 0.0;

    if (delta > 0.0001)
    {
        s = delta / (1.0 - abs(2.0 * l - 1.0));

        if (maxc == rgb.r)
            h = fmod((rgb.g - rgb.b) / delta, 6.0);
        else if (maxc == rgb.g)
            h = (rgb.b - rgb.r) / delta + 2.0;
        else
            h = (rgb.r - rgb.g) / delta + 4.0;

        h = h / 6.0;
        if (h < 0.0) h += 1.0;
    }

    return float3(h, s, l);
}

float3 hsl_to_rgb(float3 hsl)
{
    float h = hsl.x;
    float s = hsl.y;
    float l = hsl.z;

    float c = (1.0 - abs(2.0 * l - 1.0)) * s;
    float x = c * (1.0 - abs(fmod(h * 6.0, 2.0) - 1.0));
    float m = l - c / 2.0;

    float3 rgb;

    if (h < 1.0/6.0)
        rgb = float3(c, x, 0.0);
    else if (h < 2.0/6.0)
        rgb = float3(x, c, 0.0);
    else if (h < 3.0/6.0)
        rgb = float3(0.0, c, x);
    else if (h < 4.0/6.0)
        rgb = float3(0.0, x, c);
    else if (h < 5.0/6.0)
        rgb = float3(x, 0.0, c);
    else
        rgb = float3(c, 0.0, x);

    return rgb + m;
}

kernel void hue_saturation(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant float &hue_shift [[buffer(0)]],
    constant float &saturation [[buffer(1)]],
    constant float &lightness [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= src.get_width() || gid.y >= src.get_height())
        return;

    float4 color = src.read(gid);

    float3 hsl = rgb_to_hsl(color.rgb);

    // Adjust hue
    hsl.x = fmod(hsl.x + hue_shift, 1.0);
    if (hsl.x < 0.0) hsl.x += 1.0;

    // Adjust saturation
    hsl.y = clamp(hsl.y * (1.0 + saturation), 0.0, 1.0);

    // Adjust lightness
    hsl.z = clamp(hsl.z + lightness, 0.0, 1.0);

    color.rgb = hsl_to_rgb(hsl);

    dst.write(color, gid);
}


// ============================================================================
// Simple Convolution (3x3 kernel)
// ============================================================================

kernel void convolve_3x3(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant float *kernel [[buffer(0)]],
    constant float &divisor [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height())
        return;

    float4 sum = float4(0.0);

    for (int ky = -1; ky <= 1; ky++)
    {
        for (int kx = -1; kx <= 1; kx++)
        {
            int2 coord = int2(gid) + int2(kx, ky);
            coord = clamp(coord, int2(0), int2(src.get_width() - 1, src.get_height() - 1));

            float4 pixel = src.read(uint2(coord));
            float weight = kernel[(ky + 1) * 3 + (kx + 1)];

            sum += pixel * weight;
        }
    }

    sum /= divisor;
    sum = clamp(sum, 0.0, 1.0);

    dst.write(sum, gid);
}


// ============================================================================
// Threshold
// ============================================================================

kernel void threshold(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant float &low [[buffer(0)]],
    constant float &high [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= src.get_width() || gid.y >= src.get_height())
        return;

    float4 color = src.read(gid);
    float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));

    if (gray >= low && gray <= high)
        color.rgb = float3(1.0);
    else
        color.rgb = float3(0.0);

    dst.write(color, gid);
}
