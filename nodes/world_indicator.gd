class_name WorldIndicator extends Control

const WIDTH := 360.0
const DIAMOND_Y := 14.0

var label:Label

func setup(text:String) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 60)
	size = Vector2(WIDTH, 60)
	label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.position = Vector2(0, DIAMOND_Y + 16)
	label.size = Vector2(WIDTH, 28)

func _draw() -> void:
	var c := Vector2(WIDTH / 2.0, DIAMOND_Y)
	draw_colored_polygon(_diamond(c, 14.0), Color(0, 0, 0, 0.8)) # outline
	draw_colored_polygon(_diamond(c, 10.0), Color(0.9, 0.1, 0.1))

func _diamond(c:Vector2, r:float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])

# Fully visible beyond "far", fully invisible within "near"
func place(cam:Camera3D, world_pos:Vector3, near:float, far:float) -> void:
	if cam.is_position_behind(world_pos):
		visible = false
		return
	var d := cam.global_position.distance_to(world_pos)
	var a := clampf((d - near) / maxf(far - near, 0.01), 0.0, 1.0)
	visible = a > 0.01
	modulate.a = a
	position = cam.unproject_position(world_pos) - Vector2(WIDTH / 2.0, DIAMOND_Y)
