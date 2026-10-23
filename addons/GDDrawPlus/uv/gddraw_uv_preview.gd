@tool
# Derived from Gator Model Studio (c) 2026 Blackwater Gator Studios, MIT License.
# See LICENSE-GatorModelStudio.txt. Modified for GDDraw: renamed classes, mesh-rebuild code removed,
# host hooks added to the editor window.
class_name GDDrawUVPreview
extends Control

const MAX_PREVIEW_FACES: int = 12000
const MAX_DENSE_SELECTED_FACES: int = 256
const CHECKER_CELL_COUNT: int = 10

var _mesh: GDDrawUVMeshData
var _selected_faces: PackedInt32Array = PackedInt32Array()
var _material_index: int = 0
var _texture: Texture2D


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 220.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	queue_redraw()


func set_uv_data(
	mesh: GDDrawUVMeshData,
	selected_faces: PackedInt32Array = PackedInt32Array(),
	material_index: int = 0,
	texture: Texture2D = null
) -> void:
	_mesh = mesh
	_selected_faces = selected_faces.duplicate()
	_material_index = maxi(material_index, 0)
	_texture = texture
	queue_redraw()


func set_selected_faces(selected_faces: PackedInt32Array) -> void:
	_selected_faces = selected_faces.duplicate()
	queue_redraw()


func _draw() -> void:
	var bounds: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color(0.055, 0.06, 0.07, 1.0), true)
	if size.x <= 2.0 or size.y <= 2.0:
		return

	var padding: float = 8.0
	var square_size: float = maxf(1.0, minf(size.x, size.y) - padding * 2.0)
	var origin: Vector2 = Vector2((size.x - square_size) * 0.5, (size.y - square_size) * 0.5)
	var uv_rect: Rect2 = Rect2(origin, Vector2(square_size, square_size))
	_draw_background(uv_rect)
	_draw_grid(origin, square_size)

	if _mesh == null or not _mesh.has_uv_map:
		_draw_centered_message("No UV map")
		return

	var material_faces: PackedInt32Array = _get_material_faces()
	if material_faces.is_empty():
		_draw_centered_message("No faces use this material")
		return

	var selected_lookup: Dictionary = {}
	for face_index: int in _selected_faces:
		selected_lookup[face_index] = true

	if material_faces.size() > MAX_PREVIEW_FACES:
		var draw_count: int = 0
		for face_index: int in _selected_faces:
			if draw_count >= MAX_DENSE_SELECTED_FACES:
				break
			if _mesh.get_face_material(face_index) != _material_index:
				continue
			_draw_uv_face(face_index, origin, square_size, true)
			draw_count += 1
		_draw_centered_message("Dense UV preview limited; use the Full UV Editor")
		return

	for face_index: int in material_faces:
		_draw_uv_face(face_index, origin, square_size, selected_lookup.has(face_index))


func _draw_background(uv_rect: Rect2) -> void:
	var cell_size: Vector2 = uv_rect.size / float(CHECKER_CELL_COUNT)
	for y: int in CHECKER_CELL_COUNT:
		for x: int in CHECKER_CELL_COUNT:
			var colour: Color = Color(0.10, 0.11, 0.13, 1.0)
			if (x + y) % 2 != 0:
				colour = Color(0.18, 0.19, 0.22, 1.0)
			draw_rect(
				Rect2(uv_rect.position + Vector2(float(x), float(y)) * cell_size, cell_size),
				colour,
				true
			)
	if _texture != null:
		draw_texture_rect(_texture, uv_rect, false, Color(1.0, 1.0, 1.0, 0.78))


func _draw_grid(origin: Vector2, square_size: float) -> void:
	for grid_index: int in range(11):
		var fraction: float = float(grid_index) / 10.0
		var grid_colour: Color = Color(0.2, 0.22, 0.25, 0.55)
		if grid_index == 0 or grid_index == 10:
			grid_colour = Color(0.62, 0.65, 0.7, 0.95)
		var x: float = origin.x + square_size * fraction
		var y: float = origin.y + square_size * fraction
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + square_size), grid_colour, 1.0)
		draw_line(Vector2(origin.x, y), Vector2(origin.x + square_size, y), grid_colour, 1.0)


func _get_material_faces() -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	if _mesh == null:
		return result
	for face_index: int in _mesh.faces.size():
		if _mesh.get_face_material(face_index) == _material_index:
			result.append(face_index)
	return result


func _draw_uv_face(
	face_index: int,
	origin: Vector2,
	square_size: float,
	selected: bool
) -> void:
	if _mesh == null or face_index < 0 or face_index >= _mesh.uv_faces.size():
		return
	var uvs: PackedVector2Array = _mesh.uv_faces[face_index]
	if uvs.size() < 2:
		return
	var points: PackedVector2Array = PackedVector2Array()
	for uv: Vector2 in uvs:
		points.append(origin + Vector2(uv.x, 1.0 - uv.y) * square_size)
	points.append(points[0])
	var colour: Color = Color(1.0, 0.58, 0.18, 1.0) if selected else Color(0.78, 0.9, 1.0, 0.95)
	var width: float = 2.0 if selected else 1.0
	draw_polyline(points, colour, width, true)


func _draw_centered_message(message: String) -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 13
	var text_size: Vector2 = font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(
		font,
		(size - text_size) * 0.5 + Vector2(0.0, text_size.y),
		message,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		Color(0.82, 0.84, 0.88, 1.0)
	)
