#[compute]
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D bloom_tex;
layout(rgba16f, set = 1, binding = 0) uniform restrict image2D color_img;

layout(push_constant, std430) uniform PushConstant {
    float intensity;
    float pad0; float pad1; float pad2;
    float pad3; float pad4; float pad5; float pad6;
} pc;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 dest_size = imageSize(color_img);
    if (coord.x >= dest_size.x || coord.y >= dest_size.y) return;

    vec2 norm_uv = (vec2(coord) + 0.5) / vec2(dest_size);
    vec3 bloom = texture(bloom_tex, norm_uv).rgb;

    vec3 color = imageLoad(color_img, coord).rgb;

    color += bloom * pc.intensity;

    imageStore(color_img, coord, vec4(color, 1.0));
}
