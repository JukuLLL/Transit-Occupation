#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;

layout(push_constant, std430) uniform PushConstant {
    float brush_radius;
    float pigment_bleed;
    float strength;
    float edge_preservation;

    float luma_preservation;
    float color_boost;
    float shape;
    float bleed_threshold;

    float _pad0;
    float _pad1;
    float _pad2;
    float _pad3;

    float _p1; float _p2; float _p3; float _p4;
} pc;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 img_size = imageSize(source_img);
    if (coord.x >= img_size.x || coord.y >= img_size.y) return;

    int radius = max(int(pc.brush_radius), 1);

    vec3 m[4];
    vec3 s[4];
    for(int k=0; k<4; k++) {
        m[k] = vec3(0.0);
        s[k] = vec3(0.0);
    }

    ivec2 offsets[4] = ivec2[](
        ivec2(-radius, -radius),
        ivec2(0, -radius),
        ivec2(-radius, 0),
        ivec2(0, 0)
    );

    int n = 0;

    for(int q=0; q<4; q++) {
        n = 0;
        for(int x=0; x<=radius; x++) {
            for(int y=0; y<=radius; y++) {
                if (pc.shape > 0.5) {

                    vec2 diff = vec2(float(x), float(y)) - vec2(float(radius) * 0.5);
                    if (length(diff) > float(radius) * 0.5 + 0.5) continue;
                }

                ivec2 sample_pos = coord + offsets[q] + ivec2(x, y);
                sample_pos = clamp(sample_pos, ivec2(0), img_size - 1);
                vec3 c = imageLoad(source_img, sample_pos).rgb;
                m[q] += c;
                s[q] += c * c;
                n++;
            }
        }
        float inv_n = 1.0 / float(max(n, 1));
        m[q] *= inv_n;
        s[q] = abs(s[q] * inv_n - m[q] * m[q]);
    }

    float min_var = 1e6;
    vec3 w_color = vec3(0.0);

    for(int q=0; q<4; q++) {
        float variance = dot(s[q], vec3(1.0));
        if (variance < min_var) {
            min_var = variance;
            w_color = m[q];
        }
    }

    vec4 orig = imageLoad(source_img, coord);
    vec3 final_color = w_color;

    if (pc.pigment_bleed > 0.0) {
        float edge_val = clamp(min_var * 50.0 / max(pc.bleed_threshold, 0.001), 0.0, 1.0);
        final_color *= mix(1.0, 0.5, edge_val * pc.pigment_bleed);
    }

    if (pc.color_boost > 0.001) {
        float luma = dot(final_color, vec3(0.2126, 0.7152, 0.0722));
        final_color = mix(final_color, mix(vec3(luma), final_color, 1.0 + pc.color_boost), 1.0);
    }

    if (pc.luma_preservation > 0.0) {
        float luma_orig = dot(orig.rgb, vec3(0.2126, 0.7152, 0.0722));
        float luma_final = dot(final_color, vec3(0.2126, 0.7152, 0.0722));
        final_color *= mix(1.0, luma_orig / max(luma_final, 0.0001), pc.luma_preservation);
    }

    final_color = mix(orig.rgb, final_color, pc.strength);
    imageStore(dest_img, coord, vec4(final_color, orig.a));
}
