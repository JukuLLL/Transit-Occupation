#[compute]
#version 450
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D source_img;
layout(rgba16f, set = 1, binding = 0) uniform restrict writeonly image2D dest_img;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 dest_size = imageSize(dest_img);
    if (coord.x >= dest_size.x || coord.y >= dest_size.y) return;

    vec4 val = imageLoad(source_img, coord);
    imageStore(dest_img, coord, val);
}
