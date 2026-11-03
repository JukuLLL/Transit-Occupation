shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx, unshaded;

uniform sampler2D PanoramicTexture;

void fragment() {
	// Направление взгляда в мировом пространстве отражается от нормали
	vec3 view_dir = VIEW;
	vec3 normal = NORMAL;
	vec3 reflect_dir = reflect(view_dir, normal);
	
	ROUGHNESS = 1.0f;

	// Вычисление долготы (longitude) и широты (latitude)
	float longitude = atan(reflect_dir.x, reflect_dir.z); // [-PI, PI]
	float latitude = acos(clamp(reflect_dir.y, -1.0, 1.0)); // [0, PI]

	// Нормализация в UV-координаты
	longitude = (longitude + 3.14159265359) / (2.0 * 3.14159265359); // [0..1]
	latitude = latitude / 3.14159265359; // [0..1]

	vec2 uv = vec2(longitude, latitude);

	// Семплируем панорамную текстуру
	vec4 tex_color = texture(PanoramicTexture, uv);
	ALBEDO = tex_color.rgb;
}
