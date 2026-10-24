#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_img;

layout(push_constant, std430) uniform PushConstant {
    float character_scale;
    float character_set;
    float color_mode;
    float strength;

    float bg_r; float bg_g; float bg_b; float fg_r;
    float fg_g; float fg_b; float screen_width; float screen_height;

    float _p1; float _p2; float _p3; float _p4;
} pc;

float rand(vec2 n) {
    return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

float get_font_pixel(int type, vec2 block_uv, float lum, vec2 block_id) {
    ivec2 p = ivec2(floor(block_uv * vec2(3.0, 5.0)));
    p.x = clamp(p.x, 0, 2);
    p.y = clamp(p.y, 0, 4);

    if (type == 0) {
        int l = int(lum * 6.0);
        if (l == 0) return 0.0;
        if (l == 1) return float(p.x == 1 && p.y == 0);
        if (l == 2) return float(p.y == 2);
        if (l == 3) return float(p.y == 2 || p.x == 1);
        if (l == 4) return float((p.x==0&&p.y==0)||(p.x==2&&p.y==4)||(p.y==2&&p.x==1)||(p.x==0&&p.y==4)||(p.x==2&&p.y==0));
        if (l >= 5) return float(p.x==0||p.x==2||p.y==0||p.y==2||p.y==4);
    } else if (type == 1) {
        if (lum < 0.1) return 0.0;
        float r = rand(block_id + vec2(lum));
        if (r < 0.5) {
            return float((p.x==0||p.x==2) && (p.y>0&&p.y<4) || (p.y==0||p.y==4) && p.x==1);
        } else {
            return float(p.x==1 || (p.x==0&&p.y==3) || (p.y==0));
        }
    } else if (type == 2) {
        if (lum < 0.05) return 0.0;
        float r = rand(block_id * 1.5 + vec2(lum));

        if (r < 0.25) return float(p.y==4 || p.x==1 || (p.x==0 && p.y==0));
        if (r < 0.5) return float(p.y==4 || p.x==0 || p.y==2);
        if (r < 0.75) return float((p.x==2&&p.y>0) || (p.y==0&&p.x>0) || (p.y==2&&p.x<2));
        return float(p.x==1 || (p.y==0&&p.x==0) || (p.y==4&&p.x==2));
    }
    return 0.0;
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 dest_size = imageSize(color_img);
    if (coord.x >= dest_size.x || coord.y >= dest_size.y) return;

    vec4 orig = imageLoad(color_img, coord);

    float scale = max(pc.character_scale, 2.0);
    vec2 block_id = floor(vec2(coord) / scale);
    ivec2 block_center_coord = ivec2(block_id * scale + (scale * 0.5));
    block_center_coord = clamp(block_center_coord, ivec2(0), dest_size - 1);

    vec3 sampled_col = imageLoad(color_img, block_center_coord).rgb;
    float luma = dot(sampled_col, vec3(0.299, 0.587, 0.114));

    vec2 block_uv = fract(vec2(coord) / scale);

    vec2 local_uv = (block_uv - 0.1) / 0.8;

    float alpha = 0.0;
    if (local_uv.x >= 0.0 && local_uv.x <= 1.0 && local_uv.y >= 0.0 && local_uv.y <= 1.0) {
        alpha = get_font_pixel(int(pc.character_set), local_uv, luma, block_id);
    }

    vec3 bg_color = vec3(pc.bg_r, pc.bg_g, pc.bg_b);
    vec3 fg_color = vec3(pc.fg_r, pc.fg_g, pc.fg_b);

    vec3 final_col;
    if (pc.color_mode < 0.5) {
        final_col = mix(vec3(0.0), sampled_col * 1.5, alpha);
    } else {
        final_col = mix(bg_color, mix(fg_color, vec3(1.0), luma * 0.3), alpha);

        if (alpha > 0.5) final_col *= mix(0.3, 1.5, luma);
    }

    vec3 mixed_result = mix(orig.rgb, final_col, pc.strength);

    imageStore(color_img, coord, vec4(mixed_result, orig.a));
}
