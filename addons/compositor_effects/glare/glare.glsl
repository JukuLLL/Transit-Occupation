#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D source_image;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_image;

layout(push_constant, std430) uniform PushConstant {
    float threshold;
    float intensity;
    float glare_size;
    float samples;

    float ray_count;
    float base_angle;
    float color_r;
    float color_g;

    float color_b;
    float falloff;
    float knee;
    float chroma_shift;

    float rotation_speed;
    float time;
    float blend_mode;
    float asymmetry;
} pc;

vec3 sample_bilinear(ivec2 img_size, vec2 pos) {
    vec2 cpos = clamp(pos, vec2(0.0), vec2(img_size) - 1.0);
    ivec2 base = ivec2(floor(cpos - 0.5));
    vec2 f = fract(cpos - 0.5);
    ivec2 c00 = clamp(base, ivec2(0), img_size - 1);
    ivec2 c10 = clamp(base + ivec2(1, 0), ivec2(0), img_size - 1);
    ivec2 c01 = clamp(base + ivec2(0, 1), ivec2(0), img_size - 1);
    ivec2 c11 = clamp(base + ivec2(1, 1), ivec2(0), img_size - 1);
    return mix(
        mix(imageLoad(source_image, c00).rgb, imageLoad(source_image, c10).rgb, f.x),
        mix(imageLoad(source_image, c01).rgb, imageLoad(source_image, c11).rgb, f.x),
        f.y
    );
}

float soft_threshold(float luma, float thr, float kn) {
    float k = max(kn, 0.0001);
    float lo = thr - k * 0.5;
    float hi = thr + k * 0.5;
    if (luma < lo) return 0.0;
    if (luma > hi) return luma - thr;
    float t = (luma - lo) / (hi - lo);
    return t * t * (luma - thr);
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_image);

    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec4 original = imageLoad(source_image, coord);

    int rays = max(int(pc.ray_count), 1);
    float angle_step = 3.14159265 / float(rays);
    int half_samples = max(int(pc.samples), 1);
    float step_size = max(pc.glare_size / float(half_samples), 0.0);

    float animated_angle = pc.base_angle + pc.time * pc.rotation_speed;

    vec3 glare_accum = vec3(0.0);

    for (int r = 0; r < rays; r++) {
        float ray_angle = animated_angle + float(r) * angle_step;
        vec2 dir = vec2(cos(ray_angle), -sin(ray_angle));

        float ray_scale_fwd = 1.0 + pc.asymmetry * (float(r) / float(max(rays - 1, 1)));
        float ray_scale_bck = 1.0 - pc.asymmetry * (float(r) / float(max(rays - 1, 1)));

        for (int i = 1; i <= half_samples; i++) {
            float t = float(i) / float(half_samples);
            float weight = pow(1.0 - t, pc.falloff);

            float dist_fwd = float(i) * step_size * ray_scale_fwd;
            float dist_bck = float(i) * step_size * ray_scale_bck;

            float chroma = pc.chroma_shift;
            vec3 col_f_r = sample_bilinear(img_size, vec2(coord) + dir * dist_fwd * (1.0 - chroma));
            vec3 col_f_g = sample_bilinear(img_size, vec2(coord) + dir * dist_fwd);
            vec3 col_f_b = sample_bilinear(img_size, vec2(coord) + dir * dist_fwd * (1.0 + chroma));

            float luma_fr = max(col_f_r.r, max(col_f_r.g, col_f_r.b));
            float luma_fg = max(col_f_g.r, max(col_f_g.g, col_f_g.b));
            float luma_fb = max(col_f_b.r, max(col_f_b.g, col_f_b.b));

            float h_fr = soft_threshold(luma_fr, pc.threshold, pc.knee);
            float h_fg = soft_threshold(luma_fg, pc.threshold, pc.knee);
            float h_fb = soft_threshold(luma_fb, pc.threshold, pc.knee);

            vec3 fwd_contrib = vec3(0.0);
            if (h_fr > 0.0) fwd_contrib.r = col_f_r.r * (h_fr / max(luma_fr, 0.0001)) * weight;
            if (h_fg > 0.0) fwd_contrib.g = col_f_g.g * (h_fg / max(luma_fg, 0.0001)) * weight;
            if (h_fb > 0.0) fwd_contrib.b = col_f_b.b * (h_fb / max(luma_fb, 0.0001)) * weight;
            glare_accum += fwd_contrib;

            vec3 col_b_r = sample_bilinear(img_size, vec2(coord) - dir * dist_bck * (1.0 - chroma));
            vec3 col_b_g = sample_bilinear(img_size, vec2(coord) - dir * dist_bck);
            vec3 col_b_b = sample_bilinear(img_size, vec2(coord) - dir * dist_bck * (1.0 + chroma));

            float luma_br = max(col_b_r.r, max(col_b_r.g, col_b_r.b));
            float luma_bg = max(col_b_g.r, max(col_b_g.g, col_b_g.b));
            float luma_bb = max(col_b_b.r, max(col_b_b.g, col_b_b.b));

            float h_br = soft_threshold(luma_br, pc.threshold, pc.knee);
            float h_bg = soft_threshold(luma_bg, pc.threshold, pc.knee);
            float h_bb = soft_threshold(luma_bb, pc.threshold, pc.knee);

            vec3 bck_contrib = vec3(0.0);
            if (h_br > 0.0) bck_contrib.r = col_b_r.r * (h_br / max(luma_br, 0.0001)) * weight;
            if (h_bg > 0.0) bck_contrib.g = col_b_g.g * (h_bg / max(luma_bg, 0.0001)) * weight;
            if (h_bb > 0.0) bck_contrib.b = col_b_b.b * (h_bb / max(luma_bb, 0.0001)) * weight;
            glare_accum += bck_contrib;
        }
    }

    glare_accum *= step_size;
    float norm = 2.0 / float(rays);
    vec3 tint = vec3(pc.color_r, pc.color_g, pc.color_b);
    vec3 final_glare = glare_accum * tint * pc.intensity * 0.05 * norm;

    vec3 result;
    int bm = int(pc.blend_mode);
    if (bm == 1) {
        result = 1.0 - (1.0 - original.rgb) * (1.0 - final_glare);
    } else {
        result = original.rgb + final_glare;
    }

    imageStore(dest_image, coord, vec4(result, original.a));
}
