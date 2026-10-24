#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly  image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;
layout(set = 2, binding = 0) uniform sampler2D depth_tex;

layout(push_constant, std430) uniform PushConstant {
    float focus_distance;
    float aperture;
    float focal_length;
    float max_blur;

    float near_start;
    float near_end;
    float far_start;
    float far_end;

    float bokeh_shape;
    float bokeh_rotation;
    float samples;
    float strength;

    float near_plane;
    float far_plane;
    float autofocus_x;
    float autofocus_y;

    float autofocus_enabled;
    float chroma_amount;
    float highlight_boost;
    float highlight_threshold;

    float manual_mode;
    float _pad0;
    float _pad1;
    float _pad2;
} pc;

float linearize_depth(float raw_depth) {
    float n = pc.near_plane;
    float f = pc.far_plane;
    return (n * f) / (f - raw_depth * (f - n));
}

float compute_coc_physical(float depth, float focus_dist) {
    float f_mm = pc.focal_length;
    float a_mm = f_mm / max(pc.aperture, 0.1);
    float s = max(focus_dist * 1000.0, f_mm + 0.001);
    float d = max(depth * 1000.0, f_mm + 0.001);
    float coc = a_mm * (f_mm * (s - d)) / (d * (s - f_mm));
    return coc * 0.5;
}

float compute_coc_manual(float depth, float focus_dist) {
    float delta = depth - focus_dist;
    float coc;
    if (delta < 0.0) {
        float range = max(pc.near_start - pc.near_end, 0.0001);
        float t = clamp((-delta - pc.near_end) / range, 0.0, 1.0);
        coc = -t;
    } else {
        float range = max(pc.far_end - pc.far_start, 0.0001);
        float t = clamp((delta - pc.far_start) / range, 0.0, 1.0);
        coc = t;
    }
    return coc;
}

vec2 bokeh_offset(int index, int total, float shape, float rotation) {
    float angle = float(index) / float(total) * 6.28318530;
    angle += rotation;
    vec2 dir = vec2(cos(angle), sin(angle));

    int sides = int(shape);
    if (sides < 3) {
        return dir;
    }

    float sector = 6.28318530 / float(sides);
    float half_sector = sector * 0.5;
    float local_angle = mod(angle - rotation, sector) - half_sector;
    float r = cos(half_sector) / cos(local_angle);
    return dir * r;
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_img);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec2 uv = (vec2(coord) + 0.5) / vec2(img_size);

    float focus_dist = pc.focus_distance;
    if (pc.autofocus_enabled > 0.5) {
        vec2 af_uv = vec2(pc.autofocus_x, pc.autofocus_y);
        float af_raw = textureLod(depth_tex, af_uv, 0.0).r;
        focus_dist = linearize_depth(af_raw);
    }

    float raw_depth = textureLod(depth_tex, uv, 0.0).r;
    float linear_depth = linearize_depth(raw_depth);

    float coc;
    if (pc.manual_mode > 0.5) {
        coc = compute_coc_manual(linear_depth, focus_dist);
    } else {
        coc = compute_coc_physical(linear_depth, focus_dist);
    }

    float abs_coc = clamp(abs(coc), 0.0, pc.max_blur);
    float blur_radius = abs_coc * pc.strength;

    vec4 original = imageLoad(source_img, coord);

    if (blur_radius < 0.5) {
        imageStore(dest_img, coord, original);
        return;
    }

    int sample_count = max(int(pc.samples), 1);
    float rotation = pc.bokeh_rotation * (3.14159265 / 180.0);
    float shape = pc.bokeh_shape;

    vec4 accum = vec4(0.0);
    float weight_sum = 0.0;
    float highlight_accum = 0.0;

    for (int ring = 0; ring <= 3; ring++) {
        float ring_radius = blur_radius * (float(ring) / 3.0);
        int ring_samples = (ring == 0) ? 1 : sample_count;

        for (int i = 0; i < ring_samples; i++) {
            vec2 offset;
            if (ring == 0) {
                offset = vec2(0.0);
            } else {
                offset = bokeh_offset(i, ring_samples, shape, rotation) * ring_radius;
            }

            ivec2 sample_coord = clamp(coord + ivec2(round(offset)), ivec2(0), img_size - 1);

            vec2 sample_uv = (vec2(sample_coord) + 0.5) / vec2(img_size);
            float s_raw = textureLod(depth_tex, sample_uv, 0.0).r;
            float s_depth = linearize_depth(s_raw);

            float s_coc;
            if (pc.manual_mode > 0.5) {
                s_coc = compute_coc_manual(s_depth, focus_dist);
            } else {
                s_coc = compute_coc_physical(s_depth, focus_dist);
            }
            float s_abs_coc = clamp(abs(s_coc), 0.0, pc.max_blur);

            float w = 1.0;
            if (s_abs_coc < length(offset) / max(pc.max_blur, 0.001) && ring > 0) {
                w = 0.1;
            }

            vec4 s = imageLoad(source_img, sample_coord);

            float luma = max(s.r, max(s.g, s.b));
            float highlight = max(luma - pc.highlight_threshold, 0.0) * pc.highlight_boost;
            s.rgb *= 1.0 + highlight;

            if (pc.chroma_amount > 0.001 && ring > 0) {
                float chroma_shift = pc.chroma_amount * (float(ring) / 3.0);
                vec2 chroma_off = offset * chroma_shift * 0.1;
                ivec2 r_coord = clamp(coord + ivec2(round(offset - chroma_off)), ivec2(0), img_size - 1);
                ivec2 b_coord = clamp(coord + ivec2(round(offset + chroma_off)), ivec2(0), img_size - 1);
                s.r = imageLoad(source_img, r_coord).r * (1.0 + highlight);
                s.b = imageLoad(source_img, b_coord).b * (1.0 + highlight);
            }

            accum += s * w;
            weight_sum += w;
        }
    }

    vec4 blurred = accum / max(weight_sum, 0.0001);
    vec4 result = mix(original, blurred, clamp(abs_coc / max(pc.max_blur, 0.001), 0.0, 1.0));
    result.a = original.a;

    imageStore(dest_img, coord, result);
}
