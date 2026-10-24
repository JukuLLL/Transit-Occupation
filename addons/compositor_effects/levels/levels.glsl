#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;

layout(push_constant, std430) uniform PushConstant {
    float in_black;
    float in_white;
    float in_gamma;
    float out_black;

    float out_white;
    float strength;
    float in_black_r;
    float in_white_r;

    float in_black_g;
    float in_white_g;
    float in_black_b;
    float in_white_b;

    float gamma_r;
    float gamma_g;
    float gamma_b;
    float clamp_output;
} pc;

vec3 apply_levels(vec3 color, vec3 ib, vec3 iw, vec3 gm, float ob, float ow) {
    vec3 in_range = max(iw - ib, vec3(0.0001));
    color = clamp((color - ib) / in_range, vec3(0.0), vec3(1.0));
    color = pow(color, 1.0 / max(gm, vec3(0.01)));
    color = mix(vec3(ob), vec3(ow), color);
    return color;
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(color_image);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec4 original = imageLoad(color_image, coord);
    vec3 color = original.rgb;

    vec3 ib = vec3(pc.in_black + pc.in_black_r, pc.in_black + pc.in_black_g, pc.in_black + pc.in_black_b);
    vec3 iw = vec3(pc.in_white + pc.in_white_r, pc.in_white + pc.in_white_g, pc.in_white + pc.in_white_b);
    vec3 gm = vec3(pc.in_gamma * pc.gamma_r, pc.in_gamma * pc.gamma_g, pc.in_gamma * pc.gamma_b);

    color = apply_levels(color, ib, iw, gm, pc.out_black, pc.out_white);

    if (pc.clamp_output > 0.5) {
        color = clamp(color, vec3(0.0), vec3(1.0));
    }

    vec3 result = mix(original.rgb, color, pc.strength);
    imageStore(color_image, coord, vec4(result, original.a));
}
