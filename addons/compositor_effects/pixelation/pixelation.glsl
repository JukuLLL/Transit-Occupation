#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;

layout(push_constant, std430) uniform PushConstant {
    float pixel_size_x;
    float pixel_size_y;
    float grid_offset_x;
    float grid_offset_y;

    float gap_size_x;
    float gap_size_y;
    float gap_color_r;
    float gap_color_g;

    float gap_color_b;
    float gap_roundness;
    float gap_aa;
    float color_mode;

    float posterize_levels;
    float outline_strength;
    float outline_threshold;
    float strength;
} pc;

float luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_img);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    int px = max(int(pc.pixel_size_x), 1);
    int py = max(int(pc.pixel_size_y), 1);

    vec2 offset = vec2(pc.grid_offset_x, pc.grid_offset_y);
    vec2 pos = vec2(coord) - offset;
    vec2 cell = floor(pos / vec2(px, py));
    vec2 local_pos = pos - cell * vec2(px, py);

    float gap_x = clamp(pc.gap_size_x, 0.0, float(px) - 1.0);
    float gap_y = clamp(pc.gap_size_y, 0.0, float(py) - 1.0);
    float fill_w = float(px) - gap_x;
    float fill_h = float(py) - gap_y;
    vec2 fill_center = vec2(fill_w, fill_h) * 0.5;

    float in_gap = 0.0;
    float roundness = clamp(pc.gap_roundness, 0.0, 1.0);
    float aa = max(pc.gap_aa, 0.01);

    if (gap_x > 0.0 || gap_y > 0.0) {
        vec2 fill_half = vec2(fill_w, fill_h) * 0.5;
        float max_radius = min(fill_half.x, fill_half.y);
        float radius = roundness * max_radius;
        vec2 d = abs(local_pos - fill_center) - fill_half + vec2(radius);
        float sdf = length(max(d, vec2(0.0))) - radius;
        in_gap = smoothstep(-aa, aa, sdf);
    }

    vec2 snapped_pos = cell * vec2(px, py) + vec2(float(px) * 0.5, float(py) * 0.5) + offset;
    ivec2 snapped = clamp(ivec2(snapped_pos), ivec2(0), img_size - 1);
    vec4 sampled = imageLoad(source_img, snapped);
    vec3 pixel_color = sampled.rgb;

    int mode = int(pc.color_mode);
    if (mode == 1) {
        float luma = luminance(pixel_color);
        pixel_color = vec3(luma);
    } else if (mode == 2) {
        pixel_color = vec3(
            pixel_color.r > 0.5 ? 1.0 : 0.0,
            pixel_color.g > 0.5 ? 1.0 : 0.0,
            pixel_color.b > 0.5 ? 1.0 : 0.0
        );
    }

    float levels = pc.posterize_levels;
    if (levels > 1.5 && levels < 256.0) {
        pixel_color = floor(pixel_color * levels + 0.5) / levels;
    }

    if (pc.outline_strength > 0.001) {
        vec2 neighbor_offsets[4] = vec2[4](
            vec2(float(px), 0.0), vec2(-float(px), 0.0),
            vec2(0.0, float(py)), vec2(0.0, -float(py))
        );
        float edge = 0.0;
        float center_luma = luminance(pixel_color);
        for (int i = 0; i < 4; i++) {
            ivec2 nc = clamp(ivec2(snapped_pos + neighbor_offsets[i]), ivec2(0), img_size - 1);
            float nl = luminance(imageLoad(source_img, nc).rgb);
            edge += abs(center_luma - nl);
        }
        edge *= 0.25;
        float outline = smoothstep(pc.outline_threshold, pc.outline_threshold + 0.1, edge);
        pixel_color *= 1.0 - outline * pc.outline_strength;
    }

    vec3 gap_col = vec3(pc.gap_color_r, pc.gap_color_g, pc.gap_color_b);
    vec3 result = mix(pixel_color, gap_col, in_gap);

    vec4 original = imageLoad(source_img, coord);
    result = mix(original.rgb, result, pc.strength);

    imageStore(dest_img, coord, vec4(result, original.a));
}
