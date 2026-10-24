#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly  image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;

layout(push_constant, std430) uniform PushConstant {
    float brightness;
    float contrast;
    float saturation;
    float gamma;

    float exposure;
    float temperature;
    float tint;
    float hue_shift;

    float vibrance;
    float contrast_pivot;
    float lift;
    float gain;

    float shadow_lift;
    float midtone_adjust;
    float highlight_adjust;
    float shadow_threshold;

    float highlight_threshold;
    float gamma_r;
    float gamma_g;
    float gamma_b;

    float clamp_output;
    float _pad0;
    float _pad1;
    float _pad2;
} pc;

vec3 rgb_to_hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float zone_weight_shadow(float luma, float threshold) {
    return 1.0 - smoothstep(0.0, threshold, luma);
}

float zone_weight_highlight(float luma, float threshold) {
    return smoothstep(threshold, 1.0, luma);
}

float zone_weight_midtone(float luma, float s_thr, float h_thr) {
    return max(1.0 - zone_weight_shadow(luma, s_thr) - zone_weight_highlight(luma, h_thr), 0.0);
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_img);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec4 original = imageLoad(source_img, coord);
    vec3 color = original.rgb;

    color *= pow(2.0, pc.exposure);

    color.r *= 1.0 + pc.temperature * 0.3;
    color.b *= 1.0 - pc.temperature * 0.3;
    color.g *= 1.0 + pc.tint * 0.2;

    color += vec3(pc.brightness);

    color = (color - pc.contrast_pivot) * pc.contrast + pc.contrast_pivot;

    float luma = luminance(color);
    color = mix(vec3(luma), color, pc.saturation);

    float max_c = max(color.r, max(color.g, color.b));
    float sat_approx = (max_c > 0.0001) ? (max_c - min(color.r, min(color.g, color.b))) / max_c : 0.0;
    float vib_weight = (1.0 - sat_approx) * pc.vibrance;
    luma = luminance(color);
    color = mix(vec3(luma), color, 1.0 + vib_weight);

    if (pc.hue_shift != 0.0) {
        vec3 hsv = rgb_to_hsv(color);
        hsv.x = fract(hsv.x + pc.hue_shift / 360.0);
        color = hsv_to_rgb(hsv);
    }

    color += vec3(pc.lift);
    color *= pc.gain;

    luma = luminance(color);
    float ws = zone_weight_shadow(luma, pc.shadow_threshold);
    float wh = zone_weight_highlight(luma, pc.highlight_threshold);
    float wm = zone_weight_midtone(luma, pc.shadow_threshold, pc.highlight_threshold);
    color += vec3(ws * pc.shadow_lift + wm * pc.midtone_adjust + wh * pc.highlight_adjust);

    vec3 g = max(vec3(pc.gamma_r, pc.gamma_g, pc.gamma_b) * pc.gamma, vec3(0.01));
    color = pow(max(color, vec3(0.0)), 1.0 / g);

    if (pc.clamp_output > 0.5) {
        color = clamp(color, vec3(0.0), vec3(1.0));
    }

    imageStore(dest_img, coord, vec4(color, original.a));
}
