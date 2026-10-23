@tool
class_name GDDrawMaterialChannels
extends RefCounted

## The StandardMaterial3D texture slots ("channels") GDDraw can paint in 3D, and the helpers
## that create, read and assign them. The painting core is channel-agnostic: it paints RGBA
## image layers. A channel only decides WHICH material texture those pixels belong to, and
## how new textures are prepared.
##
## Scalar channels (roughness, metallic, ambient occlusion, height) are painted as gray
## (R = G = B = value), so they read correctly whatever channel selector the material uses.
## A texture that is packed with other channels (for example a glTF metallic-roughness
## texture) is never overwritten: GDDraw creates a separate dedicated texture for the channel
## and leaves the packed one to the other channels.

const ALBEDO := "albedo"
## BaseMaterial3D.TEXTURE_CHANNEL_RED
const TEXTURE_CHANNEL_RED := 0

## kind:       "color" or "scalar"
## texture:    the material property holding the texture
## enable:     property that must be true for the texture to have any effect ("" if none)
## value:      property that MULTIPLIES the texture ("" if none); a new texture bakes it in. (Emission is
##             only multiplied with the Multiply operator, which a new emission texture switches on; with
##             Godot's default Add operator a white colour would light the whole surface white.)
## selector:   property choosing which texture channel is read ("" if none)
## default:    initial gray for scalar channels without a value property (height starts white: with a
##             white heightmap Godot's parallax shifts nothing, so the surface looks exactly as before)
const CHANNELS := [
	{"id": "albedo", "label": "Albedo", "kind": "color", "texture": "albedo_texture", "enable": "", "value": "", "selector": "", "default": 1.0},
	{"id": "emission", "label": "Emission", "kind": "color", "texture": "emission_texture", "enable": "emission_enabled", "value": "emission", "selector": "", "default": 0.0},
	{"id": "roughness", "label": "Roughness", "kind": "scalar", "texture": "roughness_texture", "enable": "", "value": "roughness", "selector": "roughness_texture_channel", "default": 1.0},
	{"id": "metallic", "label": "Metallic", "kind": "scalar", "texture": "metallic_texture", "enable": "", "value": "metallic", "selector": "metallic_texture_channel", "default": 0.0},
	{"id": "ao", "label": "Ambient Occlusion", "kind": "scalar", "texture": "ao_texture", "enable": "ao_enabled", "value": "", "selector": "ao_texture_channel", "default": 1.0},
	{"id": "height", "label": "Height", "kind": "scalar", "texture": "heightmap_texture", "enable": "heightmap_enabled", "value": "", "selector": "", "default": 1.0},
	{"id": "normal", "label": "Normal", "kind": "color", "texture": "normal_texture", "enable": "normal_enabled", "value": "normal_scale", "selector": "", "default": 1.0},
]

## Every texture property of a StandardMaterial3D that another channel's texture could be
## packed into. Used to detect packed textures.
const OTHER_TEXTURE_PROPERTIES := [
	"albedo_texture", "emission_texture", "roughness_texture", "metallic_texture", "ao_texture",
	"heightmap_texture", "normal_texture", "rim_texture", "clearcoat_texture", "anisotropy_flowmap",
	"subsurf_scatter_texture", "subsurf_scatter_transmittance_texture", "backlight_texture",
	"detail_mask", "detail_albedo", "detail_normal",
]


static func ids() -> PackedStringArray:
	var result := PackedStringArray()
	for definition: Dictionary in CHANNELS:
		result.push_back(str(definition["id"]))
	return result


static func has_channel(channel: String) -> bool:
	for definition: Dictionary in CHANNELS:
		if definition["id"] == channel:
			return true
	return false


## Unknown ids fall back to albedo, so a stale or hand-edited value can never break painting.
static func get_definition(channel: String) -> Dictionary:
	for definition: Dictionary in CHANNELS:
		if definition["id"] == channel:
			return definition
	return CHANNELS[0]


static func label(channel: String) -> String:
	return str(get_definition(channel)["label"])


static func is_scalar(channel: String) -> bool:
	return str(get_definition(channel)["kind"]) == "scalar"


static func texture_property(channel: String) -> String:
	return str(get_definition(channel)["texture"])


static func file_suffix(channel: String) -> String:
	return str(get_definition(channel)["id"])


## The raw texture in the channel's slot (possibly packed with other channels), or null.
static func read_texture(material: Material, channel: String) -> Texture2D:
	if material == null:
		return null
	return material.get(texture_property(channel)) as Texture2D


## Sets only the texture property (no enable flags or values). Returns whether it took effect.
static func write_texture(material: Material, channel: String, texture: Texture2D) -> bool:
	if material == null:
		return false
	material.set(texture_property(channel), texture)
	return material.get(texture_property(channel)) == texture


static func _same_texture(left: Texture2D, right: Texture2D) -> bool:
	if left == right:
		return true
	return not left.resource_path.is_empty() and left.resource_path == right.resource_path


## True when the channel's texture is also used by another texture slot of the same
## material (a packed texture). Albedo is never considered packed.
static func is_packed(material: Material, channel: String) -> bool:
	if channel == ALBEDO or material == null:
		return false
	var own := read_texture(material, channel)
	if own == null:
		return false
	var own_property := texture_property(channel)
	for property_name: String in OTHER_TEXTURE_PROPERTIES:
		if property_name == own_property:
			continue
		var other := material.get(property_name) as Texture2D
		if other != null and _same_texture(own, other):
			return true
	return false


## The texture GDDraw may paint directly: null when the slot is empty OR packed, in which
## case a dedicated texture has to be created first.
static func get_editable_texture(material: Material, channel: String) -> Texture2D:
	var texture := read_texture(material, channel)
	if texture != null and is_packed(material, channel):
		return null
	return texture


## Everything to set on the material when a NEW dedicated texture is assigned: the texture
## itself plus the switches that make it effective and the multiplier it replaces
## (the multiplier's value is baked into the texture, see make_initial_image()).
## Each entry: {"property": String, "value": Variant}.
static func property_changes_for_new_texture(channel: String, texture: Texture2D) -> Array[Dictionary]:
	var definition := get_definition(channel)
	var changes: Array[Dictionary] = [{"property": str(definition["texture"]), "value": texture}]
	if channel == ALBEDO:
		return changes
	if str(definition["enable"]) != "":
		changes.push_back({"property": str(definition["enable"]), "value": true})
	if str(definition["value"]) != "":
		changes.push_back({"property": str(definition["value"]), "value": Color.WHITE if channel == "emission" else 1.0})
	if channel == "emission":
		# With the default Add operator, emission = colour + texture: a white colour would make everything glow.
		changes.push_back({"property": "emission_operator", "value": BaseMaterial3D.EMISSION_OP_MULTIPLY})
	if str(definition["selector"]) != "":
		changes.push_back({"property": str(definition["selector"]), "value": TEXTURE_CHANNEL_RED})
	return changes


static func extract_channel_value(color: Color, selector: int) -> float:
	match selector:
		1:
			return color.g
		2:
			return color.b
		3:
			return color.a
		4:
			return color.get_luminance()
		_:
			return color.r


## The gray (or color) a brand-new texture starts with, so that switching the material to
## the texture does not change how it looks.
static func initial_fill_color(material: Material, channel: String) -> Color:
	var definition := get_definition(channel)
	if channel == "normal":
		# a flat normal map: every normal points straight out of the surface (0.5, 0.5, 1.0 encoded)
		return Color(0.5, 0.5, 1.0, 1.0)
	if not is_scalar(channel):
		# Only the Add operator lights a surface from the colour alone; Multiply without a texture is black.
		if channel == "emission" and material != null and bool(material.get("emission_enabled")) and int(material.get("emission_operator")) == BaseMaterial3D.EMISSION_OP_ADD:
			var emission: Color = material.get("emission")
			return Color(emission.r, emission.g, emission.b, 1.0)
		return Color.BLACK if channel == "emission" else Color.WHITE
	var value := float(definition["default"])
	if material != null and str(definition["value"]) != "":
		value = float(material.get(str(definition["value"])))
	value = clampf(value, 0.0, 1.0)
	return Color(value, value, value, 1.0)


## Size for a new channel texture: the material's albedo texture size when it has one (so all
## channels of a surface share the UV resolution), otherwise `fallback`.
static func matching_size(material: Material, fallback: Vector2i) -> Vector2i:
	var albedo := read_texture(material, ALBEDO)
	if albedo != null and albedo.get_width() > 0 and albedo.get_height() > 0:
		return Vector2i(albedo.get_width(), albedo.get_height())
	return Vector2i(maxi(16, fallback.x), maxi(16, fallback.y))


## Builds the pixels of a new dedicated texture for `channel`. When the material's slot
## currently holds a packed texture, that channel is unpacked from it (times the material's
## multiplier); otherwise the image is filled from the material's current value.
static func make_initial_image(material: Material, channel: String, size: Vector2i) -> Image:
	var definition := get_definition(channel)
	var source := read_texture(material, channel)
	if source != null and is_scalar(channel):
		var source_image := source.get_image()
		if source_image != null and not source_image.is_empty():
			var unpacked := source_image.duplicate() as Image
			if unpacked.is_compressed() and unpacked.decompress() != OK:
				unpacked = null
			if unpacked != null:
				if unpacked.has_mipmaps():
					unpacked.clear_mipmaps()
				if unpacked.get_format() != Image.FORMAT_RGBA8:
					unpacked.convert(Image.FORMAT_RGBA8)
				var selector := 0
				if str(definition["selector"]) != "":
					selector = int(material.get(str(definition["selector"])))
				var multiplier := 1.0
				if str(definition["value"]) != "":
					multiplier = float(material.get(str(definition["value"])))
				for y in range(unpacked.get_height()):
					for x in range(unpacked.get_width()):
						var value := clampf(extract_channel_value(unpacked.get_pixel(x, y), selector) * multiplier, 0.0, 1.0)
						unpacked.set_pixel(x, y, Color(value, value, value, 1.0))
				return unpacked
	var image := Image.create_empty(maxi(16, size.x), maxi(16, size.y), false, Image.FORMAT_RGBA8)
	image.fill(initial_fill_color(material, channel))
	return image


## Scalar channels are gray: the brush colour is reduced to its luminance.
static func constrain_color(color: Color, channel: String) -> Color:
	if not is_scalar(channel):
		return color
	var value := color.get_luminance()
	return Color(value, value, value, 1.0)


## Builds the material-picker choice for a non-albedo channel of a StandardMaterial3D.
## `target` is the GDDraw3DSurfaceTarget (used for its editable-texture-path rules).
static func build_choice(channel: String, slot: int, slot_name: String, material: StandardMaterial3D, target) -> Dictionary:
	var channel_label := label(channel)
	var texture := read_texture(material, channel)
	var packed := is_packed(material, channel)
	var path := ""
	var missing := texture == null or packed
	var supported := true
	var reason := ""
	var texture_label := ""
	if texture == null:
		texture_label = "%s · Missing texture" % channel_label
		reason = "Choose Open, then explicitly confirm creation of a new %s PNG texture, filled from the material's current value." % channel_label.to_lower()
	elif packed:
		texture_label = "%s · Packed texture (will be separated)" % channel_label
		reason = "This texture is shared with other material channels. GDDraw creates a separate %s texture from it and leaves the original for the other channels." % channel_label.to_lower()
	else:
		path = target.get_editable_texture_path(texture)
		var readable := false
		if path.is_empty():
			var image := texture.get_image()
			readable = image != null and not image.is_empty()
		supported = not path.is_empty() or readable
		texture_label = "%s · %s" % [channel_label, path.get_file() if not path.is_empty() else "non-file texture"]
		if not path.is_empty():
			reason = "Ready to edit."
		elif readable:
			reason = "Open this readable in-memory texture, then use Save As to create a PNG."
		else:
			reason = "The %s texture must be readable or backed by a res:// PNG, JPG, JPEG, or WebP file." % channel_label.to_lower()
	return {
		"slot": slot,
		"label": "%s · %s" % [slot_name, texture_label],
		"channel": channel,
		"supported": supported,
		"reason": reason,
		"missing_texture": missing,
		"missing_material": false,
		"texture_path": path,
	}
