class_name PingMarker extends CanvasLayer

var world_pos:Vector3
var display_name:String = ""
var lifetime:float = 7.0

const BOX_SIZE := Vector2(160, 80)
const ICON_CENTER := Vector2(80, 40) # where the icon's center sits inside the box

var box:VBoxContainer
var distance_label:Label

func _ready() -> void:
	layer = 2
	
	box = VBoxContainer.new()
	box.custom_minimum_size = BOX_SIZE
	box.size = BOX_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	add_child(box)
	
	# Name above
	box.add_child(_make_label(display_name))
	
	# Icon in the middle
	var icon := TextureRect.new()
	icon.texture = _make_icon()
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	
	# Distance below
	distance_label = _make_label("")
	box.add_child(distance_label)

func _make_label(text:String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(0, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

# Draws a simple white diamond with a black outline, so no image file is needed
func _make_icon() -> ImageTexture:
	var s := 32
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var c := (s - 1) / 2.0
	for x in s:
		for y in s:
			var d := absf(x - c) + absf(y - c)
			if d <= 15.0:
				img.set_pixel(x, y, Color.BLACK if d > 11.0 else Color.WHITE)
	return ImageTexture.create_from_image(img)

func _process(delta:float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(world_pos):
		box.visible = false
		return
	
	box.visible = true
	box.position = cam.unproject_position(world_pos) - ICON_CENTER
	distance_label.text = "%dm" % roundi(cam.global_position.distance_to(world_pos))
