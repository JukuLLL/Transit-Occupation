#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;

layout(push_constant, std430) uniform PushConstant {
    float dark_r;
    float dark_g;
    float dark_b;
    float cutoff;

    float light_r;
    float light_g;
    float light_b;
    float softness;

    float strength;
    float invert_mask;
    float color_space;
    float _pad0;

    float _p1; float _p2; float _p3; float _p4;
} pc;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(color_image);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec4 original = imageLoad(color_image, coord);
    vec3 color = original.rgb;

    float value;
    int space = int(pc.color_space);
    if (space == 1)      value = color.r;
    else if (space == 2) value = color.g;
    else if (space == 3) value = color.b;
    else                 value = dot(color, vec3(0.2126, 0.7152, 0.0722));

    float half_soft = max(pc.softness, 0.001) * 0.5;
    float t = smoothstep(pc.cutoff - half_soft, pc.cutoff + half_soft, value);

    if (pc.invert_mask > 0.5) {
        t = 1.0 - t;
    }

    vec3 dark_color  = vec3(pc.dark_r,  pc.dark_g,  pc.dark_b);
    vec3 light_color = vec3(pc.light_r, pc.light_g, pc.light_b);
    vec3 thresholded = mix(dark_color, light_color, t);

    vec3 result = mix(color, thresholded, pc.strength);

    imageStore(color_image, coord, vec4(result, original.a));
}
