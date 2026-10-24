#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D source_image;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_image;

layout(push_constant, std430) uniform PushConstant {
    float bleed_width;
    float bleed_samples;
    float color_offset;
    float strength;

    float i_multiplier;
    float q_multiplier;
    float luma_sharpening;
    float angle;

    float bleed_curve;
    float ghosting_amount;
    float ghosting_offset;
    float _pad0;

    float _p1; float _p2; float _p3; float _p4;
} pc;

vec3 rgb_to_yiq(vec3 c) {
    return vec3(
        dot(c, vec3(0.299, 0.587, 0.114)),
        dot(c, vec3(0.596, -0.274, -0.322)),
        dot(c, vec3(0.211, -0.523, 0.312))
    );
}

vec3 yiq_to_rgb(vec3 c) {
    return vec3(
        dot(c, vec3(1.0, 0.956, 0.621)),
        dot(c, vec3(1.0, -0.272, -0.647)),
        dot(c, vec3(1.0, -1.106, 1.703))
    );
}

vec4 sample_subpixel(ivec2 img_size, vec2 pos) {
    ivec2 p0 = clamp(ivec2(floor(pos)), ivec2(0), img_size - 1);
    ivec2 p1 = clamp(p0 + ivec2(1, 0), ivec2(0), img_size - 1);
    ivec2 p2 = clamp(p0 + ivec2(0, 1), ivec2(0), img_size - 1);
    ivec2 p3 = clamp(p0 + ivec2(1, 1), ivec2(0), img_size - 1);

    vec2 f = fract(pos);

    vec4 c00 = imageLoad(source_image, p0);
    vec4 c10 = imageLoad(source_image, p1);
    vec4 c01 = imageLoad(source_image, p2);
    vec4 c11 = imageLoad(source_image, p3);

    vec4 mx0 = mix(c00, c10, f.x);
    vec4 mx1 = mix(c01, c11, f.x);
    return mix(mx0, mx1, f.y);
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_image);

    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec4 original = imageLoad(source_image, coord);
    vec3 yiq_center = rgb_to_yiq(original.rgb);

    float a = radians(pc.angle);
    vec2 dir = vec2(cos(a), sin(a));

    int samples = max(int(pc.bleed_samples), 1);
    float i_accum = 0.0;
    float q_accum = 0.0;
    float weight_sum = 0.0;

    for (int s = 0; s < samples; s++) {
        float t = float(s) / float(max(samples - 1, 1));

        float w = 1.0;
        if (pc.bleed_curve > 0.5) {
            w = 1.0 - t;
        } else if (pc.bleed_curve > 1.5) {
            w = exp(-t * 3.0);
        }

        float offset = pc.bleed_width * t - pc.color_offset;
        vec2 sample_pos = vec2(coord) - dir * offset;

        vec3 rgb_s = sample_subpixel(img_size, sample_pos).rgb;
        vec3 yiq_s = rgb_to_yiq(rgb_s);

        i_accum += yiq_s.y * w;
        q_accum += yiq_s.z * w;
        weight_sum += w;
    }

    i_accum *= pc.i_multiplier / max(weight_sum, 0.0001);
    q_accum *= pc.q_multiplier / max(weight_sum, 0.0001);

    if (pc.ghosting_amount > 0.001) {
        vec2 ghost_pos = vec2(coord) - dir * pc.ghosting_offset;
        vec3 rgb_ghost = sample_subpixel(img_size, ghost_pos).rgb;
        vec3 yiq_ghost = rgb_to_yiq(rgb_ghost);
        i_accum += yiq_ghost.y * pc.ghosting_amount;
        q_accum += yiq_ghost.z * pc.ghosting_amount;
    }

    float final_y = yiq_center.x;
    if (pc.luma_sharpening > 0.001) {
        float y_left = rgb_to_yiq(sample_subpixel(img_size, vec2(coord) - dir).rgb).x;
        float y_right = rgb_to_yiq(sample_subpixel(img_size, vec2(coord) + dir).rgb).x;
        final_y += (final_y * 2.0 - y_left - y_right) * pc.luma_sharpening;
    }

    vec3 final_yiq = vec3(final_y, mix(yiq_center.y, i_accum, pc.strength), mix(yiq_center.z, q_accum, pc.strength));
    imageStore(dest_image, coord, vec4(yiq_to_rgb(final_yiq), original.a));
}
