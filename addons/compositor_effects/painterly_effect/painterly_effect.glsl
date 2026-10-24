#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;

layout(push_constant, std430) uniform PushConstant {
    float radius;
    float intensity;
    float bin_count;
    float edge_sharpness;

    float saturation_boost;
    float brush_angle;
    float brush_aspect;
    float color_variation;

    float luma_weight;
    float detail_preserve;
    float _pad0;
    float _pad1;
} pc;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_img);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    int r = max(int(pc.radius), 1);
    int num_bins = clamp(int(pc.bin_count), 2, 32);

    float angle = pc.brush_angle * (3.14159265 / 180.0);
    float ca = cos(angle), sa = sin(angle);
    float aspect = max(pc.brush_aspect, 0.1);

    int bins[32];
    vec3 colors[32];
    vec3 colors_sq[32];

    for (int i = 0; i < 32; i++) {
        bins[i] = 0;
        colors[i] = vec3(0.0);
        colors_sq[i] = vec3(0.0);
    }

    for (int x = -r; x <= r; x++) {
        for (int y = -r; y <= r; y++) {
            float rx = float(x) * ca + float(y) * sa;
            float ry = -float(x) * sa + float(y) * ca;
            rx /= aspect;

            if (rx * rx + ry * ry > float(r * r)) continue;

            ivec2 c = clamp(coord + ivec2(x, y), ivec2(0), img_size - 1);
            vec3 col = imageLoad(source_img, c).rgb;

            float luma = dot(col, vec3(0.299, 0.587, 0.114));
            int bin_idx = clamp(int(luma * float(num_bins - 1) + 0.5), 0, num_bins - 1);

            bins[bin_idx] += 1;
            colors[bin_idx] += col;
            colors_sq[bin_idx] += col * col;
        }
    }

    int max_freq = 0;
    int max_bin = 0;

    for (int i = 0; i < num_bins; i++) {
        if (bins[i] > max_freq) {
            max_freq = bins[i];
            max_bin = i;
        }
    }

    vec3 oil_color = colors[max_bin] / float(max(max_freq, 1));

    if (pc.color_variation > 0.001 && max_freq > 1) {
        vec3 mean = oil_color;
        vec3 mean_sq = colors_sq[max_bin] / float(max_freq);
        vec3 variance = max(mean_sq - mean * mean, vec3(0.0));
        oil_color = mix(oil_color, oil_color + sqrt(variance) * pc.color_variation, 0.5);
    }

    if (pc.saturation_boost != 1.0) {
        float oil_luma = dot(oil_color, vec3(0.2126, 0.7152, 0.0722));
        oil_color = mix(vec3(oil_luma), oil_color, pc.saturation_boost);
    }

    vec4 original = imageLoad(source_img, coord);

    if (pc.detail_preserve > 0.001) {
        float orig_luma = dot(original.rgb, vec3(0.2126, 0.7152, 0.0722));
        float oil_luma = dot(oil_color, vec3(0.2126, 0.7152, 0.0722));
        float detail = orig_luma - oil_luma;
        oil_color += vec3(detail * pc.detail_preserve);
    }

    if (pc.edge_sharpness > 0.001) {
        vec3 dx = imageLoad(source_img, clamp(coord + ivec2(1, 0), ivec2(0), img_size - 1)).rgb
                - imageLoad(source_img, clamp(coord - ivec2(1, 0), ivec2(0), img_size - 1)).rgb;
        vec3 dy = imageLoad(source_img, clamp(coord + ivec2(0, 1), ivec2(0), img_size - 1)).rgb
                - imageLoad(source_img, clamp(coord - ivec2(0, 1), ivec2(0), img_size - 1)).rgb;
        float edge = length(dx) + length(dy);
        float edge_mask = smoothstep(0.0, 0.3, edge);
        oil_color = mix(oil_color, original.rgb, edge_mask * pc.edge_sharpness);
    }

    vec3 result = mix(original.rgb, oil_color, pc.intensity);
    imageStore(dest_img, coord, vec4(result, original.a));
}
