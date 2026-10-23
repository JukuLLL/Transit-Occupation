@tool
class_name GDDrawShaderBaker
extends RefCounted

## Bakes a ShaderMaterial into one image per material channel so the Material Brush can paint with it.
##
## A spatial shader is drawn on a flat quad that fills a SubViewport, once per channel. For each pass the
## shader's own code is rewritten so that the channel's value (ALBEDO, ROUGHNESS, METALLIC, EMISSION, AO or
## NORMAL_MAP) comes out as the pixel colour of an unshaded surface. The shader is used through its UV
## coordinates, the way any texture-generating shader is; things that depend on the 3D position or lighting are
## meaningless here. A canvas_item shader is drawn as it is and gives the albedo channel.
##
## vertex(): the colour passes keep the shader's vertex function running (varyings it sets still reach
## fragment()) but put the vertices back afterwards, so wind or wobble does not warp the baked picture. A
## vertex function that moves vertices also gives the HEIGHT channel: the shader is drawn on a finely
## subdivided plane and the displacement along the surface normal (what `VERTEX += NORMAL * h` or
## `VERTEX.y += h` does) is written out as a height map scaled to fill 0..1.
##
## Channels the shader never writes are not baked (the Material Brush then paints nothing for them).

const CHANNEL_OUTPUTS := {
	"albedo": "ALBEDO",
	"emission": "EMISSION",
	"roughness": "ROUGHNESS",
	"metallic": "METALLIC",
	"ao": "AO",
	"normal": "NORMAL_MAP",
}

const DEFAULT_SIZE := 1024
const SIZES := [256, 512, 1024, 2048]

## The viewport encodes its output as sRGB; maps that must come out unchanged (scalars, normals, heights) are
## converted to linear first, the exact inverse of that encoding.
const LINEARIZE := "ALBEDO = mix(pow((_gddraw_v + vec3(0.055)) / 1.055, vec3(2.4)), _gddraw_v / 12.92, lessThan(_gddraw_v, vec3(0.04045)));"

## A small procedural material for the "New Shader Material" menu entry.
const TEMPLATE_CODE := """shader_type spatial;
// A procedural marble for the Material Brush. Change anything: the brush re-bakes as you edit.
// The shader is read by UV (0..1 across the whole texture), so `stripes` is how many bands there are across it.
// It writes ALBEDO, ROUGHNESS, METALLIC and NORMAL_MAP in fragment(), and moves vertices in vertex() (that
// becomes the height map). EMISSION and AO work the same way. The channels you write are the ones baked.

uniform vec3 color_a : source_color = vec3(0.05, 0.55, 0.60);
uniform vec3 color_b : source_color = vec3(1.0, 0.55, 0.10);
uniform float stripes : hint_range(2.0, 400.0) = 40.0;
uniform float warp : hint_range(0.0, 4.0) = 1.5;
uniform float warp_scale : hint_range(1.0, 100.0) = 12.0;
uniform float roughness_a : hint_range(0.0, 1.0) = 0.15;
uniform float roughness_b : hint_range(0.0, 1.0) = 0.9;
uniform float metal_amount : hint_range(0.0, 1.0) = 0.0;
uniform float bump : hint_range(0.0, 8.0) = 3.0;
uniform float height_amount : hint_range(0.0, 1.0) = 0.1;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * value_noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

// 0 in the teal bands, 1 in the orange ones
float bands(vec2 uv) {
	float wobble = fbm(uv * warp_scale) * warp * 6.2831853;
	float band = 0.5 + 0.5 * sin((uv.x * 0.8 + uv.y * 0.6) * stripes * 6.2831853 + wobble);
	return smoothstep(0.35, 0.65, band);
}

void vertex() {
	VERTEX += NORMAL * bands(UV) * height_amount;
}

void fragment() {
	float t = bands(UV);
	ALBEDO = mix(color_a, color_b, t);
	ROUGHNESS = mix(roughness_a, roughness_b, t);
	METALLIC = metal_amount * (1.0 - t);
	vec2 e = vec2(0.0015, 0.0);
	float dx = bands(UV + e.xy) - bands(UV - e.xy);
	float dy = bands(UV + e.yx) - bands(UV - e.yx);
	NORMAL_MAP = normalize(vec3(-dx * bump, -dy * bump, 1.0)) * 0.5 + 0.5;
}
"""


## Which channels a shader writes (empty when the shader cannot be baked).
static func detect_channels(code: String) -> PackedStringArray:
	var result := PackedStringArray()
	var kind := _shader_kind(code)
	if kind == "canvas_item":
		result.push_back("albedo")
		return result
	if kind != "spatial":
		return result
	var clean := _strip_comments(code)
	var fragment_body := _function_body(clean, "fragment")
	if fragment_body.is_empty():
		return result
	for channel: String in CHANNEL_OUTPUTS:
		var regex := RegEx.new()
		regex.compile("\\b%s\\s*(?:[-+*/]?=)(?!=)" % CHANNEL_OUTPUTS[channel])
		if regex.search(fragment_body) != null:
			result.push_back(channel)
	if _vertex_moves_vertices(clean):
		result.push_back("height")
	return result


## The shader code that renders `channel` as an unshaded colour, or "" when that is not possible. For the
## height channel `height_probe_scale` > 0 writes 0.5 + displacement * scale (used to find the displacement's
## range); otherwise the displacement is mapped from height_min..height_min + height_range onto 0..1.
static func make_channel_shader_code(code: String, channel: String, height_min := 0.0, height_range := 1.0, height_probe_scale := 0.0) -> String:
	var kind := _shader_kind(code)
	if kind == "canvas_item":
		return code if channel == "albedo" else ""
	if kind != "spatial" or not (CHANNEL_OUTPUTS.has(channel) or channel == "height"):
		return ""
	var is_height := channel == "height"
	if is_height and not _vertex_moves_vertices(_strip_comments(code)):
		return ""
	# 1. vertex(): keep it running, but put the vertices back (and, for height, measure the displacement).
	var rewritten := _wrap_vertex(code, is_height)
	var clean := _strip_comments(rewritten)
	var open_brace := _function_open_brace(clean, "fragment")
	if open_brace < 0:
		return ""
	var close_brace := _matching_brace(clean, open_brace)
	if close_brace < 0:
		return ""
	# 2. the output stage appended to the end of fragment().
	var output := ""
	match channel:
		"albedo":
			output = "\n\tEMISSION = vec3(0.0);\n"
		"emission":
			output = "\n\tALBEDO = EMISSION;\n\tEMISSION = vec3(0.0);\n"
		"roughness", "metallic", "ao":
			output = "\n\tvec3 _gddraw_v = clamp(vec3(%s), vec3(0.0), vec3(1.0));\n\t%s\n\tEMISSION = vec3(0.0);\n" % [CHANNEL_OUTPUTS[channel], LINEARIZE]
		"normal":
			output = "\n\tvec3 _gddraw_v = clamp(NORMAL_MAP, vec3(0.0), vec3(1.0));\n\t%s\n\tEMISSION = vec3(0.0);\n" % LINEARIZE
		"height":
			var mapped := ""
			if height_probe_scale > 0.0:
				mapped = "0.5 + _gddraw_height * %s" % String.num(height_probe_scale, 8)
			else:
				mapped = "(_gddraw_height - (%s)) * %s" % [String.num(height_min, 8), String.num(1.0 / maxf(height_range, 0.0000001), 8)]
			output = "\n\tvec3 _gddraw_v = vec3(clamp(%s, 0.0, 1.0));\n\t%s\n\tEMISSION = vec3(0.0);\n" % [mapped, LINEARIZE]
	rewritten = rewritten.substr(0, close_brace) + output + rewritten.substr(close_brace)
	# 3. render_mode: unshaded, drawn from both sides (and the varying the height pass reads).
	var declarations := "\nvarying float _gddraw_height;" if is_height else ""
	var render_mode := RegEx.new()
	render_mode.compile("render_mode\\s+([^;]*);")
	var found := render_mode.search(clean)
	if found != null:
		# Keep the shader's own modes, but a second cull mode is a compile error, so its cull mode is replaced.
		var kept := PackedStringArray()
		for mode in found.get_string(1).split(",", false):
			var mode_name := mode.strip_edges()
			if mode_name != "" and not mode_name.begins_with("cull_") and mode_name != "unshaded":
				kept.push_back(mode_name)
		kept.push_back("unshaded")
		kept.push_back("cull_disabled")
		rewritten = rewritten.substr(0, found.get_start()) + "render_mode " + ", ".join(kept) + ";" + declarations + rewritten.substr(found.get_end())
	else:
		var type_end := _shader_type_end(clean)
		rewritten = rewritten.substr(0, type_end) + "\nrender_mode unshaded, cull_disabled;" + declarations + rewritten.substr(type_end)
	return rewritten


## A text that changes whenever the shader code or one of its parameters changes.
static func material_signature(material: ShaderMaterial) -> String:
	if material == null or material.shader == null:
		return ""
	var parts := PackedStringArray([str(material.shader.code.hash()), str(material.shader.get_instance_id())])
	for uniform in material.shader.get_shader_uniform_list():
		var uniform_name := str(uniform["name"])
		var value: Variant = material.get_shader_parameter(uniform_name)
		if value is Object and value != null:
			parts.push_back("%s=obj%d" % [uniform_name, (value as Object).get_instance_id()])
		else:
			parts.push_back("%s=%s" % [uniform_name, str(value)])
	return "|".join(parts)


## Renders every channel the shader writes. `host` is a node in the scene tree used for the temporary
## viewports. Returns {channel: Image}; channels that could not be rendered are left out.
static func bake(host: Node, material: ShaderMaterial, size := DEFAULT_SIZE) -> Dictionary:
	var images := {}
	if host == null or not host.is_inside_tree() or material == null or material.shader == null:
		return images
	var code := material.shader.code
	var kind := _shader_kind(code)
	for channel in detect_channels(code):
		var image: Image = null
		if channel == "height":
			image = await _bake_height(host, material, size)
		else:
			var channel_code := make_channel_shader_code(code, channel)
			if channel_code == "":
				continue
			image = await _render_code(host, material, channel_code, size, kind, false)
		if image != null and not image.is_empty():
			images[channel] = image
	return images


static func _render_code(host: Node, material: ShaderMaterial, channel_code: String, size: int, kind: String, plane: bool) -> Image:
	var pass_material := material.duplicate() as ShaderMaterial
	var pass_shader := Shader.new()
	pass_shader.code = channel_code
	pass_material.shader = pass_shader
	return await _render(host, pass_material, size, kind, plane)


## The height map: the vertex displacement, found in a few probing passes (its range is not known in advance)
## and then written out scaled to fill 0..1.
static func _bake_height(host: Node, material: ShaderMaterial, size: int) -> Image:
	var code := material.shader.code
	var probe_size := mini(size, 256)
	var scale := 0.5
	var low := 0.0
	var high := 1.0
	for attempt in range(8):
		var probe_code := make_channel_shader_code(code, "height", 0.0, 1.0, scale)
		if probe_code == "":
			return null
		var probe: Image = await _render_code(host, material, probe_code, probe_size, "spatial", true)
		if probe == null or probe.is_empty():
			return null
		var span := _value_span(probe)
		low = span.x
		high = span.y
		if low <= 0.01 or high >= 0.99:
			scale *= 0.1
		elif high - low < 0.02:
			scale *= 10.0
		else:
			break
		if attempt == 7:
			return null
	# displacement = (value - 0.5) / scale
	var height_min := (low - 0.5) / scale
	var height_range := (high - low) / scale
	if height_range <= 0.0000001:
		return null
	var final_code := make_channel_shader_code(code, "height", height_min, height_range)
	return await _render_code(host, material, final_code, size, "spatial", true)


## The smallest and largest red value of an image (from a 128x128 sample).
static func _value_span(image: Image) -> Vector2:
	var sample := image.duplicate() as Image
	sample.resize(128, 128, Image.INTERPOLATE_NEAREST)
	var data := sample.get_data()
	var smallest := 255
	var largest := 0
	for pixel_index in range(128 * 128):
		var value: int = data[pixel_index * 4]
		smallest = mini(smallest, value)
		largest = maxi(largest, value)
	return Vector2(float(smallest) / 255.0, float(largest) / 255.0)


static func _render(host: Node, material: ShaderMaterial, size: int, kind: String, plane := false) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(size, size)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.transparent_bg = false
	viewport.disable_3d = kind != "spatial"
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_debanding = false
	if kind == "spatial":
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color.BLACK
		environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
		var camera := Camera3D.new()
		camera.environment = environment
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 2.0
		camera.near = 0.05
		camera.far = 10.0
		var surface := MeshInstance3D.new()
		if plane:
			# a finely subdivided plane seen from above (its normal is +Y, so `VERTEX.y +=` and `NORMAL *` both
			# move it toward the camera); u runs left to right and v top to bottom, as in the other passes
			var plane_mesh := PlaneMesh.new()
			plane_mesh.size = Vector2(2.0, 2.0)
			var subdivisions := clampi(size / 2 - 1, 63, 511)
			plane_mesh.subdivide_width = subdivisions
			plane_mesh.subdivide_depth = subdivisions
			surface.mesh = plane_mesh
			camera.transform = Transform3D(Basis.looking_at(Vector3(0.0, -1.0, 0.0), Vector3(0.0, 0.0, -1.0)), Vector3(0.0, 2.0, 0.0))
			viewport.add_child(camera)
		else:
			var quad_mesh := QuadMesh.new()
			quad_mesh.size = Vector2(2.0, 2.0)
			surface.mesh = quad_mesh
			camera.position = Vector3(0.0, 0.0, 2.0)
			viewport.add_child(camera)
		surface.material_override = material
		viewport.add_child(surface)
	else:
		var rect := ColorRect.new()
		rect.color = Color.WHITE
		rect.size = Vector2(size, size)
		rect.material = material
		viewport.add_child(rect)
	host.add_child(viewport)
	var tree := host.get_tree()
	# UPDATE_ONCE draws during the next frame; a few frames later the image is ready. (frame_post_draw is not
	# used: it never fires when there is no renderer, and the bake would wait forever.)
	for _i in range(4):
		await tree.process_frame
	var texture := viewport.get_texture()
	var image: Image = texture.get_image() if texture != null else null
	viewport.queue_free()
	if image != null and image.is_compressed():
		image.decompress()
	if image != null and image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


# --------------------------------------------------------------------------- source helpers

## Adds the code that keeps vertex() from moving the geometry (and, for the height pass, records how far it
## moved along the surface normal in the `_gddraw_height` varying).
static func _wrap_vertex(code: String, record_height: bool) -> String:
	var clean := _strip_comments(code)
	var open_brace := _function_open_brace(clean, "vertex")
	if open_brace < 0:
		return code
	var close_brace := _matching_brace(clean, open_brace)
	if close_brace < 0:
		return code
	var closing := "\n\t_gddraw_height = dot(VERTEX - _gddraw_rest, _gddraw_normal);\n\tVERTEX = _gddraw_rest;\n" if record_height else "\n\tVERTEX = _gddraw_rest;\n"
	return (
		code.substr(0, open_brace + 1)
		+ "\n\tvec3 _gddraw_rest = VERTEX;\n\tvec3 _gddraw_normal = NORMAL;\n"
		+ code.substr(open_brace + 1, close_brace - open_brace - 1)
		+ closing
		+ code.substr(close_brace)
	)


## Whether vertex() assigns to VERTEX.
static func _vertex_moves_vertices(clean: String) -> bool:
	var body := _function_body(clean, "vertex")
	if body.is_empty():
		return false
	var regex := RegEx.new()
	regex.compile("\\bVERTEX\\s*(?:\\.\\w+)?\\s*(?:[-+*/]?=)(?!=)")
	return regex.search(body) != null


static func _shader_kind(code: String) -> String:
	var regex := RegEx.new()
	regex.compile("shader_type\\s+(\\w+)\\s*;")
	var found := regex.search(_strip_comments(code))
	return found.get_string(1) if found != null else ""


static func _shader_type_end(clean: String) -> int:
	var regex := RegEx.new()
	regex.compile("shader_type\\s+\\w+\\s*;")
	var found := regex.search(clean)
	return found.get_end() if found != null else 0


## The same text with comments replaced by spaces (so every index still matches the original).
static func _strip_comments(code: String) -> String:
	var length := code.length()
	var index := 0
	var chars := PackedStringArray()
	chars.resize(length)
	for i in range(length):
		chars[i] = code[i]
	while index < length:
		if code[index] == "/" and index + 1 < length and code[index + 1] == "/":
			while index < length and code[index] != "\n":
				chars[index] = " "
				index += 1
		elif code[index] == "/" and index + 1 < length and code[index + 1] == "*":
			while index < length and not (code[index] == "*" and index + 1 < length and code[index + 1] == "/"):
				if code[index] != "\n":
					chars[index] = " "
				index += 1
			if index < length:
				chars[index] = " "
				chars[index + 1] = " "
				index += 2
		else:
			index += 1
	return "".join(chars)


static func _function_open_brace(clean: String, function_name: String) -> int:
	var regex := RegEx.new()
	regex.compile("void\\s+%s\\s*\\(\\s*\\)\\s*\\{" % function_name)
	var found := regex.search(clean)
	return found.get_end() - 1 if found != null else -1


static func _matching_brace(clean: String, open_index: int) -> int:
	var depth := 0
	for index in range(open_index, clean.length()):
		var character := clean[index]
		if character == "{":
			depth += 1
		elif character == "}":
			depth -= 1
			if depth == 0:
				return index
	return -1


static func _function_body(clean: String, function_name: String) -> String:
	var open_brace := _function_open_brace(clean, function_name)
	if open_brace < 0:
		return ""
	var close_brace := _matching_brace(clean, open_brace)
	return clean.substr(open_brace + 1, close_brace - open_brace - 1) if close_brace > open_brace else ""
