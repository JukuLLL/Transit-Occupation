#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D source_image;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_image;

layout(push_constant, std430) uniform PushConstant {
    float strength;
    float samples;
    float red_offset;
    float green_offset;

    float blue_offset;
    float falloff_power;
    float barrel_distortion;
    float center_x;

    float center_y;
    float lateral_mode;
    float lateral_angle;
    float inner_radius;

    float fringe_r;
    float fringe_g;
    float fringe_b;
    float _pad0;
} pc;

vec4 image_sample_bilinear(ivec2 img_size, vec2 coord) {
    vec2 f = fract(coord - 0.5);
    ivec2 base = ivec2(floor(coord - 0.5));
    ivec2 c00 = clamp(base,              ivec2(0), img_size - 1);
    ivec2 c10 = clamp(base + ivec2(1,0), ivec2(0), img_size - 1);
    ivec2 c01 = clamp(base + ivec2(0,1), ivec2(0), img_size - 1);
    ivec2 c11 = clamp(base + ivec2(1,1), ivec2(0), img_size - 1);
    vec4 top    = mix(imageLoad(source_image, c00), imageLoad(source_image, c10), f.x);
    vec4 bottom = mix(imageLoad(source_image, c01), imageLoad(source_image, c11), f.x);
    return mix(top, bottom, f.y);
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_image);

    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec2 uv = (vec2(coord) + 0.5) / vec2(img_size);
    vec2 center = vec2(pc.center_x, pc.center_y);
    vec2 delta = uv - center;

    float dist = length(delta);
    vec2 radial_dir = (dist > 0.00001) ? normalize(delta) : vec2(0.0);

    float inner = clamp(pc.inner_radius, 0.0, 0.9999);
    float radial_t = max(dist - inner, 0.0) / max(1.0 - inner, 0.0001);
    float falloff = pow(radial_t * 2.0, pc.falloff_power);
    float barrel = 1.0 + pc.barrel_distortion * dist * dist;
    float base_offset = pc.strength * falloff * barrel;

    vec2 dir;
    if (pc.lateral_mode > 0.5) {
        float rad = pc.lateral_angle * (3.14159265 / 180.0);
        dir = vec2(cos(rad), sin(rad));
    } else {
        dir = radial_dir;
    }

    float r_off = base_offset * pc.red_offset;
    float g_off = base_offset * pc.green_offset;
    float b_off = base_offset * pc.blue_offset;

    int sample_count = max(int(pc.samples), 1);
    float inv_samples = 1.0 / float(sample_count);
    vec2 pixel_coord = vec2(coord) + 0.5;

    float r_accum = 0.0;
    float g_accum = 0.0;
    float b_accum = 0.0;

    for (int i = 0; i < sample_count; i++) {
        float t = (float(i) + 0.5) * inv_samples;
        vec2 r_coord = pixel_coord + dir * r_off * t;
        vec2 g_coord = pixel_coord + dir * g_off * t;
        vec2 b_coord = pixel_coord + dir * b_off * t;
        r_accum += image_sample_bilinear(img_size, r_coord).r;
        g_accum += image_sample_bilinear(img_size, g_coord).g;
        b_accum += image_sample_bilinear(img_size, b_coord).b;
    }

    r_accum *= inv_samples;
    g_accum *= inv_samples;
    b_accum *= inv_samples;

    vec3 fringe = vec3(pc.fringe_r, pc.fringe_g, pc.fringe_b);
    vec3 result = vec3(r_accum, g_accum, b_accum) * fringe;

    vec4 original = imageLoad(source_image, coord);
    imageStore(dest_image, coord, vec4(result, original.a));
}
