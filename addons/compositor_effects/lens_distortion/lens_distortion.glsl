#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;

layout(push_constant, std430) uniform PushConstant {
    float distortion;
    float cubic_distortion;
    float scale;
    float strength;

    float center_x;
    float center_y;
    float aspect_ratio;
    float chroma_shift;

    float border_r;
    float border_g;
    float border_b;
    float vignette;

    float squeeze;
    float _pad0;
    float _pad1;
    float _pad2;
} pc;

vec4 sample_bilinear(ivec2 img_size, vec2 cpos) {
    vec2 pos = clamp(cpos, vec2(0.0), vec2(img_size) - 1.0);
    ivec2 base = ivec2(floor(pos - 0.5));
    vec2 f = fract(pos - 0.5);
    ivec2 c00 = clamp(base, ivec2(0), img_size - 1);
    ivec2 c10 = clamp(base + ivec2(1, 0), ivec2(0), img_size - 1);
    ivec2 c01 = clamp(base + ivec2(0, 1), ivec2(0), img_size - 1);
    ivec2 c11 = clamp(base + ivec2(1, 1), ivec2(0), img_size - 1);
    return mix(
        mix(imageLoad(source_img, c00), imageLoad(source_img, c10), f.x),
        mix(imageLoad(source_img, c01), imageLoad(source_img, c11), f.x),
        f.y
    );
}

vec2 distort_uv(vec2 ndc, float extra_dist) {
    float r2 = dot(ndc, ndc);
    float f = 1.0 + (pc.distortion + extra_dist) * r2 + pc.cubic_distortion * r2 * r2;
    return ndc * f * pc.scale;
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_img);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec2 uv = (vec2(coord) + 0.5) / vec2(img_size);
    vec2 center = vec2(pc.center_x, pc.center_y);
    vec2 ndc = (uv - center) * 2.0;

    ndc.x *= mix(1.0, float(img_size.x) / float(img_size.y), pc.aspect_ratio);
    ndc.y *= pc.squeeze;

    vec3 border = vec3(pc.border_r, pc.border_g, pc.border_b);

    vec4 result;
    if (pc.chroma_shift > 0.001) {
        float shift = pc.chroma_shift * 0.1;
        vec2 ndc_r = distort_uv(ndc, -shift);
        vec2 ndc_g = distort_uv(ndc, 0.0);
        vec2 ndc_b = distort_uv(ndc, shift);

        vec2 uv_r = ndc_r * 0.5 / vec2(mix(1.0, float(img_size.x) / float(img_size.y), pc.aspect_ratio), pc.squeeze) + center;
        vec2 uv_g = ndc_g * 0.5 / vec2(mix(1.0, float(img_size.x) / float(img_size.y), pc.aspect_ratio), pc.squeeze) + center;
        vec2 uv_b = ndc_b * 0.5 / vec2(mix(1.0, float(img_size.x) / float(img_size.y), pc.aspect_ratio), pc.squeeze) + center;

        float r_val = (uv_r.x >= 0.0 && uv_r.x <= 1.0 && uv_r.y >= 0.0 && uv_r.y <= 1.0)
            ? sample_bilinear(img_size, uv_r * vec2(img_size)).r : border.r;
        float g_val = (uv_g.x >= 0.0 && uv_g.x <= 1.0 && uv_g.y >= 0.0 && uv_g.y <= 1.0)
            ? sample_bilinear(img_size, uv_g * vec2(img_size)).g : border.g;
        float b_val = (uv_b.x >= 0.0 && uv_b.x <= 1.0 && uv_b.y >= 0.0 && uv_b.y <= 1.0)
            ? sample_bilinear(img_size, uv_b * vec2(img_size)).b : border.b;

        result = vec4(r_val, g_val, b_val, 1.0);
    } else {
        vec2 dist_ndc = distort_uv(ndc, 0.0);
        vec2 dist_uv = dist_ndc * 0.5 / vec2(mix(1.0, float(img_size.x) / float(img_size.y), pc.aspect_ratio), pc.squeeze) + center;

        if (dist_uv.x < 0.0 || dist_uv.x > 1.0 || dist_uv.y < 0.0 || dist_uv.y > 1.0) {
            result = vec4(border, 1.0);
        } else {
            result = sample_bilinear(img_size, dist_uv * vec2(img_size));
        }
    }

    if (pc.vignette > 0.001) {
        float dist = length((uv - center) * 2.0);
        float vig = 1.0 - smoothstep(1.0 - pc.vignette, 1.0 + pc.vignette * 0.5, dist);
        result.rgb *= vig;
    }

    vec4 original = sample_bilinear(img_size, vec2(coord) + 0.5);
    result = mix(original, result, pc.strength);

    imageStore(dest_img, coord, result);
}
