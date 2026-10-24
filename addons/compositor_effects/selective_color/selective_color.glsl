#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly  image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;

layout(push_constant, std430) uniform PushConstant {
    float target_hue;
    float hue_range;
    float falloff;
    float desat_amount;

    float invert_mask;
    float strength;
    float hue_shift;
    float sat_adjust;

    float val_adjust;
    float tint_r;
    float tint_g;
    float tint_b;

    float desat_luma_mode;
    float min_saturation;
    float _pad0;
    float _pad1;
} pc;

float rgb_hue(vec3 c) {
    float maxc = max(c.r, max(c.g, c.b));
    float minc = min(c.r, min(c.g, c.b));
    if (maxc - minc < 0.001) return 0.0;
    float d = maxc - minc;
    float h;
    if (maxc == c.r)      h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
    else if (maxc == c.g) h = (c.b - c.r) / d + 2.0;
    else                  h = (c.r - c.g) / d + 4.0;
    return h / 6.0;
}

float rgb_saturation(vec3 c) {
    float maxc = max(c.r, max(c.g, c.b));
    float minc = min(c.r, min(c.g, c.b));
    if (maxc < 0.001) return 0.0;
    return (maxc - minc) / maxc;
}

vec3 rgb_to_hsv(vec3 c) {
    float maxc = max(c.r, max(c.g, c.b));
    float minc = min(c.r, min(c.g, c.b));
    float d = maxc - minc;
    float h = 0.0;
    if (d > 0.00001) {
        if (maxc == c.r)      h = mod((c.g - c.b) / d, 6.0);
        else if (maxc == c.g) h = (c.b - c.r) / d + 2.0;
        else                  h = (c.r - c.g) / d + 4.0;
        h /= 6.0;
        if (h < 0.0) h += 1.0;
    }
    float s = (maxc > 0.00001) ? d / maxc : 0.0;
    return vec3(h, s, maxc);
}

vec3 hsv_to_rgb(vec3 c) {
    float h = c.x * 6.0;
    float s = c.y;
    float v = c.z;
    float ch = v * s;
    float x = ch * (1.0 - abs(mod(h, 2.0) - 1.0));
    float m = v - ch;
    vec3 rgb;
    if      (h < 1.0) rgb = vec3(ch, x,  0.0);
    else if (h < 2.0) rgb = vec3(x,  ch, 0.0);
    else if (h < 3.0) rgb = vec3(0.0, ch, x);
    else if (h < 4.0) rgb = vec3(0.0, x,  ch);
    else if (h < 5.0) rgb = vec3(x,  0.0, ch);
    else              rgb = vec3(ch, 0.0, x);
    return rgb + m;
}

float luminance709(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
float luminance601(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_img);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec4 original = imageLoad(source_img, coord);
    vec3 color = clamp(original.rgb, vec3(0.0), vec3(65504.0));

    float hue = rgb_hue(color);
    float sat = rgb_saturation(color);

    float target = pc.target_hue / 360.0;
    float half_range = (pc.hue_range / 360.0) * 0.5;
    float soft = max(pc.falloff / 360.0, 0.001);

    float hue_dist = abs(hue - target);
    hue_dist = min(hue_dist, 1.0 - hue_dist);

    float mask = 1.0 - smoothstep(half_range, half_range + soft, hue_dist);
    mask *= smoothstep(pc.min_saturation, pc.min_saturation + 0.05, sat);

    if (pc.invert_mask > 0.5) mask = 1.0 - mask;

    float luma;
    if (pc.desat_luma_mode > 0.5) {
        luma = luminance601(color);
    } else {
        luma = luminance709(color);
    }
    vec3 desaturated = mix(color, vec3(luma), pc.desat_amount);

    vec3 tint = vec3(pc.tint_r, pc.tint_g, pc.tint_b);
    desaturated *= tint;

    vec3 selected = color;
    if (abs(pc.hue_shift) > 0.001 || pc.sat_adjust != 1.0 || pc.val_adjust != 1.0) {
        vec3 hsv = rgb_to_hsv(selected);
        hsv.x = fract(hsv.x + pc.hue_shift / 360.0);
        hsv.y = clamp(hsv.y * pc.sat_adjust, 0.0, 1.0);
        hsv.z *= pc.val_adjust;
        selected = hsv_to_rgb(hsv);
    }

    vec3 result = mix(desaturated, selected, mask);
    result = mix(original.rgb, result, pc.strength);
    imageStore(dest_img, coord, vec4(result, original.a));
}
