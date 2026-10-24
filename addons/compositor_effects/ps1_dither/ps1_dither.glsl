#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;

layout(push_constant, std430) uniform PushConstant {
    float color_depth;
    float dither_strength;
    float dither_scale;
    float color_space_mode;

    float strength;
    float gamma;
    float chroma_depth;
    float saturation;

    float brightness_offset;
    float scanline_mode;
    float scanline_strength;
    float scanline_frequency;

    float _pad0;
    float _pad1;
    float _pad2;
    float _pad3;
} pc;

float get_bayer4(ivec2 coord) {
    int x = coord.x & 3;
    int y = coord.y & 3;
    const float bayer[16] = float[16](
         0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
        12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0,
         3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
        15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0
    );
    return bayer[y * 4 + x] - 0.5;
}

float get_bayer8(ivec2 coord) {
    int x = coord.x & 7;
    int y = coord.y & 7;
    const float bayer[64] = float[64](
         0.0, 32.0,  8.0, 40.0,  2.0, 34.0, 10.0, 42.0,
        48.0, 16.0, 56.0, 24.0, 50.0, 18.0, 58.0, 26.0,
        12.0, 44.0,  4.0, 36.0, 14.0, 46.0,  6.0, 38.0,
        60.0, 28.0, 52.0, 20.0, 62.0, 30.0, 54.0, 22.0,
         3.0, 35.0, 11.0, 43.0,  1.0, 33.0,  9.0, 41.0,
        51.0, 19.0, 59.0, 27.0, 49.0, 17.0, 57.0, 25.0,
        15.0, 47.0,  7.0, 39.0, 13.0, 45.0,  5.0, 37.0,
        63.0, 31.0, 55.0, 23.0, 61.0, 29.0, 53.0, 21.0
    );
    return bayer[y * 8 + x] / 64.0 - 0.5;
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(source_img);
    if (coord.x >= size.x || coord.y >= size.y) return;

    vec4 original = imageLoad(source_img, coord);
    vec3 color = original.rgb;

    float g = max(pc.gamma, 0.01);
    color = pow(max(color, vec3(0.0)), vec3(1.0 / g));
    color += vec3(pc.brightness_offset);

    ivec2 dither_coord = ivec2(vec2(coord) / max(pc.dither_scale, 0.001));
    float dither_value;
    if (pc.dither_scale > 3.5) {
        dither_value = get_bayer8(dither_coord);
    } else {
        dither_value = get_bayer4(dither_coord);
    }

    float cd = max(pc.color_depth, 1.0);
    float chroma_cd = max(pc.chroma_depth, 1.0);

    color += vec3(dither_value * pc.dither_strength * (1.0 / cd));

    int mode = int(pc.color_space_mode);
    if (mode == 1) {
        float y = dot(color, vec3(0.299, 0.587, 0.114));
        float u = 0.492 * (color.b - y);
        float v = 0.877 * (color.r - y);
        y = floor(y * cd + 0.5) / cd;
        u = floor(u * chroma_cd + 0.5) / chroma_cd;
        v = floor(v * chroma_cd + 0.5) / chroma_cd;
        color.r = y + 1.13983 * v;
        color.g = y - 0.39465 * u - 0.58060 * v;
        color.b = y + 2.03211 * u;
    } else if (mode == 2) {
        float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
        color = vec3(floor(luma * cd + 0.5) / cd);
    } else {
        color = floor(color * cd + 0.5) / cd;
    }

    color = pow(max(color, vec3(0.0)), vec3(g));

    if (pc.saturation != 1.0) {
        float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
        color = mix(vec3(luma), color, pc.saturation);
    }

    if (pc.scanline_mode > 0.5) {
        float freq = max(pc.scanline_frequency, 1.0);
        float scanline;
        if (pc.scanline_mode > 1.5) {
            scanline = step(0.5, fract(float(coord.y) / freq));
        } else {
            scanline = 0.5 + 0.5 * cos(float(coord.y) * 3.14159265 / freq);
        }
        color *= 1.0 - pc.scanline_strength * (1.0 - scanline);
    }

    vec3 result = mix(original.rgb, color, pc.strength);
    imageStore(dest_img, coord, vec4(result, original.a));
}
