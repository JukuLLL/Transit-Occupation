shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap_anisotropic;

group_uniforms Color;
uniform vec3 color : source_color = vec3(1.0);
uniform float color_coat : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float oilyness : hint_range(0.0, 2.0, 0.01) = 0.1;

group_uniforms Rim;
uniform float rim_amount : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float rim_shape : hint_range(0.1, 6.0, 0.01) = 4.0;
uniform vec3 rim_color : source_color = vec3(1.0);

group_uniforms Roughness;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.8;
uniform sampler2D roughness_texture;

group_uniforms Refraction;
uniform float refraction_strength : hint_range(-1.0, 1.0, 0.01) = 0.5;
uniform float scatter_strength : hint_range(0.0, 2.0, 0.1) = 0.5;
uniform vec2 tile_size = vec2(10.0);

vec2 scatter_offset(vec4 frag, vec2 screen_size, vec3 normal, float scale) {
	float x = mod(frag.x, tile_size.x) * 2.0 - tile_size.x;
	float y = mod(frag.y, tile_size.y) * 2.0 - tile_size.y;
	
	float aspect = screen_size.y / screen_size.x;
	
	vec2 offset = vec2(x,y) * normal.xy * scale * vec2(aspect, 1.0);
	
	return offset;
}


void fragment() {
	float fresnel = pow(clamp(1.0 - dot(NORMAL, VIEW),0.0, 1.0), 1.0);
	vec2 offset = vec2(NORMAL.x, -NORMAL.y) * fresnel;
	
	vec2 screen_size = vec2(textureSize(screen_texture, 4));
	
	vec2 uv = (SCREEN_UV + offset * refraction_strength) + scatter_offset(FRAGCOORD, screen_size, NORMAL, 0.01 * scatter_strength);
	vec4 screen = texture(screen_texture, uv);
	
	ROUGHNESS = 0.0;
	METALLIC = 0.0;
	
	float coat_amount = pow(1.0 - color_coat, 1.0);
	
	ALBEDO = color * mix(vec3(1.0), screen.rgb, coat_amount);
	ALBEDO = mix(ALBEDO, rim_color, pow(fresnel, rim_shape) * rim_amount);
	EMISSION = ALBEDO * coat_amount;
	
	ALBEDO -= vec3((sin(NORMAL.xy * 10.0) * 0.5 + 0.5) * (0.1 * oilyness), 0.0);
	
	SPECULAR = specular;
	
	float roughness_value = clamp(texture(roughness_texture, UV).r * roughness, 0.01, 1.0);
	ROUGHNESS = roughness_value;
}