#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;

layout(push_constant, std430) uniform PushConstant {
    float monitor_type;
    float phosphor_scale;
    float phosphor_power;
    float electron_convergence_x;

    float electron_convergence_y;
    float scanline_depth;
    float scanline_count;
    float scanline_interlaced;

    float rf_noise_static;
    float rf_noise_roll;
    float rf_color_bleed;
    float luma_halation;

    float vignette_strength;
    float corner_roundness;
    float brightness_boost;
    float time;
} pc;

float rand(vec2 n) {
    return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

vec3 read_ntsc_composite(vec2 uv, vec2 img_res) {
    float spread = pc.rf_color_bleed / img_res.x;

    vec2 conv_offset_r = vec2(pc.electron_convergence_x, pc.electron_convergence_y) / img_res;
    vec2 conv_offset_b = vec2(-pc.electron_convergence_x, -pc.electron_convergence_y) / img_res;

    vec2 uv_r = clamp(uv + conv_offset_r, 0.0, 1.0);
    vec2 uv_g = clamp(uv, 0.0, 1.0);
    vec2 uv_b = clamp(uv + conv_offset_b, 0.0, 1.0);

    vec2 smear_left = vec2(-spread, 0.0);
    vec2 smear_right = vec2(spread, 0.0);

    ivec2 cR = ivec2(uv_r * img_res);
    ivec2 cG = ivec2(uv_g * img_res);
    ivec2 cB = ivec2(uv_b * img_res);

    vec3 center = vec3(
        imageLoad(source_img, cR).r,
        imageLoad(source_img, cG).g,
        imageLoad(source_img, cB).b
    );

    if (pc.rf_color_bleed < 0.001) return center;

    ivec2 lR = ivec2((uv_r + smear_left) * img_res);
    ivec2 lG = ivec2((uv_g + smear_left) * img_res);
    ivec2 lB = ivec2((uv_b + smear_left) * img_res);

    ivec2 rR = ivec2((uv_r + smear_right) * img_res);
    ivec2 rG = ivec2((uv_g + smear_right) * img_res);
    ivec2 rB = ivec2((uv_b + smear_right) * img_res);

    vec3 left = vec3(imageLoad(source_img, lR).r, imageLoad(source_img, lG).g, imageLoad(source_img, lB).b);
    vec3 right = vec3(imageLoad(source_img, rR).r, imageLoad(source_img, rG).g, imageLoad(source_img, rB).b);

    float luma = dot(center, vec3(0.299, 0.587, 0.114));

    vec3 chroma_blur = (left + center + right) / 3.0;
    float blur_luma = dot(chroma_blur, vec3(0.299, 0.587, 0.114));

    vec3 result = chroma_blur * (luma / max(blur_luma, 0.001));
    return max(vec3(0.0), result);
}

vec3 get_phosphor_mask(vec2 coord) {
    int type = int(pc.monitor_type);
    vec3 mask = vec3(1.0);

    vec2 p_coord = floor(coord / max(pc.phosphor_scale, 0.1));

    if (type == 0) {
        int m = int(mod(p_coord.x, 3.0));
        mask = m == 0 ? vec3(1.0, 0.0, 0.0) : (m == 1 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
    } else if (type == 1) {
        int x = int(mod(p_coord.x, 3.0));
        int y = int(mod(p_coord.y, 2.0));
        int m = int(mod(float(x) + (y == 1 ? 1.5 : 0.0), 3.0));
        mask = m == 0 ? vec3(1.0, 0.0, 0.0) : (m == 1 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
    } else if (type == 2) {
        int y = int(mod(p_coord.y, 4.0));
        float offset = (y == 2 || y == 3) ? 1.5 : 0.0;
        int m = int(mod(p_coord.x + offset, 3.0));
        mask = m == 0 ? vec3(1.0, 0.0, 0.0) : (m == 1 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
        if (mod(p_coord.x, 3.0) < 0.5 && mod(p_coord.y, 2.0) > 0.5) mask *= 0.5;
    } else if (type == 3) {
        float lum = mod(p_coord.x + p_coord.y, 2.0);
        mask = lum > 0.5 ? vec3(0.1, 1.0, 0.2) : vec3(0.02, 0.2, 0.04);
    } else if (type == 4) {
        int x = int(mod(p_coord.x, 3.0));
        int y = int(mod(p_coord.y, 3.0));
        mask = x == 0 ? vec3(1.0, 0.1, 0.1) : (x == 1 ? vec3(0.1, 1.0, 0.1) : vec3(0.1, 0.1, 1.0));
        if (y == 0) mask *= 0.5;
    }

    mask = pow(mask, vec3(pc.phosphor_power));
    return mask;
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_img);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec2 uv = (vec2(coord) + 0.5) / vec2(img_size);
    vec2 mapped_uv = uv;

    if (pc.rf_noise_roll > 0.0) {
        float roll = sin(uv.y * 12.0 - pc.time * 4.0) * cos(uv.y * 50.0 + pc.time * 2.0);
        mapped_uv.x += roll * pc.rf_noise_roll * 0.005;
    }

    if (pc.rf_noise_static > 0.0) {
        float snow = rand(uv + vec2(pc.time * 0.1)) * 2.0 - 1.0;
        mapped_uv.x += snow * pc.rf_noise_static * 0.002;
    }

    vec3 color = read_ntsc_composite(mapped_uv, vec2(img_size));
    color *= pc.brightness_boost;

    if (pc.scanline_depth > 0.0) {
        float lines = max(pc.scanline_count, 120.0);
        float time_shift = pc.scanline_interlaced > 0.5 ? pc.time * 60.0 : 0.0;
        float line_wave = sin(mapped_uv.y * lines * 3.14159 + time_shift);
        float line_dim = clamp(line_wave * 0.5 + 0.5, 0.0, 1.0);
        color *= mix(1.0, line_dim, pc.scanline_depth);
    }

    vec3 mask = get_phosphor_mask(vec2(coord));
    color *= mask;

    if (pc.luma_halation > 0.0) {
        float luma = dot(color, vec3(0.299, 0.587, 0.114));
        color = mix(color, color * 1.5, luma * pc.luma_halation);
    }

    if (pc.corner_roundness > 0.0) {
        vec2 corner = abs(uv * 2.0 - 1.0);
        float len = length(max(corner - vec2(1.0 - pc.corner_roundness), 0.0));
        float bezel = 1.0 - smoothstep(0.0, 0.01, len - pc.corner_roundness);
        color *= bezel;
    }

    if (pc.vignette_strength > 0.0) {
        vec2 corner = abs(uv * 2.0 - 1.0);
        float v = 1.0 - pow(max(corner.x, corner.y), 4.0) * pc.vignette_strength;
        color *= clamp(v, 0.0, 1.0);
    }

    vec4 orig = imageLoad(source_img, coord);
    imageStore(dest_img, coord, vec4(color, orig.a));
}
