#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly  image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;

layout(push_constant, std430) uniform PushConstant {
    float dot_size;
    float strength;
    float color_mode;
    float angle_offset;

    float aa_width;
    float dot_scale;
    float dot_gamma;
    float dot_shape;

    float paper_r;
    float paper_g;
    float paper_b;
    float ink_r;

    float ink_g;
    float ink_b;
    float angle_c;
    float angle_m;

    float angle_y;
    float angle_k;
    float angle_r;
    float angle_g;

    float angle_b;
    float angle_bw;
    float luma_mode;
    float _pad0;
} pc;

vec4 rgb_to_cmyk(vec3 rgb) {
    float k = 1.0 - max(rgb.r, max(rgb.g, rgb.b));
    float inv_k = 1.0 / max(1.0 - k, 0.0001);
    float c = (1.0 - rgb.r - k) * inv_k;
    float m = (1.0 - rgb.g - k) * inv_k;
    float y = (1.0 - rgb.b - k) * inv_k;
    return vec4(c, m, y, k);
}

vec3 cmyk_to_rgb(vec4 cmyk) {
    return vec3(
        (1.0 - cmyk.x) * (1.0 - cmyk.w),
        (1.0 - cmyk.y) * (1.0 - cmyk.w),
        (1.0 - cmyk.z) * (1.0 - cmyk.w)
    );
}

vec2 rotate_grid(vec2 coord, float angle_deg) {
    float a = radians(angle_deg);
    float ca = cos(a), sa = sin(a);
    return vec2(coord.x * ca + coord.y * sa, -coord.x * sa + coord.y * ca);
}

float dot_dist(vec2 coord, float angle_deg, float freq) {
    vec2 rot = rotate_grid(coord, angle_deg);
    vec2 cell = fract(rot / freq) - 0.5;
    int shape = int(pc.dot_shape);
    if (shape == 1) {
        return abs(cell.x) + abs(cell.y);
    } else if (shape == 2) {
        return abs(cell.x);
    }
    return length(cell);
}

float dot_mask(float dist, float channel_value) {
    float gamma = max(pc.dot_gamma, 0.01);
    float radius = pow(channel_value, 1.0 / gamma) * 0.5 * max(pc.dot_scale, 0.0);
    float aa = max(pc.aa_width, 0.0001);
    return 1.0 - smoothstep(radius - aa, radius + aa, dist);
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_img);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec4 original = imageLoad(source_img, coord);
    vec3 color = clamp(original.rgb, vec3(0.0), vec3(1.0));
    vec2 pos = vec2(coord);

    float freq = max(pc.dot_size, 1.0);
    float base = pc.angle_offset;

    vec3 paper = vec3(pc.paper_r, pc.paper_g, pc.paper_b);
    vec3 ink   = vec3(pc.ink_r,   pc.ink_g,   pc.ink_b);

    vec3 halftoned;
    int mode = int(pc.color_mode);

    if (mode == 0) {
        vec4 cmyk = rgb_to_cmyk(color);

        float mc = dot_mask(dot_dist(pos, base + pc.angle_c, freq), cmyk.x);
        float mm = dot_mask(dot_dist(pos, base + pc.angle_m, freq), cmyk.y);
        float my = dot_mask(dot_dist(pos, base + pc.angle_y, freq), cmyk.z);
        float mk = dot_mask(dot_dist(pos, base + pc.angle_k, freq), cmyk.w);

        vec4 dots = vec4(mc, mm, my, mk);
        halftoned = cmyk_to_rgb(dots);

    } else if (mode == 1) {
        float mr = dot_mask(dot_dist(pos, base + pc.angle_r, freq), color.r);
        float mg = dot_mask(dot_dist(pos, base + pc.angle_g, freq), color.g);
        float mb = dot_mask(dot_dist(pos, base + pc.angle_b, freq), color.b);
        halftoned = vec3(mr, mg, mb);

    } else {
        vec3 luma_weights = (pc.luma_mode > 0.5)
            ? vec3(0.2126, 0.7152, 0.0722)
            : vec3(0.299,  0.587,  0.114);
        float luma = dot(color, luma_weights);
        float m = dot_mask(dot_dist(pos, base + pc.angle_bw, freq), luma);
        halftoned = mix(paper, ink, m);
    }

    vec3 result = mix(color, halftoned, pc.strength);
    imageStore(dest_img, coord, vec4(result, original.a));
}
