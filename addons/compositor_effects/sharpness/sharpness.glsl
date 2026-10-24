#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;
layout(set = 2, binding = 0) uniform sampler2D depth_texture;

layout(push_constant, std430) uniform PushConstant {
    float strength;
    float threshold;
    float limit;
    float depth_threshold;

    float radius;
    float luma_only;
    float near_plane;
    float far_plane;

    float detail_boost;
    float edge_protect;
    float _pad0;
    float _pad1;
} pc;

float linearize_depth(float raw) {
    float n = pc.near_plane;
    float f = pc.far_plane;
    return (n * f) / (f - raw * (f - n));
}

float luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec4 sample_img(ivec2 img_size, ivec2 cpos) {
    return imageLoad(source_img, clamp(cpos, ivec2(0), img_size - 1));
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(source_img);
    if (coord.x >= size.x || coord.y >= size.y) return;

    vec4 center = imageLoad(source_img, coord);

    vec2 uv = (vec2(coord) + 0.5) / vec2(size);
    float raw_depth = textureLod(depth_texture, uv, 0.0).r;
    float linear_d = linearize_depth(raw_depth);

    if (pc.depth_threshold < 1.0 && linear_d > pc.depth_threshold * pc.far_plane) {
        imageStore(dest_img, coord, center);
        return;
    }

    int r = max(int(pc.radius), 1);
    vec4 laplacian = vec4(0.0);
    float total_weight = 0.0;

    for (int x = -r; x <= r; x++) {
        for (int y = -r; y <= r; y++) {
            if (x == 0 && y == 0) continue;
            float w = 1.0 / (float(abs(x) + abs(y)));
            laplacian -= sample_img(size, coord + ivec2(x, y)) * w;
            total_weight += w;
        }
    }
    laplacian += center * total_weight;
    laplacian /= total_weight;

    float magnitude;
    if (pc.luma_only > 0.5) {
        magnitude = abs(luminance(laplacian.rgb));
    } else {
        magnitude = length(laplacian.rgb);
    }

    float factor = smoothstep(pc.threshold, pc.threshold + 0.1, magnitude);

    if (pc.edge_protect > 0.001) {
        float depth_grad = 0.0;
        float d_right = linearize_depth(textureLod(depth_texture, uv + vec2(1.0 / float(size.x), 0.0), 0.0).r);
        float d_down  = linearize_depth(textureLod(depth_texture, uv + vec2(0.0, 1.0 / float(size.y)), 0.0).r);
        depth_grad = abs(linear_d - d_right) + abs(linear_d - d_down);
        float edge_mask = 1.0 - smoothstep(0.0, pc.edge_protect, depth_grad);
        factor *= edge_mask;
    }

    vec4 sharpening = laplacian * pc.strength * factor;

    if (pc.detail_boost > 0.001) {
        float detail = luminance(abs(laplacian.rgb));
        sharpening *= 1.0 + detail * pc.detail_boost;
    }

    sharpening = clamp(sharpening, -pc.limit, pc.limit);

    if (pc.luma_only > 0.5) {
        float sharp_luma = luminance(sharpening.rgb);
        vec4 result = center;
        result.rgb += vec3(sharp_luma);
        imageStore(dest_img, coord, result);
    } else {
        imageStore(dest_img, coord, center + sharpening);
    }
}
