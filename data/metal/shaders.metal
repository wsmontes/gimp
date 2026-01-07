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

// Display rendering shader - simple passthrough for canvas display
kernel void gimp_display_render_shader(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) {
        return;
    }

    float4 color = input.read(gid);
    color = clamp(color, 0.0, 1.0);
    output.write(color, gid);
}

// Hue-Saturation shader - HSL color manipulation
kernel void gimp_hue_saturation_shader(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float &hue_offset [[buffer(0)]],
    constant float &saturation [[buffer(1)]],
    constant float &lightness [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) {
        return;
    }

    float4 color = input.read(gid);

    // RGB to HSL
    float maxc = max(max(color.r, color.g), color.b);
    float minc = min(min(color.r, color.g), color.b);
    float l = (maxc + minc) / 2.0;
    float s = 0.0;
    float h = 0.0;

    if (maxc != minc) {
        float delta = maxc - minc;
        s = l > 0.5 ? delta / (2.0 - maxc - minc) : delta / (maxc + minc);

        if (maxc == color.r) {
            h = (color.g - color.b) / delta + (color.g < color.b ? 6.0 : 0.0);
        } else if (maxc == color.g) {
            h = (color.b - color.r) / delta + 2.0;
        } else {
            h = (color.r - color.g) / delta + 4.0;
        }
        h /= 6.0;
    }

    // Apply adjustments
    h = fract(h + hue_offset);
    s = clamp(s * saturation, 0.0, 1.0);
    l = clamp(l + lightness, 0.0, 1.0);

    // HSL to RGB
    float c = (1.0 - abs(2.0 * l - 1.0)) * s;
    float x = c * (1.0 - abs(fmod(h * 6.0, 2.0) - 1.0));
    float m = l - c / 2.0;

    float3 rgb;
    if (h < 1.0/6.0) {
        rgb = float3(c, x, 0.0);
    } else if (h < 2.0/6.0) {
        rgb = float3(x, c, 0.0);
    } else if (h < 3.0/6.0) {
        rgb = float3(0.0, c, x);
    } else if (h < 4.0/6.0) {
        rgb = float3(0.0, x, c);
    } else if (h < 5.0/6.0) {
        rgb = float3(x, 0.0, c);
    } else {
        rgb = float3(c, 0.0, x);
    }

    color.rgb = rgb + m;
    output.write(color, gid);
}

// Color Temperature shader - warm/cool adjustment
kernel void gimp_color_temperature_shader(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float &temperature [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) {
        return;
    }

    float4 color = input.read(gid);

    // Temperature adjustment
    if (temperature > 0.0) {
        // Warm: increase red, decrease blue
        color.r = clamp(color.r + temperature * 0.5, 0.0, 1.0);
        color.b = clamp(color.b - temperature * 0.3, 0.0, 1.0);
    } else {
        // Cool: decrease red, increase blue
        color.r = clamp(color.r + temperature * 0.3, 0.0, 1.0);
        color.b = clamp(color.b - temperature * 0.5, 0.0, 1.0);
    }

    output.write(color, gid);
}

// Bilinear scale shader - high-quality texture sampling
kernel void gimp_scale_bilinear_shader(
    texture2d<float, access::sample> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float2 &scale_factor [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    constexpr sampler textureSampler(coord::normalized,
                                     address::clamp_to_edge,
                                     filter::linear);

    float2 coord = float2(gid) / float2(output.get_width(), output.get_height());
    float4 color = input.sample(textureSampler, coord);
    output.write(color, gid);
}

// Rotate shader - arbitrary angle rotation with bilinear sampling
kernel void gimp_rotate_shader(
    texture2d<float, access::sample> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float &angle [[buffer(0)]],
    constant float2 &center [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    constexpr sampler textureSampler(coord::normalized,
                                     address::clamp_to_edge,
                                     filter::linear);

    float2 pos = float2(gid) / float2(output.get_width(), output.get_height());
    pos -= center;

    float cosA = cos(angle);
    float sinA = sin(angle);
    float2 rotated = float2(
        pos.x * cosA - pos.y * sinA,
        pos.x * sinA + pos.y * cosA
    );

    rotated += center;

    if (rotated.x >= 0.0 && rotated.x <= 1.0 && rotated.y >= 0.0 && rotated.y <= 1.0) {
        float4 color = input.sample(textureSampler, rotated);
        output.write(color, gid);
    } else {
        output.write(float4(0.0), gid);
    }
}
