shader_type spatial;
render_mode blend_add, unshaded,cull_disabled;

//Main color of the effect
uniform vec4 color:source_color;

//scrolling direction
uniform vec2 offset;

// scroll speed of the texture
uniform float speed;

// Mask Texture
uniform sampler2D mask_texture;

//Intensity of effect
uniform float intensity;

void fragment(){
	
	vec2 uv = UV;
	
	float scroll = TIME * speed;
	
	float scroll_amount = offset.x * scroll;
	
	vec2 scrolled = uv + vec2(scroll_amount);
	
	vec4 mask_color = texture(mask_texture,scrolled);
	
	float mask_alpha = mask_color.a;
	
	float mask_binary = round(mask_color.r);
	
	vec3 final_color = color.rgb * mask_binary;
	
	float clamped_intensity = clamp(intensity, 0, 5.0);
	float final_alpha = color.a * mask_alpha * clamped_intensity;
	
	ALBEDO = final_color;
	ALPHA = final_alpha;
}
