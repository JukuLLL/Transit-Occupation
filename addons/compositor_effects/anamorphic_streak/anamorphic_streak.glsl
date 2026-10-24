#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D source_image;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_image;

layout(push_constant, std430) uniform PushConstant {
    float threshold;
    float intensity;
    float streak_length;
    float samples;

    float color_r;
    float color_g;
    float color_b;
    float falloff;

    float angle_deg;
    float chroma_spread;
    float knee_softness;
    float dual_axis;

    float flicker;
    float time;
    float _pad0;
    float _pad1;
} pc;

float soft_threshold(float luma, float threshold, float knee) {
    float knee_width = max(knee, 0.0001);
    float lo = threshold - knee_width * 0.5;
    float hi = threshold + knee_width * 0.5;
    if (luma < lo) return 0.0;
    if (luma > hi) return luma - threshold;
    float t = (luma - lo) / (hi - lo);
    return t * t * (luma - threshold);
}

vec3 sample_along(ivec2 img_size, vec2 origin, vec2 dir, float dist) {
    vec2 pos = origin + dir * dist;
    int x0 = clamp(int(floor(pos.x)), 0, img_size.x - 1);
    int y0 = clamp(int(floor(pos.y)), 0, img_size.y - 1);
    int x1 = clamp(x0 + 1, 0, img_size.x - 1);
    int y1 = clamp(y0 + 1, 0, img_size.y - 1);
    float fx = fract(pos.x);
    float fy = fract(pos.y);
    vec3 c00 = imageLoad(source_image, ivec2(x0, y0)).rgb;
    vec3 c10 = imageLoad(source_image, ivec2(x1, y0)).rgb;
    vec3 c01 = imageLoad(source_image, ivec2(x0, y1)).rgb;
    vec3 c11 = imageLoad(source_image, ivec2(x1, y1)).rgb;
    return mix(mix(c00, c10, fx), mix(c01, c11, fx), fy);
}

vec3 accumulate_streak(ivec2 img_size, vec2 origin, vec2 dir, float step_size, int half_samples) {
    vec3 accum_r = vec3(0.0);
    vec3 accum_g = vec3(0.0);
    vec3 accum_b = vec3(0.0);

    float chroma = pc.chroma_spread;

    for (int i = 1; i <= half_samples; i++) {
        float t = float(i) / float(half_samples);
        float weight = pow(1.0 - t, pc.falloff);
        float base_dist = float(i) * step_size;

        vec3 col_fwd_r = sample_along(img_size, origin, dir, base_dist * (1.0 - chroma));
        vec3 col_fwd_g = sample_along(img_size, origin, dir, base_dist);
        vec3 col_fwd_b = sample_along(img_size, origin, dir, base_dist * (1.0 + chroma));

        float luma_r = max(col_fwd_r.r, max(col_fwd_r.g, col_fwd_r.b));
        float luma_g = max(col_fwd_g.r, max(col_fwd_g.g, col_fwd_g.b));
        float luma_b = max(col_fwd_b.r, max(col_fwd_b.g, col_fwd_b.b));

        float h_r = soft_threshold(luma_r, pc.threshold, pc.knee_softness);
        float h_g = soft_threshold(luma_g, pc.threshold, pc.knee_softness);
        float h_b = soft_threshold(luma_b, pc.threshold, pc.knee_softness);

        if (h_r > 0.0) accum_r += col_fwd_r * (h_r / max(luma_r, 0.0001)) * weight;
        if (h_g > 0.0) accum_g += col_fwd_g * (h_g / max(luma_g, 0.0001)) * weight;
        if (h_b > 0.0) accum_b += col_fwd_b * (h_b / max(luma_b, 0.0001)) * weight;

        vec3 col_bck_r = sample_along(img_size, origin, dir, -base_dist * (1.0 - chroma));
        vec3 col_bck_g = sample_along(img_size, origin, dir, -base_dist);
        vec3 col_bck_b = sample_along(img_size, origin, dir, -base_dist * (1.0 + chroma));

        float luma_br = max(col_bck_r.r, max(col_bck_r.g, col_bck_r.b));
        float luma_bg = max(col_bck_g.r, max(col_bck_g.g, col_bck_g.b));
        float luma_bb = max(col_bck_b.r, max(col_bck_b.g, col_bck_b.b));

        float h_br = soft_threshold(luma_br, pc.threshold, pc.knee_softness);
        float h_bg = soft_threshold(luma_bg, pc.threshold, pc.knee_softness);
        float h_bb = soft_threshold(luma_bb, pc.threshold, pc.knee_softness);

        if (h_br > 0.0) accum_r += col_bck_r * (h_br / max(luma_br, 0.0001)) * weight;
        if (h_bg > 0.0) accum_g += col_bck_g * (h_bg / max(luma_bg, 0.0001)) * weight;
        if (h_bb > 0.0) accum_b += col_bck_b * (h_bb / max(luma_bb, 0.0001)) * weight;
    }

    return vec3(accum_r.r, accum_g.g, accum_b.b) * step_size;
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_image);

    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec4 original = imageLoad(source_image, coord);

    int half_samples = max(int(pc.samples), 1);
    float step_size = max(pc.streak_length / float(half_samples), 0.0);

    float rad = pc.angle_deg * (3.14159265 / 180.0);
    vec2 dir_primary = vec2(cos(rad), sin(rad));
    vec2 dir_secondary = vec2(-sin(rad), cos(rad));

    vec2 origin = vec2(float(coord.x), float(coord.y));

    vec3 streak = accumulate_streak(img_size, origin, dir_primary, step_size, half_samples);

    if (pc.dual_axis > 0.5) {
        streak += accumulate_streak(img_size, origin, dir_secondary, step_size, half_samples);
        streak *= 0.5;
    }

    vec3 tint = vec3(pc.color_r, pc.color_g, pc.color_b);
    float flicker_scale = 1.0 + pc.flicker * (fract(sin(pc.time * 123.456 + float(coord.y) * 0.01) * 43758.5) - 0.5) * 2.0;

    vec3 final_streak = streak * tint * pc.intensity * 0.05 * flicker_scale;

    imageStore(dest_image, coord, vec4(original.rgb + final_streak, original.a));
}
