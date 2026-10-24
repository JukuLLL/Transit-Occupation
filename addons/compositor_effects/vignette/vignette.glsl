#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;

layout(push_constant, std430) uniform PushConstant {
    float intensity;
    float radius;
    float softness;
    float strength;

    float color_r;
    float color_g;
    float color_b;
    float shape;

    float offset_x;
    float offset_y;
    float blend_mode;
    float _pad0;

    float _p1; float _p2; float _p3; float _p4;
} pc;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(color_image);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec2 uv = vec2(coord) / vec2(img_size);
    vec4 orig = imageLoad(color_image, coord);

    vec2 center = vec2(0.5 + pc.offset_x, 0.5 + pc.offset_y);
    float dist = 0.0;

    if (pc.shape < 0.5) {

        vec2 aspect_uv = uv;
        aspect_uv.x = (aspect_uv.x - center.x) * (float(img_size.x) / float(img_size.y)) + center.x;
        dist = distance(aspect_uv, center);
    } else if (pc.shape < 1.5) {

        dist = distance(uv, center);
    } else {

        vec2 d = abs(uv - center);
        dist = max(d.x, d.y);
    }

    float vignette_mask = smoothstep(pc.radius, pc.radius - pc.softness, dist);
    vignette_mask = mix(1.0, vignette_mask, pc.intensity);

    vec3 v_color = vec3(pc.color_r, pc.color_g, pc.color_b);
    vec3 final_color;

    if (pc.blend_mode < 0.5) {

        final_color = mix(v_color * orig.rgb, orig.rgb, vignette_mask);
    } else if (pc.blend_mode < 1.5) {

        final_color = mix(v_color, orig.rgb, vignette_mask);
    } else {

        final_color = orig.rgb + v_color * (1.0 - vignette_mask);
    }

    final_color = mix(orig.rgb, final_color, pc.strength);

    imageStore(color_image, coord, vec4(final_color, orig.a));
}
