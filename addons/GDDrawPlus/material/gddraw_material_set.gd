@tool
class_name GDDrawMaterialSet
extends RefCounted

## A "material" the Material Brush paints with: one image (or a plain value) per material
## channel (see GDDrawMaterialChannels). It is read from
##   - a StandardMaterial3D resource (.tres / .res / .material), or
##   - a texture set on disk: pick any image of the set and its siblings are found by file name
##     (Material Maker and most PBR exporters name them <name>_albedo.png, <name>_roughness.png,
##     <name>_metallic.png, <name>_emission.png, <name>_ambient_occlusion.png, <name>_depth.png ...).
## The set is only read, never modified. Normal maps are tangent-space maps in the OpenGL convention Godot uses;
## a set whose file name says DirectX (normal_dx) is flipped automatically, see flip_normal_green.

const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "tga", "exr", "hdr", "svg"]
const MATERIAL_EXTENSIONS := ["tres", "res", "material"]

## File-name words that identify a channel, most specific first. A name matches when it ends
## with the word (after a separator, or camelCase for words of 5+ letters).
const CHANNEL_WORDS := {
	"albedo": ["albedo", "basecolor", "base_color", "base-color", "diffuse", "color", "col"],
	"emission": ["emission", "emissive"],
	"roughness": ["roughness", "rough"],
	"metallic": ["metallic", "metalness", "metal"],
	"ao": ["ambient_occlusion", "ambientocclusion", "occlusion", "ao"],
	"height": ["height", "heightmap", "height_map", "displacement", "depth", "bump"],
	"normal": ["normal", "normalgl", "normaldx", "normal_gl", "normal_dx", "nrm"],
	# Not a channel of its own: one image holding ambient occlusion (red), roughness (green) and metallic (blue).
	"orm": ["orm", "arm"],
}
## Which image channel of a packed ORM texture holds what (see GDDrawMaterialChannels.extract_channel_value).
const ORM_CHANNELS := [["ao", 0], ["roughness", 1], ["metallic", 2]]
## Settings of a material that decide how a channel's texture LOOKS (not what it contains). A painted object needs
## them too, or the same textures render differently (e.g. deep parallax with layers vs the plain parallax default).
const SETTING_PROPERTIES := {
	"height": ["heightmap_scale", "heightmap_deep_parallax", "heightmap_min_layers", "heightmap_max_layers", "heightmap_flip_tangent", "heightmap_flip_binormal", "heightmap_flip_texture"],
	"ao": ["ao_light_affect"],
	"emission": ["emission_energy_multiplier"],
}

var display_name := ""
var source_path := ""
## The material this set was built from (null for a texture set on disk). Kept so the Material Brush can
## follow edits made to it in the Inspector.
var source_material: BaseMaterial3D
## The ShaderMaterial this set was baked from (null otherwise); see GDDrawShaderBaker.
var shader_material: ShaderMaterial

var _images: Dictionary = {}
var _constants: Dictionary = {}
var _tints: Dictionary = {}
var _selectors: Dictionary = {}
## Emission textures are added to the emission colour unless the material multiplies them (Godot's Emission Operator).
var _emission_adds := false
## Multiplier of the normal map's strength (StandardMaterial3D.normal_scale).
var _normal_scale := 1.0
## DirectX normal maps have their green channel inverted compared to Godot's OpenGL ones.
var flip_normal_green := false:
	set(value):
		if value != flip_normal_green:
			flip_normal_green = value
			_fast_maps.erase("normal")
var _fast_maps: Dictionary = {}


## Loads a set from a material resource or from any image of a texture set. Returns null when
## nothing usable was found (the reason is in `error`).
static func load_from_path(path: String, error: Array = []) -> GDDrawMaterialSet:
	if not FileAccess.file_exists(path):
		error.push_back("%s was not found." % path.get_file())
		return null
	var extension := path.get_extension().to_lower()
	var result := GDDrawMaterialSet.new()
	result.source_path = path
	var loaded := false
	if extension in MATERIAL_EXTENSIONS:
		loaded = result._load_material(path, error)
	elif extension in IMAGE_EXTENSIONS:
		loaded = result._load_texture_set(path, error)
	else:
		error.push_back("Choose a material (.tres) or an image from a texture set.")
	if not loaded or result.channels().is_empty():
		if error.is_empty():
			error.push_back("No usable textures were found for %s." % path.get_file())
		return null
	return result


## Builds a set from the images GDDrawShaderBaker rendered from a ShaderMaterial (channel -> Image).
static func load_from_baked(images: Dictionary, name_text: String, baked_from: ShaderMaterial, path := "") -> GDDrawMaterialSet:
	var result := GDDrawMaterialSet.new()
	result.source_path = path
	result.display_name = name_text if name_text != "" else "Shader"
	result.shader_material = baked_from
	for channel: String in images:
		if not GDDrawMaterialChannels.has_channel(channel):
			continue
		var image := result._prepare(images[channel] as Image)
		if image != null:
			result._images[channel] = image
			result._selectors[channel] = 0
	return result if not result.channels().is_empty() else null


## Builds a set from a material object that is already in memory (for example one being edited in the
## Inspector). `path` is only used for the display name.
static func load_from_material(material: BaseMaterial3D, path := "", error: Array = []) -> GDDrawMaterialSet:
	var result := GDDrawMaterialSet.new()
	result.source_path = path
	if material == null or not result._read_material(material, path.get_file().get_basename() if path != "" else material.resource_name, error) or result.channels().is_empty():
		if error.is_empty():
			error.push_back("The material has no textures or values the Material Brush can use.")
		return null
	return result


## Text that changes whenever something the Material Brush reads from `material` changes (textures,
## colours, values, enable switches), so edits made in the Inspector can be noticed cheaply.
static func material_signature(material: BaseMaterial3D) -> String:
	if material == null:
		return ""
	var parts := PackedStringArray([str(material.albedo_color)])
	for channel in GDDrawMaterialChannels.ids():
		var definition := GDDrawMaterialChannels.get_definition(channel)
		for key in ["enable", "value", "selector"]:
			var property_name := str(definition[key])
			if property_name != "":
				parts.push_back("%s=%s" % [property_name, str(material.get(property_name))])
		var texture := GDDrawMaterialChannels.read_texture(material, channel)
		if texture == null:
			parts.push_back("%s:none" % channel)
		else:
			var ready := true
			if texture is NoiseTexture2D:
				# Noise textures generate their image a moment after they are assigned.
				ready = (texture as NoiseTexture2D).get_image() != null
			parts.push_back("%s:%d:%s:%s" % [channel, texture.get_instance_id(), texture.resource_path, str(ready)])
	var packed_orm = material.get("orm_texture")
	if packed_orm is Texture2D:
		parts.push_back("orm:%d:%s" % [packed_orm.get_instance_id(), packed_orm.resource_path])
	for channel: String in SETTING_PROPERTIES:
		for property_name: String in SETTING_PROPERTIES[channel]:
			parts.push_back("%s=%s" % [property_name, str(material.get(property_name))])
	return "|".join(parts)


## A short display name for a material path: the file name of a material, the shared prefix of a texture set.
static func name_for_path(path: String) -> String:
	var base := path.get_file().get_basename()
	if path.get_extension().to_lower() in MATERIAL_EXTENSIONS:
		return base
	var prefix := str(classify_file_name(base)[1]).strip_edges()
	while prefix.length() > 0 and prefix[prefix.length() - 1] in ["_", "-", " ", "."]:
		prefix = prefix.left(prefix.length() - 1)
	return prefix if prefix != "" else base

## Splits a file base name into [channel, prefix]; channel is "" when no channel word is found.
static func classify_file_name(base_name: String) -> Array:
	var lowered := base_name.to_lower()
	for channel: String in CHANNEL_WORDS:
		for word: String in CHANNEL_WORDS[channel]:
			var prefix: Variant = _strip_trailing_word(lowered, word)
			if prefix != null:
				return [channel, str(prefix)]
	return ["", lowered]


## null when `name` does not end with `word`; otherwise the name without it (and without the separator).
static func _strip_trailing_word(name: String, word: String) -> Variant:
	if name == word:
		return ""
	for separator in ["_", "-", " ", "."]:
		if name.ends_with(separator + word):
			return name.substr(0, name.length() - word.length() - 1)
	if word.length() >= 5 and name.ends_with(word) and not word.contains("_") and not word.contains("-"):
		return name.substr(0, name.length() - word.length())
	return null


func channels() -> PackedStringArray:
	var result := PackedStringArray()
	for channel in GDDrawMaterialChannels.ids():
		if has_channel(channel):
			result.push_back(channel)
	return result


## The channel's colours exactly as sample() would give them, prepared for whole-image (native) use: an opaque
## RGBA8 Image, or a Color for a plain value. null when sample() does more than read the image (tints, other
## texture channels, transparency), in which case the Material Brush samples pixel by pixel instead.
func fast_map(channel: String) -> Variant:
	if _fast_maps.has(channel):
		return _fast_maps[channel] if _fast_maps[channel] != null else null
	var result: Variant = _build_fast_map(channel)
	_fast_maps[channel] = result
	return result


func _build_fast_map(channel: String) -> Variant:
	if not _images.has(channel):
		return _constants.get(channel, null)
	var tint: Color = _tints.get(channel, Color.WHITE)
	var image: Image = _images[channel]
	if image.get_format() != Image.FORMAT_RGBA8:
		return null
	var prepared := image.duplicate() as Image
	if GDDrawMaterialChannels.is_scalar(channel):
		if not is_equal_approx(tint.r, 1.0):
			return null
		var selector := int(_selectors.get(channel, 4))
		if selector == 4:
			prepared.convert(Image.FORMAT_L8)
		elif selector == 0 and shader_material != null:
			# baked images are gray already; only the alpha has to be made opaque
			prepared.convert(Image.FORMAT_RGB8)
		elif selector >= 0 and selector <= 2:
			# one colour channel of a packed texture (ORM, glTF metallic-roughness): pull it out once, natively usable after that
			prepared = _extract_channel(prepared, selector)
		else:
			return null
		prepared.convert(Image.FORMAT_RGBA8)
		return prepared
	if channel == "normal":
		if not is_equal_approx(_normal_scale, 1.0):
			return null
		if flip_normal_green:
			var normal_data := prepared.get_data()
			for pixel_index in range(prepared.get_width() * prepared.get_height()):
				normal_data[pixel_index * 4 + 1] = 255 - normal_data[pixel_index * 4 + 1]
			prepared = Image.create_from_data(prepared.get_width(), prepared.get_height(), false, Image.FORMAT_RGBA8, normal_data)
	if channel == "emission" and _emission_adds:
		if tint.r > 0.001 or tint.g > 0.001 or tint.b > 0.001:
			return null
	elif not (is_equal_approx(tint.r, 1.0) and is_equal_approx(tint.g, 1.0) and is_equal_approx(tint.b, 1.0) and is_equal_approx(tint.a, 1.0)):
		return null
	if prepared.detect_alpha() != Image.ALPHA_NONE:
		return null
	return prepared


## The red (0), green (1) or blue (2) channel of an RGBA8 image as an L8 image.
static func _extract_channel(image: Image, selector: int) -> Image:
	var data := image.get_data()
	var count := image.get_width() * image.get_height()
	var bytes := PackedByteArray()
	bytes.resize(count)
	for index in range(count):
		bytes[index] = data[index * 4 + selector]
	return Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_L8, bytes)


func has_channel(channel: String) -> bool:
	return _images.has(channel) or _constants.has(channel)


func has_texture(channel: String) -> bool:
	return _images.has(channel)


func describe() -> String:
	var labels := PackedStringArray()
	for channel in channels():
		labels.push_back(GDDrawMaterialChannels.label(channel) + ("" if has_texture(channel) else " (value)"))
	return ", ".join(labels)


## The colour of `channel` at texture coordinate `uv` (wraps, so 0..1 is one tile). Scalar
## channels return gray. Channels the set does not have return transparent.
func sample(channel: String, uv: Vector2) -> Color:
	if _images.has(channel):
		var image: Image = _images[channel]
		var color := _sample_bilinear(image, uv)
		return _finish(channel, color)
	if _constants.has(channel):
		return _constants[channel]
	return Color(0, 0, 0, 0)


func _finish(channel: String, color: Color) -> Color:
	if channel == "normal":
		var green := 1.0 - color.g if flip_normal_green else color.g
		return Color((color.r - 0.5) * _normal_scale + 0.5, (green - 0.5) * _normal_scale + 0.5, color.b, 1.0)
	if GDDrawMaterialChannels.is_scalar(channel):
		var value := GDDrawMaterialChannels.extract_channel_value(color, int(_selectors.get(channel, 4)))
		value = clampf(value * _tint_value(channel), 0.0, 1.0)
		return Color(value, value, value, 1.0)
	var tint: Color = _tints.get(channel, Color.WHITE)
	if channel == "emission" and _emission_adds:
		return Color(minf(color.r + tint.r, 1.0), minf(color.g + tint.g, 1.0), minf(color.b + tint.b, 1.0), color.a)
	return Color(color.r * tint.r, color.g * tint.g, color.b * tint.b, color.a * tint.a)


func _tint_value(channel: String) -> float:
	var tint: Color = _tints.get(channel, Color.WHITE)
	return tint.r


func _sample_bilinear(image: Image, uv: Vector2) -> Color:
	var width := image.get_width()
	var height := image.get_height()
	var fx := (uv.x - floorf(uv.x)) * float(width) - 0.5
	var fy := (uv.y - floorf(uv.y)) * float(height) - 0.5
	var x0 := floori(fx)
	var y0 := floori(fy)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var x1 := posmod(x0 + 1, width)
	var y1 := posmod(y0 + 1, height)
	x0 = posmod(x0, width)
	y0 = posmod(y0, height)
	var top := image.get_pixel(x0, y0).lerp(image.get_pixel(x1, y0), tx)
	var bottom := image.get_pixel(x0, y1).lerp(image.get_pixel(x1, y1), tx)
	return top.lerp(bottom, ty)


# --------------------------------------------------------------------------- loading

func _load_material(path: String, error: Array) -> bool:
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	var material := resource as BaseMaterial3D
	if material == null:
		error.push_back("%s is not a StandardMaterial3D." % path.get_file())
		return false
	return _read_material(material, path.get_file().get_basename(), error)


func _read_material(material: BaseMaterial3D, name_text: String, _error: Array) -> bool:
	source_material = material
	_emission_adds = material.emission_operator == BaseMaterial3D.EMISSION_OP_ADD
	display_name = name_text if name_text != "" else "Material"
	for channel in GDDrawMaterialChannels.ids():
		var definition := GDDrawMaterialChannels.get_definition(channel)
		var enable := str(definition["enable"])
		if enable != "" and not bool(material.get(enable)):
			continue
		var texture := GDDrawMaterialChannels.read_texture(material, channel)
		var image := _image_from_texture(texture) if texture else null
		if channel == "normal":
			if image != null:
				_images[channel] = image
				_selectors[channel] = 0
				_normal_scale = material.normal_scale
			continue
		var selector_property := str(definition["selector"])
		var value_property := str(definition["value"])
		if image != null:
			_images[channel] = image
			if selector_property != "":
				_selectors[channel] = int(material.get(selector_property))
			else:
				_selectors[channel] = 0
			if channel == "albedo":
				_tints[channel] = material.albedo_color
			elif value_property != "":
				var multiplier = material.get(value_property)
				_tints[channel] = multiplier if multiplier is Color else Color(float(multiplier), float(multiplier), float(multiplier), 1.0)
		elif channel == "albedo":
			_constants[channel] = material.albedo_color
		elif value_property != "":
			var value = material.get(value_property)
			if value is Color:
				if channel == "emission":
					_constants[channel] = Color(value.r, value.g, value.b, 1.0)
			else:
				var scalar := clampf(float(value), 0.0, 1.0)
				_constants[channel] = Color(scalar, scalar, scalar, 1.0)
	# An ORMMaterial3D keeps ambient occlusion (R), roughness (G) and metallic (B) in one packed texture; the
	# constants read above (roughness 1, metallic 0) are not what it renders.
	var packed_orm = material.get("orm_texture")
	if packed_orm is Texture2D:
		_add_packed_orm(_image_from_texture(packed_orm))
	return true


func _add_packed_orm(image: Image) -> void:
	if image == null:
		return
	for entry in ORM_CHANNELS:
		var channel: String = entry[0]
		if _images.has(channel):
			continue
		_images[channel] = image
		_selectors[channel] = int(entry[1])
		_tints.erase(channel)
		_constants.erase(channel)


## The values of the material's settings that decide how the painted channels look, for the channels this set
## has a texture for: {"height": {"heightmap_scale": 5.0, ...}, ...}. A texture set or baked shader has no such
## settings; a height map then gets deep parallax with layers, because Godot's default (plain parallax) smears
## and spikes at any high-contrast edge (brick joints, cell borders). The height scale is left alone.
func target_settings() -> Dictionary:
	var result := {}
	if source_material == null:
		if has_texture("height"):
			result["height"] = {"heightmap_deep_parallax": true, "heightmap_min_layers": 8, "heightmap_max_layers": 32}
		return result
	for channel: String in SETTING_PROPERTIES:
		if not has_texture(channel):
			continue
		var values := {}
		for property_name: String in SETTING_PROPERTIES[channel]:
			values[property_name] = source_material.get(property_name)
		result[channel] = values
	return result


func _load_texture_set(path: String, error: Array) -> bool:
	var directory := path.get_base_dir()
	var picked_base := path.get_file().get_basename()
	var classified := classify_file_name(picked_base)
	var prefix := str(classified[1])
	display_name = name_for_path(path)

	var found: Dictionary = {}
	if str(classified[0]) == "":
		# An image without a channel word is a plain albedo texture.
		found["albedo"] = path
	else:
		var access := DirAccess.open(directory)
		if access == null:
			error.push_back("Could not read the folder %s." % directory)
			return false
		for file_name in access.get_files():
			if file_name.get_extension().to_lower() not in IMAGE_EXTENSIONS:
				continue
			var other := classify_file_name(file_name.get_basename())
			if (str(other[0]) not in GDDrawMaterialChannels.ids() and str(other[0]) != "orm") or str(other[1]) != prefix or found.has(str(other[0])):
				continue
			found[str(other[0])] = directory.path_join(file_name)
		found[str(classified[0])] = path
	for channel: String in found:
		var image := _load_image_file(str(found[channel]))
		if image == null:
			continue
		if channel == "orm":
			continue
		_images[channel] = image
		_selectors[channel] = 4
	if found.has("orm"):
		# packed occlusion / roughness / metallic; separate files for those channels win over it
		_add_packed_orm(_load_image_file(str(found["orm"])))
	if _images.has("normal"):
		# DirectX normal maps (normal_dx, NormalDX, ...) have an inverted green channel
		var normal_name := str(found["normal"]).get_file().get_basename().to_lower()
		flip_normal_green = normal_name.contains("normaldx") or normal_name.contains("directx") or normal_name.contains("_dx") or normal_name.contains("-dx") or normal_name.ends_with("dx")
	if _images.is_empty():
		error.push_back("Could not read the images of %s." % path.get_file())
		return false
	return true


func _load_image_file(path: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
	return _prepare(image)


func _image_from_texture(texture: Texture2D) -> Image:
	if texture == null:
		return null
	if texture.resource_path.begins_with("res://") and texture.resource_path.get_extension().to_lower() in IMAGE_EXTENSIONS:
		var from_file := _load_image_file(texture.resource_path)
		if from_file != null:
			return from_file
	return _prepare(texture.get_image())


func _prepare(image: Image) -> Image:
	if image == null or image.is_empty():
		return null
	var prepared := image.duplicate() as Image
	if prepared.is_compressed() and prepared.decompress() != OK:
		return null
	if prepared.has_mipmaps():
		prepared.clear_mipmaps()
	if prepared.get_format() != Image.FORMAT_RGBA8 and prepared.get_format() != Image.FORMAT_RGBAF:
		prepared.convert(Image.FORMAT_RGBA8)
	return prepared
