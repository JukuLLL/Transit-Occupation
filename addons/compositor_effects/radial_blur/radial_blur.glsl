#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;

layout(push_constant, std430) uniform PushConstant {
    float center_x;
    float center_y;
    float blur_strength;
    float sample_count;

    float blur_power;
    float screen_width;
    float screen_height;
    float _pad0;

    float _p1; float _p2; float _p3; float _p4;
    float _p5; float _p6; float _p7; float _p8;
} pc;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 dest_size = imageSize(dest_img);
    if (coord.x >= dest_size.x || coord.y >= dest_size.y) return;

    vec2 uv = (vec2(coord) + 0.5) / vec2(pc.screen_width, pc.screen_height);
    vec2 center = vec2(pc.center_x, pc.center_y);

    vec2 dir = uv - center;
    float dist = length(dir);

    float strength = pow(dist, pc.blur_power) * pc.blur_strength;

    int samples = int(max(pc.sample_count, 1.0));
    vec3 result = vec3(0.0);
    float total_weight = 0.0;

    for (int i = 0; i < samples; i++) {
        float factor = float(i) / float(samples - 1);

        float scale = 1.0 - (factor * strength);
        vec2 sample_uv = center + (dir * scale);

        ivec2 sample_coord = ivec2(sample_uv * vec2(pc.screen_width, pc.screen_height));
        sample_coord = clamp(sample_coord, ivec2(0), dest_size - 1);

        result += imageLoad(source_img, sample_coord).rgb;
        total_weight += 1.0;
    }

    result /= max(total_weight, 1.0);

    vec4 orig = imageLoad(source_img, coord);
    imageStore(dest_img, coord, vec4(result, orig.a));
}
