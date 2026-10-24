#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_img;

layout(push_constant, std430) uniform PushConstant {
    float strength;
    float saturation_boost;
    float contrast;
    float exposure;

    float _p1; float _p2; float _p3; float _p4;
    float _p5; float _p6; float _p7; float _p8;
    float _p9; float _p10; float _p11; float _p12;
} pc;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 dest_size = imageSize(color_img);
    if (coord.x >= dest_size.x || coord.y >= dest_size.y) return;

    vec4 orig = imageLoad(color_img, coord);
    vec3 color = orig.rgb * pc.exposure;

    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    vec3 blend = vec3(luma);

    vec3 bypass = vec3(0.0);
    for (int i = 0; i < 3; i++) {
        if (blend[i] < 0.5) {
            bypass[i] = 2.0 * color[i] * blend[i];
        } else {
            bypass[i] = 1.0 - 2.0 * (1.0 - color[i]) * (1.0 - blend[i]);
        }
    }

    vec3 mixed = mix(color, bypass, pc.strength);

    if (pc.saturation_boost > 0.001) {
        float mix_luma = dot(mixed, vec3(0.2126, 0.7152, 0.0722));
        mixed = mix(vec3(mix_luma), mixed, 1.0 + pc.saturation_boost);
    }

    if (pc.contrast != 1.0) {
        mixed = (mixed - 0.5) * max(pc.contrast, 0.0) + 0.5;
    }

    mixed = max(mixed, vec3(0.0));

    imageStore(color_img, coord, vec4(mixed, orig.a));
}
