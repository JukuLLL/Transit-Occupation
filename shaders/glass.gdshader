shader_type spatial;
render_mode blend_mix, depth_draw_always;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap_anisotropic;

group_uniforms Color;
uniform vec3 color : source_color = vec3(1.0);
uniform float color_coat : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float oilyness : hint_range(0.0, 2.0, 0.01) = 0.1;

group_uniforms Rim;
uniform float rim_amount : hint_range(0.0, 1.0, 0.01) = 0.8;
uniform float rim_shape : hint_range(0.1, 6.0, 0.01) = 2.5;
uniform vec3 rim_color : source_color = vec3(1.0);

group_uniforms Refraction;
uniform float refraction_strength : hint_range(-1.0, 1.0, 0.01) = 0.5;

group_uniforms Blur;
uniform float blur_amount: hint_range(0.1, 8.0) = 4.0;
uniform float roughness_affect : hint_range(0.0, 1.0, 0.01) = 0.0;

group_uniforms Roughness;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform sampler2D roughness_texture;

float overlay(float base, float blend){
	float limit = step(0.5, base);
	return mix(2.0 * base * blend, 1.0 - 2.0 * (1.0 - base) * (1.0 - blend), limit);
}

void fragment() {
	vec2 pixel_size = 1.0 / vec2(textureSize(screen_texture, 0));
	
	float fresnel = pow(clamp(1.0 - dot(NORMAL, VIEW),0.0, 1.0), 1.0);
	vec2 offset = vec2(NORMAL.x, -NORMAL.y) * fresnel;
	
	vec2 screen_uv = SCREEN_UV + offset * refraction_strength;
	
	float roughness_value = clamp(texture(roughness_texture, UV).r * roughness, 0.01, 1.0);
	
	float blur = mix(blur_amount, overlay(blur_amount, 1.0 - roughness_value), roughness_affect);
	vec3 glass = textureLod(screen_texture, screen_uv, blur).rgb;
	
	float coat_amount = pow(1.0 - color_coat, 1.0);
	
	ALBEDO = color * mix(vec3(1.0), glass, coat_amount);
	ALBEDO = mix(ALBEDO, rim_color, pow(fresnel, rim_shape) * rim_amount);
	
	ALBEDO -= vec3((sin(NORMAL.xy * 10.0) * 0.5 + 0.5) * (0.1 * oilyness), 0.0);
	
	EMISSION = ALBEDO * coat_amount;
	
	SPECULAR = 1.0;
	
	ROUGHNESS = roughness_value;
}