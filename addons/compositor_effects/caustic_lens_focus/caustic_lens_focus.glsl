#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;

layout(push_constant, std430) uniform PushConstant {
    float intensity;
    float aberration_spread;
    float wave_frequency;
    float time;

    float focus_x;
    float focus_y;
    float wave_speed;
    float falloff_radius;

    float falloff_sharpness;
    float luminance_boost;
    float harmonics;
    float harmonic_scale;

    float blend;
    float distortion_mode;
    float _pad0;
    float _pad1;
} pc;

vec4 sample_img(ivec2 img_size, vec2 uv) {
    ivec2 c = clamp(ivec2(uv * vec2(img_size)), ivec2(0), img_size - 1);
    return imageLoad(source_img, c);
}

float radial_mask(float dist, float radius, float sharpness) {
    if (radius <= 0.0) return 1.0;
    float edge = radius * sharpness;
    return 1.0 - smoothstep(radius - edge, radius, dist);
}

float caustic_wave(float dist, float freq, float speed, float t, float harmonics, float hscale) {
    float w = sin(dist * freq - t * speed);
    float h2 = sin(dist * freq * harmonics - t * speed * 1.3) * hscale;
    float h3 = sin(dist * freq * harmonics * 2.1 - t * speed * 0.7) * hscale * 0.5;
    return w + h2 + h3;
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_img);

    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    vec2 uv = vec2(coord) / vec2(img_size);
    vec2 focus = vec2(pc.focus_x, pc.focus_y);
    vec2 d = uv - focus;

    float aspect = float(img_size.x) / float(img_size.y);
    vec2 d_aspect = d * vec2(aspect, 1.0);
    float dist = length(d_aspect);

    float wave = caustic_wave(dist, pc.wave_frequency, pc.wave_speed, pc.time, pc.harmonics, pc.harmonic_scale);
    float ripple = wave * (pc.intensity * 0.05);

    float mask = radial_mask(dist, pc.falloff_radius, pc.falloff_sharpness);
    ripple *= mask;

    vec2 radial_dir = (dist > 0.0001) ? (d / length(d)) : vec2(0.0);

    vec2 dir_r;
    vec2 dir_g;
    vec2 dir_b;

    if (pc.distortion_mode > 0.5) {
        vec2 tangent = vec2(-radial_dir.y, radial_dir.x);
        dir_r = tangent;
        dir_g = tangent;
        dir_b = tangent;
    } else {
        dir_r = radial_dir;
        dir_g = radial_dir;
        dir_b = radial_dir;
    }

    float chroma = pc.aberration_spread;
    vec2 uv_r = uv + dir_r * ripple;
    vec2 uv_g = uv + dir_g * ripple * (1.0 + chroma);
    vec2 uv_b = uv + dir_b * ripple * (1.0 + chroma * 2.0);

    float r = sample_img(img_size, uv_r).r;
    float g = sample_img(img_size, uv_g).g;
    float b = sample_img(img_size, uv_b).b;

    float luma = (r + g + b) / 3.0;
    vec3 distorted = vec3(r, g, b) + vec3(luma) * ripple * pc.luminance_boost;

    vec4 orig = imageLoad(source_img, coord);
    vec3 result = mix(orig.rgb, distorted, pc.blend);

    imageStore(dest_img, coord, vec4(result, orig.a));
}
