#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly  image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;

layout(push_constant, std430) uniform PushConstant {
    float shadow_r;
    float shadow_g;
    float shadow_b;
    float strength;

    float highlight_r;
    float highlight_g;
    float highlight_b;
    float preserve_luma;

    float midtone_r;
    float midtone_g;
    float midtone_b;
    float midtone_pos;

    float curve_gamma;
    float saturation_preserve;
    float luma_mode;
    float _pad0;
} pc;

float luminance709(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
float luminance601(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float get_luma(vec3 c) {
    return (pc.luma_mode > 0.5) ? luminance709(c) : luminance601(c);
}

vec3 three_point_gradient(float t, vec3 shadow, vec3 midtone, vec3 highlight, float mid_pos) {
    float mp = clamp(mid_pos, 0.01, 0.99);
    if (t < mp) {
        return mix(shadow, midtone, t / mp);
    }
    return mix(midtone, highlight, (t - mp) / (1.0 - mp));
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_img);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec4 original = imageLoad(source_img, coord);
    vec3 color = original.rgb;

    float luma = clamp(get_luma(color), 0.0, 1.0);

    float gamma = max(pc.curve_gamma, 0.01);
    float t = pow(luma, 1.0 / gamma);

    vec3 shadow    = vec3(pc.shadow_r,    pc.shadow_g,    pc.shadow_b);
    vec3 midtone   = vec3(pc.midtone_r,   pc.midtone_g,   pc.midtone_b);
    vec3 highlight = vec3(pc.highlight_r,  pc.highlight_g,  pc.highlight_b);

    vec3 remapped = three_point_gradient(t, shadow, midtone, highlight, pc.midtone_pos);

    if (pc.preserve_luma > 0.001) {
        float remap_luma = get_luma(remapped);
        float ratio = luma / max(remap_luma, 0.0001);
        remapped *= mix(1.0, ratio, pc.preserve_luma);
    }

    if (pc.saturation_preserve > 0.001) {
        float orig_sat = length(color - vec3(luma));
        float remap_luma2 = get_luma(remapped);
        float remap_sat = length(remapped - vec3(remap_luma2));
        if (remap_sat > 0.0001) {
            float target_sat = mix(remap_sat, orig_sat, pc.saturation_preserve);
            remapped = vec3(remap_luma2) + (remapped - vec3(remap_luma2)) * (target_sat / remap_sat);
        }
    }

    vec3 result = mix(color, remapped, pc.strength);
    imageStore(dest_img, coord, vec4(result, original.a));
}
