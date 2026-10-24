#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly  image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;

layout(push_constant, std430) uniform PushConstant {
    float blur_radius;
    float blur_sigma;
    float direction_x;
    float direction_y;

    float strength;
    float preserve_alpha;
    float luminance_mask;
    float mask_invert;

    float mask_threshold;
    float mask_softness;
    float tint_r;
    float tint_g;

    float tint_b;
    float gamma_correct;
    float _pad0;
    float _pad1;
} pc;

float gaussian(float x, float sigma) {
    return exp(-(x * x) / (2.0 * sigma * sigma));
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_img);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    int radius = clamp(int(pc.blur_radius), 0, 32);
    vec4 original = imageLoad(source_img, coord);

    if (radius == 0 || pc.strength < 0.001) {
        imageStore(dest_img, coord, original);
        return;
    }

    float sigma = pc.blur_sigma > 0.001 ? pc.blur_sigma : float(radius) / 3.0;
    ivec2 dir = ivec2(int(pc.direction_x), int(pc.direction_y));

    vec4 accum = vec4(0.0);
    float weight_sum = 0.0;

    for (int i = -radius; i <= radius; i++) {
        ivec2 sample_coord = clamp(coord + dir * i, ivec2(0), img_size - 1);
        float w = gaussian(float(i), sigma);
        vec4 s = imageLoad(source_img, sample_coord);

        if (pc.gamma_correct > 0.5) {
            s.rgb = s.rgb * s.rgb;
        }

        accum += s * w;
        weight_sum += w;
    }

    vec4 blurred = accum / max(weight_sum, 0.0001);

    if (pc.gamma_correct > 0.5) {
        blurred.rgb = sqrt(max(blurred.rgb, vec3(0.0)));
    }

    vec3 tint = vec3(pc.tint_r, pc.tint_g, pc.tint_b);
    blurred.rgb *= tint;

    float local_strength = pc.strength;

    if (pc.luminance_mask > 0.5) {
        float luma = dot(original.rgb, vec3(0.2126, 0.7152, 0.0722));
        float mask = smoothstep(pc.mask_threshold, pc.mask_threshold + max(pc.mask_softness, 0.001), luma);
        if (pc.mask_invert > 0.5) mask = 1.0 - mask;
        local_strength *= mask;
    }

    vec4 result = mix(original, blurred, local_strength);

    if (pc.preserve_alpha > 0.5) {
        result.a = original.a;
    }

    imageStore(dest_img, coord, result);
}
