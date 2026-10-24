#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly  image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;

layout(push_constant, std430) uniform PushConstant {
    float strength;
    float angle;
    float mix_mode;
    float bias;

    float kernel_radius;
    float edge_tint_r;
    float edge_tint_g;
    float edge_tint_b;

    float luma_only;
    float contrast;
    float blend;
    float metallic;

    float _pad0;
    float _pad1;
    float _pad2;
    float _pad3;
} pc;

vec4 sample_clamped(ivec2 coord, ivec2 img_size) {
    return imageLoad(source_img, clamp(coord, ivec2(0), img_size - 1));
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_img);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec4 original = imageLoad(source_img, coord);

    float a = radians(pc.angle);
    vec2 dir = vec2(cos(a), -sin(a));
    int radius = max(int(pc.kernel_radius), 1);

    vec3 accum_pos = vec3(0.0);
    vec3 accum_neg = vec3(0.0);

    for (int i = 1; i <= radius; i++) {
        float w = 1.0 / float(i);
        ivec2 offset = ivec2(round(dir * float(i)));
        accum_pos += sample_clamped(coord + offset, img_size).rgb * w;
        accum_neg += sample_clamped(coord - offset, img_size).rgb * w;
    }

    vec3 emboss = (accum_pos - accum_neg) * pc.strength;

    if (pc.contrast != 1.0) {
        emboss = (emboss - 0.0) * pc.contrast;
    }

    emboss += vec3(pc.bias);

    vec3 tint = vec3(pc.edge_tint_r, pc.edge_tint_g, pc.edge_tint_b);

    vec3 result;
    int mode = int(pc.mix_mode);

    if (mode == 0) {
        float luma = dot(emboss, vec3(0.333));
        result = vec3(luma) * tint;
    } else if (mode == 1) {
        vec3 base = original.rgb;
        vec3 bv = clamp(emboss, vec3(0.0), vec3(1.0));
        result = mix(
            2.0 * base * bv,
            1.0 - 2.0 * (1.0 - base) * (1.0 - bv),
            step(0.5, bv)
        );
    } else if (mode == 2) {
        result = original.rgb + emboss * tint - vec3(pc.bias);
    } else {
        result = original.rgb * (emboss + vec3(1.0 - pc.bias));
    }

    if (pc.metallic > 0.001) {
        float edge_luma = abs(dot(accum_pos - accum_neg, vec3(0.333)));
        float highlight = pow(clamp(edge_luma * pc.strength, 0.0, 1.0), 3.0);
        result += tint * highlight * pc.metallic;
    }

    if (pc.luma_only > 0.5) {
        float orig_luma = dot(original.rgb, vec3(0.2126, 0.7152, 0.0722));
        float result_luma = dot(result, vec3(0.2126, 0.7152, 0.0722));
        if (result_luma > 0.0001) {
            result = original.rgb * (result_luma / orig_luma);
        }
    }

    result = mix(original.rgb, result, pc.blend);
    imageStore(dest_img, coord, vec4(result, original.a));
}
