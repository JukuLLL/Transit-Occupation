#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly  image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;
layout(set = 2, binding = 0) uniform sampler2D depth_tex;
layout(set = 3, binding = 0) uniform sampler2D normal_tex;

layout(std140, set = 4, binding = 0) uniform CameraData {
    mat4 inv_projection;
    mat4 inv_view;
} cam;

layout(push_constant, std430) uniform PushConstant {
    float screen_width;
    float screen_height;
    float color_levels;
    float strength;
    float dither_intensity;
    float world_scale;
    float gamma;
    float saturation_boost;

    float dither_pattern;
    float color_mode;
    float posterize_strength;
    float _pad0;

    float _p1; float _p2; float _p3; float _p4;
} pc;

float bayer8x8(ivec2 c) {
    int x = c.x & 7;
    int y = c.y & 7;
    const float m[64] = float[64](
         0.0/64.0, 32.0/64.0,  8.0/64.0, 40.0/64.0,  2.0/64.0, 34.0/64.0, 10.0/64.0, 42.0/64.0,
        48.0/64.0, 16.0/64.0, 56.0/64.0, 24.0/64.0, 50.0/64.0, 18.0/64.0, 58.0/64.0, 26.0/64.0,
        12.0/64.0, 44.0/64.0,  4.0/64.0, 36.0/64.0, 14.0/64.0, 46.0/64.0,  6.0/64.0, 38.0/64.0,
        60.0/64.0, 28.0/64.0, 52.0/64.0, 20.0/64.0, 62.0/64.0, 30.0/64.0, 54.0/64.0, 22.0/64.0,
         3.0/64.0, 35.0/64.0, 11.0/64.0, 43.0/64.0,  1.0/64.0, 33.0/64.0,  9.0/64.0, 41.0/64.0,
        51.0/64.0, 19.0/64.0, 59.0/64.0, 27.0/64.0, 49.0/64.0, 17.0/64.0, 57.0/64.0, 25.0/64.0,
        15.0/64.0, 47.0/64.0,  7.0/64.0, 39.0/64.0, 13.0/64.0, 45.0/64.0,  5.0/64.0, 37.0/64.0,
        63.0/64.0, 31.0/64.0, 55.0/64.0, 23.0/64.0, 61.0/64.0, 29.0/64.0, 53.0/64.0, 21.0/64.0
    );
    return m[y * 8 + x] - 0.5;
}

float bayer4x4(ivec2 c) {
    int x = c.x & 3;
    int y = c.y & 3;
    const float m[16] = float[16](
        0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
       12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0,
        3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
       15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0
    );
    return m[y * 4 + x] - 0.5;
}

float ign(ivec2 p) {
    vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(vec2(p), magic.xy))) - 0.5;
}

float get_dither_val(ivec2 c) {
    if (pc.dither_pattern < 0.5) return bayer8x8(c);
    if (pc.dither_pattern < 1.5) return bayer4x4(c);
    return ign(c);
}

vec3 reconstruct_world_pos(vec2 uv, float depth_raw) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, depth_raw, 1.0);
    vec4 view_pos = cam.inv_projection * ndc;
    view_pos /= view_pos.w;
    vec4 world_pos = cam.inv_view * view_pos;
    return world_pos.xyz;
}

vec3 decode_normal_to_world(vec3 view_normal) {
    mat3 view_to_world = mat3(cam.inv_view);
    return normalize(view_to_world * view_normal);
}

float volumetric_dither(vec3 world_pos, vec3 world_normal, float scale) {
    vec3 sp = world_pos / max(scale, 0.001);
    vec3 an = abs(world_normal);
    ivec2 bayer_coord;

    float scale8 = 8.0;
    if (pc.dither_pattern > 0.5 && pc.dither_pattern < 1.5) scale8 = 4.0;

    if (an.z >= an.x && an.z >= an.y) {
        bayer_coord = ivec2(floor(sp.xy * scale8));
    } else if (an.y >= an.x) {
        bayer_coord = ivec2(floor(sp.xz * scale8));
    } else {
        bayer_coord = ivec2(floor(sp.yz * scale8));
    }

    float base_val = get_dither_val(bayer_coord);

    vec3 cell = floor(sp * scale8);
    const float a1 = 0.8191725134;
    const float a2 = 0.6710436067;
    const float a3 = 0.5497004779;
    float r3_val = fract(cell.x * a1 + cell.y * a2 + cell.z * a3) - 0.5;

    float dominance = max(an.x, max(an.y, an.z));
    float bayer_weight = smoothstep(0.6, 0.85, dominance);

    if (pc.dither_pattern > 1.5) bayer_weight = 1.0;

    return mix(r3_val, base_val, bayer_weight);
}

float quantize(float value, float n, float dither_offset) {
    float clamped = clamp(value, 0.0, 1.0);
    float shifted = clamped + dither_offset / n;
    shifted = clamp(shifted, 0.0, 1.0);
    return floor(shifted * n + 0.5) / n;
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_img);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec4 original = imageLoad(source_img, coord);
    vec3 color = original.rgb;

    if (pc.color_mode > 0.5) {
        float l = dot(color, vec3(0.2126, 0.7152, 0.0722));
        color = vec3(l);
    }

    vec2 uv = (vec2(coord) + 0.5) / vec2(pc.screen_width, pc.screen_height);
    float depth_raw = texelFetch(depth_tex, coord, 0).r;
    vec3 view_normal = texelFetch(normal_tex, coord, 0).xyz * 2.0 - 1.0;

    vec3 world_pos = reconstruct_world_pos(uv, depth_raw);
    vec3 world_normal = decode_normal_to_world(view_normal);

    float dither;
    if (depth_raw > 0.9999) {
        dither = get_dither_val(coord) * pc.dither_intensity;
    } else {
        dither = volumetric_dither(world_pos, world_normal, pc.world_scale) * pc.dither_intensity;
    }

    float g = max(pc.gamma, 0.01);
    vec3 gamma_corrected = pow(max(color, vec3(0.0)), vec3(1.0 / g));

    float n = max(pc.color_levels, 2.0);
    vec3 posterized;
    if (pc.color_mode > 0.5) {
        float ql = quantize(gamma_corrected.r, n, dither);
        posterized = vec3(ql);
    } else {
        posterized.r = quantize(gamma_corrected.r, n, dither);
        posterized.g = quantize(gamma_corrected.g, n, dither);
        posterized.b = quantize(gamma_corrected.b, n, dither);
    }

    posterized = pow(max(posterized, vec3(0.0)), vec3(g));

    if (pc.saturation_boost > 0.001 && pc.color_mode < 0.5) {
        float luma = dot(posterized, vec3(0.299, 0.587, 0.114));
        posterized = mix(vec3(luma), posterized, pc.saturation_boost);
    }

    posterized = mix(color + (dither / n), posterized, pc.posterize_strength);

    vec3 result = mix(original.rgb, posterized, pc.strength);
    imageStore(dest_img, coord, vec4(result, original.a));
}
