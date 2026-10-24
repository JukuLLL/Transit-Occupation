#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;

layout(push_constant, std430) uniform PushConstant {
    float strength;
    float chromaticity;
    float frame;
    float grain_size;

    float shadow_noise;
    float midtone_noise;
    float highlight_noise;
    float shadow_threshold;

    float highlight_threshold;
    float blend_mode;
    float tint_r;
    float tint_g;

    float tint_b;
    float clamp_output;
    float response_curve;
    float _pad0;
} pc;

uint uhash(uint x) {
    x ^= x >> 16u;
    x *= 0x45d9f3bu;
    x ^= x >> 16u;
    x *= 0x45d9f3bu;
    x ^= x >> 16u;
    return x;
}

float pixel_noise(ivec2 p, uint seed) {
    uint h = uhash(uint(p.x) + uhash(uint(p.y) + uhash(seed)));
    return float(h) / 4294967295.0;
}

vec3 pixel_noise3(ivec2 p, uint seed) {
    return vec3(
        pixel_noise(p, seed),
        pixel_noise(p, seed + 7u),
        pixel_noise(p, seed + 13u)
    );
}

float to_triangle(float u) {
    float v = u * 2.0 - 1.0;
    return sign(v) * (1.0 - sqrt(max(1.0 - abs(v), 0.0)));
}

float to_gaussian(float u) {
    float v = clamp(u, 0.0001, 0.9999);
    return sqrt(-2.0 * log(v)) * cos(6.28318530 * pixel_noise(ivec2(0), uint(v * 65536.0)));
}

float shape_noise(float u, float curve) {
    if (curve < 0.5) {
        return u * 2.0 - 1.0;
    } else if (curve < 1.5) {
        return to_triangle(u);
    }
    return clamp(to_gaussian(u) * 0.3, -1.0, 1.0);
}

float luminance_weight(float luma) {
    float s = 1.0 - smoothstep(0.0, pc.shadow_threshold, luma);
    float h = smoothstep(pc.highlight_threshold, 1.0, luma);
    float m = max(1.0 - s - h, 0.0);
    return s * pc.shadow_noise + m * pc.midtone_noise + h * pc.highlight_noise;
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(color_image);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec4 original = imageLoad(color_image, coord);
    vec3 color = original.rgb;

    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));

    ivec2 gc = ivec2(floor(vec2(coord) / max(pc.grain_size, 1.0)));
    uint seed = uhash(uint(pc.frame));

    vec3 raw3 = pixel_noise3(gc, seed);
    float raw1 = pixel_noise(gc, seed + 100u);

    float curve = pc.response_curve;
    vec3 grain_rgb = vec3(shape_noise(raw3.r, curve), shape_noise(raw3.g, curve), shape_noise(raw3.b, curve));
    float grain_mono = shape_noise(raw1, curve);

    vec3 grain = mix(vec3(grain_mono), grain_rgb, pc.chromaticity);

    vec3 tint = vec3(pc.tint_r, pc.tint_g, pc.tint_b);
    grain *= tint;

    float weight = luminance_weight(luma);
    vec3 scaled_grain = grain * pc.strength * weight;

    vec3 result;
    int bm = int(pc.blend_mode);
    if (bm == 1) {
        result = color * (1.0 + scaled_grain);
    } else if (bm == 2) {
        vec3 blend_val = clamp(scaled_grain * 0.5 + 0.5, vec3(0.0), vec3(1.0));
        result = mix(
            2.0 * color * blend_val,
            1.0 - 2.0 * (1.0 - color) * (1.0 - blend_val),
            step(0.5, blend_val)
        );
    } else {
        result = color + scaled_grain;
    }

    if (pc.clamp_output > 0.5) {
        result = max(result, vec3(0.0));
    }

    imageStore(color_image, coord, vec4(result, original.a));
}
