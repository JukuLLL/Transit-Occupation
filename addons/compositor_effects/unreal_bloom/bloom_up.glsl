#[compute]
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D source_tex;

layout(rgba16f, set = 1, binding = 0) uniform restrict image2D dest_img;

layout(push_constant, std430) uniform PushConstant {
    vec2 inv_tex_size;
    float filter_radius;
    float pad0;
    float pad1; float pad2; float pad3; float pad4;
} pc;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 dest_size = imageSize(dest_img);
    if (coord.x >= dest_size.x || coord.y >= dest_size.y) return;

    vec2 norm_uv = (vec2(coord) + 0.5) / vec2(dest_size);
    vec2 texel = pc.inv_tex_size * pc.filter_radius;

    vec3 A = texture(source_tex, norm_uv + vec2(-1.0, -1.0) * texel).rgb;
    vec3 B = texture(source_tex, norm_uv + vec2( 0.0, -1.0) * texel).rgb;
    vec3 C = texture(source_tex, norm_uv + vec2( 1.0, -1.0) * texel).rgb;
    vec3 D = texture(source_tex, norm_uv + vec2(-1.0,  0.0) * texel).rgb;
    vec3 E = texture(source_tex, norm_uv + vec2( 0.0,  0.0) * texel).rgb;
    vec3 F = texture(source_tex, norm_uv + vec2( 1.0,  0.0) * texel).rgb;
    vec3 G = texture(source_tex, norm_uv + vec2(-1.0,  1.0) * texel).rgb;
    vec3 H = texture(source_tex, norm_uv + vec2( 0.0,  1.0) * texel).rgb;
    vec3 I = texture(source_tex, norm_uv + vec2( 1.0,  1.0) * texel).rgb;

    vec3 upsampled = E * 0.25;
    upsampled += (B + D + F + H) * 0.125;
    upsampled += (A + C + G + I) * 0.0625;

    vec3 existing = imageLoad(dest_img, coord).rgb;
    imageStore(dest_img, coord, vec4(existing + upsampled, 1.0));
}
