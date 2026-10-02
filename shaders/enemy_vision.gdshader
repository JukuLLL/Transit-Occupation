/*
FOR SCREEN POST-PROCESSING (GRAY SCALE AND DITHERING)
*/

shader_type canvas_item;

uniform sampler2D texture_screen : hint_screen_texture;
uniform sampler2D texture_noise;

uniform float colors : hint_range(1.0, 16.0);
uniform float dither : hint_range(0.0, 0.5);

void fragment() {
	
	COLOR = texture(texture_screen, SCREEN_UV);
	float avg = (COLOR.r + COLOR.g + COLOR.b) / 3.0;
	
	COLOR.rgb = vec3(avg);
	float a = floor(mod(UV.x / TEXTURE_PIXEL_SIZE.x, 2.0));
	float b = floor(mod(UV.y / TEXTURE_PIXEL_SIZE.y, 2.0));	
	float c = mod(a + b, 2.0);
	
	vec4 color = COLOR;
	
	COLOR.r = (round(color.r * colors + dither) / colors) * c;
	COLOR.g = (round(color.g * colors + dither) / colors) * c;
	COLOR.b = (round(color.b * colors + dither) / colors) * c;
	c = 1.0 - c;
	COLOR.r += (round(color.r * colors - dither) / colors) * c;
	COLOR.g += (round(color.g * colors - dither) / colors) * c;
	COLOR.b += (round(color.b * colors - dither) / colors) * c;
}
