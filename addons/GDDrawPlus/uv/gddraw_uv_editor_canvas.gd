@tool
# Derived from Gator Model Studio (c) 2026 Blackwater Gator Studios, MIT License.
# See LICENSE-GatorModelStudio.txt. Modified for GDDraw: renamed classes, mesh-rebuild code removed,
# host hooks added to the editor window.
class_name GDDrawUVEditorCanvas
extends Control

signal mesh_commit_requested(mesh: GDDrawUVMeshData, action_name: String)
signal mesh_preview_requested(mesh: GDDrawUVMeshData)
signal mesh_preview_cancelled
signal selection_changed
signal select_mode_changed(mode: int)
signal status_changed(message: String)

enum SelectMode {
	VERTEX,
	EDGE,
	FACE,
	ISLAND,
}

enum TransformMode {
	NONE,
	MOVE,
	ROTATE,
	SCALE,
}

var mesh: GDDrawUVMeshData
var textures: Array[Texture2D] = []
var material_names: PackedStringArray = PackedStringArray()
var material_tile_count: int = 1
var select_mode: int = SelectMode.ISLAND
var show_checker: bool = true
var show_texture: bool = true
var show_distortion: bool = false
var show_seams: bool = true

var selected_corners: Array[Vector2i] = []
var selected_edges: Array[Vector2i] = []
var selected_faces: PackedInt32Array = PackedInt32Array()

var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
var _panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_value: Vector2 = Vector2.ZERO
var _transform_mode: int = TransformMode.NONE
var _transform_original: GDDrawUVMeshData
var _transform_preview: GDDrawUVMeshData
var _transform_start_mouse: Vector2 = Vector2.ZERO
var _transform_center: Vector2 = Vector2.ZERO
var _transform_start_vector: Vector2 = Vector2.RIGHT
var _box_selecting: bool = false
var _box_armed: bool = false
var _box_start: Vector2 = Vector2.ZERO
var _box_end: Vector2 = Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(560.0, 420.0)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	queue_redraw()


func set_data(
	new_mesh: GDDrawUVMeshData,
	new_textures: Array[Texture2D] = [],
	new_material_names: PackedStringArray = PackedStringArray()
) -> void:
	mesh = new_mesh
	textures.clear()
	for source_texture: Texture2D in new_textures:
		textures.append(source_texture)
	material_names = new_material_names.duplicate()
	material_tile_count = maxi(1, maxi(textures.size(), material_names.size()))
	if mesh != null:
		for face_index: int in mesh.faces.size():
			material_tile_count = maxi(material_tile_count, mesh.get_face_material(face_index) + 1)
	if _transform_mode == TransformMode.NONE:
		_transform_preview = null
	_prune_selection()
	queue_redraw()
	_emit_selection_status()


func set_select_mode(new_mode: int) -> void:
	var clamped_mode: int = clampi(new_mode, SelectMode.VERTEX, SelectMode.ISLAND)
	if select_mode == clamped_mode:
		return
	select_mode = clamped_mode
	clear_selection()
	select_mode_changed.emit(select_mode)


func clear_selection() -> void:
	selected_corners.clear()
	selected_edges.clear()
	selected_faces.clear()
	selection_changed.emit()
	queue_redraw()
	_emit_selection_status()


func select_all() -> void:
	clear_selection()
	if mesh == null or not mesh.has_uv_map:
		return
	match select_mode:
		SelectMode.VERTEX:
			selected_corners = GDDrawUVOperations.all_corners(mesh)
		SelectMode.EDGE:
			for face_index: int in mesh.faces.size():
				for corner_index: int in mesh.faces[face_index].size():
					selected_edges.append(Vector2i(face_index, corner_index))
		_:
			selected_faces = GDDrawUVOperations.all_faces(mesh)
	selection_changed.emit()
	queue_redraw()
	_emit_selection_status()


func frame_all() -> void:
	if mesh == null or not mesh.has_uv_map:
		zoom = 1.0
		pan = Vector2.ZERO
		queue_redraw()
		return
	var bounds: Rect2 = _get_material_tile_bounds(mesh)
	if bounds.size.x <= 0.00001 or bounds.size.y <= 0.00001:
		return
	var available: Vector2 = size - Vector2(48.0, 72.0)
	var base: float = _base_scale()
	zoom = clampf(minf(available.x / (bounds.size.x * base), available.y / (bounds.size.y * base)), 0.05, 100.0)
	var screen_center: Vector2 = size * 0.5
	var bounds_center_screen: Vector2 = _uv_to_screen_unpanned(bounds.get_center())
	pan = screen_center - bounds_center_screen
	queue_redraw()


func begin_transform(mode: int) -> void:
	if mesh == null or not mesh.has_uv_map:
		return
	var corners: Array[Vector2i] = get_selected_corners()
	if corners.is_empty():
		status_changed.emit("Select UV vertices, edges, faces, or islands first.")
		return
	_transform_mode = mode
	_transform_original = mesh.duplicate_mesh_data()
	_transform_preview = mesh.duplicate_mesh_data()
	_transform_start_mouse = get_local_mouse_position()
	_transform_center = _get_corner_material_tile_center(mesh, corners)
	_transform_start_vector = _screen_to_uv(_transform_start_mouse) - _transform_center
	if _transform_start_vector.length_squared() <= 0.000001:
		_transform_start_vector = Vector2.RIGHT
	grab_focus()
	status_changed.emit("Move the mouse; left-click or Enter confirms, right-click or Escape cancels.")


func cancel_transform() -> void:
	if _transform_mode == TransformMode.NONE:
		return
	_transform_mode = TransformMode.NONE
	_transform_original = null
	_transform_preview = null
	mesh_preview_cancelled.emit()
	queue_redraw()
	status_changed.emit("UV transform cancelled.")


func confirm_transform() -> void:
	if _transform_mode == TransformMode.NONE or _transform_preview == null:
		return
	var action_name: String = "Transform UVs"
	match _transform_mode:
		TransformMode.MOVE:
			action_name = "Move UVs"
		TransformMode.ROTATE:
			action_name = "Rotate UVs"
		TransformMode.SCALE:
			action_name = "Scale UVs"
	var committed: GDDrawUVMeshData = _transform_preview.duplicate_mesh_data()
	_transform_mode = TransformMode.NONE
	_transform_original = null
	_transform_preview = null
	mesh_commit_requested.emit(committed, action_name)
	status_changed.emit("%s applied." % action_name)


func get_selected_corners() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if mesh == null:
		return result
	match select_mode:
		SelectMode.VERTEX:
			result = selected_corners.duplicate()
		SelectMode.EDGE:
			for ref: Vector2i in selected_edges:
				_append_unique(result, ref)
				if ref.x >= 0 and ref.x < mesh.faces.size():
					_append_unique(result, Vector2i(ref.x, (ref.y + 1) % mesh.faces[ref.x].size()))
		_:
			for face_index: int in selected_faces:
				if face_index < 0 or face_index >= mesh.faces.size():
					continue
				for corner_index: int in mesh.faces[face_index].size():
					result.append(Vector2i(face_index, corner_index))
	return result


func get_selected_face_indices() -> PackedInt32Array:
	if mesh == null:
		return PackedInt32Array()
	if select_mode == SelectMode.FACE or select_mode == SelectMode.ISLAND:
		return selected_faces.duplicate()
	var result: PackedInt32Array = PackedInt32Array()
	for ref: Vector2i in get_selected_corners():
		if not result.has(ref.x):
			result.append(ref.x)
	return result


func get_selected_edge_refs() -> Array[Vector2i]:
	return selected_edges.duplicate()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
		return
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		_handle_key(event as InputEventKey)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	grab_focus()
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_zoom_at(event.position, 1.15)
		accept_event()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_zoom_at(event.position, 1.0 / 1.15)
		accept_event()
		return
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		if event.pressed:
			_pan_start_mouse = event.position
			_pan_start_value = pan
		accept_event()
		return
	if _transform_mode != TransformMode.NONE:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			confirm_transform()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_transform()
			accept_event()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		if _box_armed:
			_box_armed = false
			_box_selecting = true
			_box_start = event.position
			_box_end = event.position
			accept_event()
			return
		_pick_at(event.position, event.shift_pressed)
		accept_event()
	elif _box_selecting:
		_box_selecting = false
		_apply_box_selection(Rect2(_box_start, _box_end - _box_start).abs(), event.shift_pressed)
		queue_redraw()
		accept_event()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _panning:
		pan = _pan_start_value + event.position - _pan_start_mouse
		queue_redraw()
		accept_event()
		return
	if _box_selecting:
		_box_end = event.position
		queue_redraw()
		accept_event()
		return
	if _transform_mode != TransformMode.NONE:
		_update_transform_preview(event.position, event.shift_pressed)
		accept_event()


func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			if _transform_mode != TransformMode.NONE:
				cancel_transform()
		KEY_ENTER, KEY_KP_ENTER:
			if _transform_mode != TransformMode.NONE:
				confirm_transform()
		KEY_G:
			begin_transform(TransformMode.MOVE)
		KEY_R:
			begin_transform(TransformMode.ROTATE)
		KEY_S:
			begin_transform(TransformMode.SCALE)
		KEY_A:
			if event.alt_pressed:
				clear_selection()
			else:
				select_all()
		KEY_1:
			set_select_mode(SelectMode.VERTEX)
		KEY_2:
			set_select_mode(SelectMode.EDGE)
		KEY_3:
			set_select_mode(SelectMode.FACE)
		KEY_4:
			set_select_mode(SelectMode.ISLAND)
		KEY_HOME:
			frame_all()
		KEY_B:
			_box_armed = true
			status_changed.emit("Drag a box with the left mouse button. Hold Shift while releasing to add.")


func _update_transform_preview(mouse_position: Vector2, precision: bool) -> void:
	if _transform_original == null:
		return
	var corners: Array[Vector2i] = get_selected_corners()
	var sensitivity: float = 0.1 if precision else 1.0
	match _transform_mode:
		TransformMode.MOVE:
			var delta: Vector2 = (_screen_to_uv(mouse_position) - _screen_to_uv(_transform_start_mouse)) * sensitivity
			_transform_preview = _transform_material_tile_corners(
				_transform_original, corners, delta, Vector2.ONE, 0.0, _transform_center
			)
		TransformMode.ROTATE:
			var current: Vector2 = _screen_to_uv(mouse_position) - _transform_center
			if current.length_squared() <= 0.000001:
				return
			var angle: float = rad_to_deg(_transform_start_vector.angle_to(current)) * sensitivity
			_transform_preview = _transform_material_tile_corners(
				_transform_original, corners, Vector2.ZERO, Vector2.ONE, angle, _transform_center
			)
		TransformMode.SCALE:
			var start_length: float = maxf(_transform_start_vector.length(), 0.0001)
			var current_length: float = (_screen_to_uv(mouse_position) - _transform_center).length()
			var factor: float = lerpf(1.0, current_length / start_length, sensitivity)
			_transform_preview = _transform_material_tile_corners(
				_transform_original, corners, Vector2.ZERO, Vector2(factor, factor), 0.0, _transform_center
			)
	if _transform_preview != null:
		mesh_preview_requested.emit(_transform_preview)
	queue_redraw()


func _pick_at(position: Vector2, additive: bool) -> void:
	if mesh == null or not mesh.has_uv_map:
		return
	if not additive:
		selected_corners.clear()
		selected_edges.clear()
		selected_faces.clear()
	match select_mode:
		SelectMode.VERTEX:
			var corner: Vector2i = _pick_corner(position)
			if corner.x >= 0:
				_toggle_corner_group(corner, additive)
		SelectMode.EDGE:
			var edge_ref: Vector2i = _pick_edge(position)
			if edge_ref.x >= 0:
				_toggle_ref(selected_edges, edge_ref, additive)
		SelectMode.FACE:
			var face_index: int = _pick_face(position)
			if face_index >= 0:
				_toggle_face(face_index, additive)
		SelectMode.ISLAND:
			var island_face: int = _pick_face(position)
			if island_face >= 0:
				_toggle_island(island_face, additive)
	selection_changed.emit()
	queue_redraw()
	_emit_selection_status()


func _toggle_corner_group(ref: Vector2i, additive: bool) -> void:
	var group: Array[Vector2i] = _get_linked_corners(ref)
	var already_selected: bool = selected_corners.has(ref)
	for corner: Vector2i in group:
		if additive and already_selected:
			selected_corners.erase(corner)
		elif not selected_corners.has(corner):
			selected_corners.append(corner)


func _toggle_ref(values: Array[Vector2i], ref: Vector2i, additive: bool) -> void:
	if additive and values.has(ref):
		values.erase(ref)
	elif not values.has(ref):
		values.append(ref)


func _toggle_face(face_index: int, additive: bool) -> void:
	if additive and selected_faces.has(face_index):
		selected_faces.remove_at(selected_faces.find(face_index))
	elif not selected_faces.has(face_index):
		selected_faces.append(face_index)


func _toggle_island(face_index: int, additive: bool) -> void:
	for island: PackedInt32Array in _get_material_uv_islands(mesh):
		if not island.has(face_index):
			continue
		var removing: bool = additive and selected_faces.has(face_index)
		for member: int in island:
			if removing:
				if selected_faces.has(member):
					selected_faces.remove_at(selected_faces.find(member))
			elif not selected_faces.has(member):
				selected_faces.append(member)
		break


func _apply_box_selection(rect: Rect2, additive: bool) -> void:
	if mesh == null or not mesh.has_uv_map:
		return
	if not additive:
		selected_corners.clear()
		selected_edges.clear()
		selected_faces.clear()
	match select_mode:
		SelectMode.VERTEX:
			for ref: Vector2i in GDDrawUVOperations.all_corners(mesh):
				if rect.has_point(_uv_to_screen(_face_uv_to_material_tile(mesh, ref.x, mesh.uv_faces[ref.x][ref.y]))):
					for linked: Vector2i in _get_linked_corners(ref):
						_append_unique(selected_corners, linked)
		SelectMode.EDGE:
			for face_index: int in mesh.faces.size():
				for corner_index: int in mesh.faces[face_index].size():
					var next: int = (corner_index + 1) % mesh.faces[face_index].size()
					var middle: Vector2 = (
						_uv_to_screen(_face_uv_to_material_tile(mesh, face_index, mesh.uv_faces[face_index][corner_index]))
						+ _uv_to_screen(_face_uv_to_material_tile(mesh, face_index, mesh.uv_faces[face_index][next]))
					) * 0.5
					if rect.has_point(middle):
						selected_edges.append(Vector2i(face_index, corner_index))
		_:
			var hit_faces: PackedInt32Array = PackedInt32Array()
			for face_index: int in mesh.faces.size():
				var center: Vector2 = Vector2.ZERO
				for uv: Vector2 in mesh.uv_faces[face_index]:
					center += _uv_to_screen(_face_uv_to_material_tile(mesh, face_index, uv))
				center /= float(mesh.uv_faces[face_index].size())
				if rect.has_point(center):
					hit_faces.append(face_index)
			if select_mode == SelectMode.ISLAND:
				for island: PackedInt32Array in _get_material_uv_islands(mesh):
					var hit: bool = false
					for face_index: int in hit_faces:
						if island.has(face_index):
							hit = true
							break
					if not hit:
						continue
					for member: int in island:
						if not selected_faces.has(member):
							selected_faces.append(member)
			else:
				for face_index: int in hit_faces:
					if not selected_faces.has(face_index):
						selected_faces.append(face_index)
	selection_changed.emit()
	_emit_selection_status()


func _pick_corner(position: Vector2) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: float = 10.0
	for ref: Vector2i in GDDrawUVOperations.all_corners(mesh):
		var distance: float = position.distance_to(_uv_to_screen(_face_uv_to_material_tile(mesh, ref.x, mesh.uv_faces[ref.x][ref.y])))
		if distance < best_distance:
			best_distance = distance
			best = ref
	return best


func _pick_edge(position: Vector2) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: float = 8.0
	for face_index: int in mesh.faces.size():
		var count: int = mesh.faces[face_index].size()
		for corner_index: int in count:
			var a: Vector2 = _uv_to_screen(_face_uv_to_material_tile(mesh, face_index, mesh.uv_faces[face_index][corner_index]))
			var b: Vector2 = _uv_to_screen(_face_uv_to_material_tile(mesh, face_index, mesh.uv_faces[face_index][(corner_index + 1) % count]))
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(position, a, b)
			var distance: float = closest.distance_to(position)
			if distance < best_distance:
				best_distance = distance
				best = Vector2i(face_index, corner_index)
	return best


func _pick_face(position: Vector2) -> int:
	for face_index: int in range(mesh.faces.size() - 1, -1, -1):
		var polygon: PackedVector2Array = PackedVector2Array()
		for uv: Vector2 in mesh.uv_faces[face_index]:
			polygon.append(_uv_to_screen(_face_uv_to_material_tile(mesh, face_index, uv)))
		if _point_in_polygon(position, polygon):
			return face_index
	return -1


func _get_linked_corners(ref: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [ref]
	if mesh == null or not mesh.has_uv_map:
		return result
	var allowed_faces: Dictionary = {}
	for island: PackedInt32Array in _get_material_uv_islands(mesh):
		if island.has(ref.x):
			for face_index: int in island:
				allowed_faces[face_index] = true
			break
	var vertex_index: int = mesh.faces[ref.x][ref.y]
	var material_index: int = mesh.get_face_material(ref.x)
	var uv: Vector2 = mesh.uv_faces[ref.x][ref.y]
	for candidate: Vector2i in GDDrawUVOperations.all_corners(mesh):
		if candidate == ref or not allowed_faces.has(candidate.x):
			continue
		if mesh.faces[candidate.x][candidate.y] != vertex_index:
			continue
		if mesh.get_face_material(candidate.x) != material_index:
			continue
		if mesh.uv_faces[candidate.x][candidate.y].distance_squared_to(uv) <= 0.0000000001:
			result.append(candidate)
	return result


func _zoom_at(position: Vector2, factor: float) -> void:
	var before: Vector2 = _screen_to_uv(position)
	zoom = clampf(zoom * factor, 0.05, 100.0)
	var after_screen: Vector2 = _uv_to_screen(before)
	pan += position - after_screen
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.045, 0.05, 0.06, 1.0), true)
	var display_mesh: GDDrawUVMeshData = _transform_preview if _transform_preview != null else mesh
	_draw_uv_tiles()
	if display_mesh == null or not display_mesh.has_uv_map:
		_draw_message("No UV map. Use Auto Unwrap or a projection first.")
		return
	if show_distortion:
		_draw_distortion(display_mesh)
	_draw_faces(display_mesh)
	_draw_edges(display_mesh)
	_draw_vertices(display_mesh)
	if _box_selecting:
		var rect: Rect2 = Rect2(_box_start, _box_end - _box_start).abs()
		draw_rect(rect, Color(0.2, 0.55, 1.0, 0.15), true)
		draw_rect(rect, Color(0.3, 0.7, 1.0, 0.95), false, 1.0)


func _draw_uv_tiles() -> void:
	var tile_count: int = maxi(material_tile_count, 1)
	var font: Font = ThemeDB.fallback_font
	for tile_index: int in tile_count:
		var tile_origin: Vector2 = _uv_to_screen(Vector2(float(tile_index), 1.0))
		var tile_end: Vector2 = _uv_to_screen(Vector2(float(tile_index + 1), 0.0))
		var tile_rect: Rect2 = Rect2(tile_origin, tile_end - tile_origin).abs()
		if show_checker:
			var cells: int = 10
			var cell: Vector2 = tile_rect.size / float(cells)
			for y: int in cells:
				for x: int in cells:
					var colour: Color = Color(0.10, 0.11, 0.13, 1.0)
					if (x + y) % 2 != 0:
						colour = Color(0.18, 0.19, 0.22, 1.0)
					draw_rect(Rect2(tile_rect.position + Vector2(x, y) * cell, cell), colour, true)
		else:
			draw_rect(tile_rect, Color(0.09, 0.1, 0.12, 1.0), true)
		var tile_texture: Texture2D = textures[tile_index] if tile_index < textures.size() else null
		if show_texture and tile_texture != null:
			draw_texture_rect(tile_texture, tile_rect, false, Color(1.0, 1.0, 1.0, 0.68))
		for grid_index: int in 11:
			var fraction: float = float(grid_index) / 10.0
			var grid_colour: Color = Color(0.32, 0.34, 0.38, 0.5)
			if grid_index == 0 or grid_index == 10:
				grid_colour = Color(0.65, 0.68, 0.72, 0.9)
			var x_position: float = lerpf(tile_rect.position.x, tile_rect.end.x, fraction)
			var y_position: float = lerpf(tile_rect.position.y, tile_rect.end.y, fraction)
			draw_line(Vector2(x_position, tile_rect.position.y), Vector2(x_position, tile_rect.end.y), grid_colour, 1.0)
			draw_line(Vector2(tile_rect.position.x, y_position), Vector2(tile_rect.end.x, y_position), grid_colour, 1.0)
		var tile_name: String = "Material %d" % (tile_index + 1)
		if tile_index < material_names.size() and not material_names[tile_index].is_empty():
			tile_name = material_names[tile_index]
		var label: String = "%d  %s" % [tile_index + 1, tile_name]
		draw_string(
			font,
			tile_rect.position + Vector2(6.0, -7.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			maxf(tile_rect.size.x - 12.0, 32.0),
			13,
			Color(0.88, 0.9, 0.94, 0.95)
		)


func _draw_distortion(display_mesh: GDDrawUVMeshData) -> void:
	for face_index: int in display_mesh.faces.size():
		var polygon: PackedVector2Array = PackedVector2Array()
		for uv: Vector2 in display_mesh.uv_faces[face_index]:
			polygon.append(_uv_to_screen(_face_uv_to_material_tile(display_mesh, face_index, uv)))
		var distortion: float = clampf(GDDrawUVOperations.get_face_distortion(display_mesh, face_index), -2.0, 2.0)
		var colour: Color
		if distortion >= 0.0:
			colour = Color(1.0, 0.25, 0.12, 0.18 + absf(distortion) * 0.16)
		else:
			colour = Color(0.1, 0.45, 1.0, 0.18 + absf(distortion) * 0.16)
		draw_colored_polygon(polygon, colour)


func _draw_faces(display_mesh: GDDrawUVMeshData) -> void:
	for face_index: int in display_mesh.faces.size():
		if not selected_faces.has(face_index):
			continue
		var polygon: PackedVector2Array = PackedVector2Array()
		for uv: Vector2 in display_mesh.uv_faces[face_index]:
			polygon.append(_uv_to_screen(_face_uv_to_material_tile(display_mesh, face_index, uv)))
		draw_colored_polygon(polygon, Color(1.0, 0.48, 0.08, 0.22))


func _draw_edges(display_mesh: GDDrawUVMeshData) -> void:
	var boundary_edges: Dictionary = GDDrawUVOperations.get_uv_boundary_edges(display_mesh) if show_seams else {}
	for face_index: int in display_mesh.faces.size():
		var face: PackedInt32Array = display_mesh.faces[face_index]
		for corner_index: int in face.size():
			var next: int = (corner_index + 1) % face.size()
			var a: Vector2 = _uv_to_screen(_face_uv_to_material_tile(display_mesh, face_index, display_mesh.uv_faces[face_index][corner_index]))
			var b: Vector2 = _uv_to_screen(_face_uv_to_material_tile(display_mesh, face_index, display_mesh.uv_faces[face_index][next]))
			var ref: Vector2i = Vector2i(face_index, corner_index)
			var colour: Color = Color(0.72, 0.78, 0.86, 0.92)
			var width: float = 1.0
			var edge: Vector2i = GDDrawUVMeshData.canonical_edge(face[corner_index], face[next])
			if boundary_edges.has(edge):
				colour = Color(1.0, 0.18, 0.18, 1.0)
				width = 2.0
			if selected_edges.has(ref):
				colour = Color(1.0, 0.58, 0.12, 1.0)
				width = 3.0
			draw_line(a, b, colour, width, true)


func _draw_vertices(display_mesh: GDDrawUVMeshData) -> void:
	if select_mode != SelectMode.VERTEX:
		return
	for ref: Vector2i in GDDrawUVOperations.all_corners(display_mesh):
		var position: Vector2 = _uv_to_screen(_face_uv_to_material_tile(display_mesh, ref.x, display_mesh.uv_faces[ref.x][ref.y]))
		var selected: bool = selected_corners.has(ref)
		draw_circle(position, 4.5 if selected else 3.0, Color(1.0, 0.55, 0.1) if selected else Color(0.82, 0.88, 0.96))


func _get_face_material_tile(source_mesh: GDDrawUVMeshData, face_index: int) -> int:
	if source_mesh == null or face_index < 0 or face_index >= source_mesh.faces.size():
		return 0
	return maxi(source_mesh.get_face_material(face_index), 0)


func _face_uv_to_material_tile(source_mesh: GDDrawUVMeshData, face_index: int, uv: Vector2) -> Vector2:
	return uv + Vector2(float(_get_face_material_tile(source_mesh, face_index)), 0.0)


func _material_tile_uv_to_face(source_mesh: GDDrawUVMeshData, face_index: int, uv: Vector2) -> Vector2:
	return uv - Vector2(float(_get_face_material_tile(source_mesh, face_index)), 0.0)


func _get_material_tile_bounds(source_mesh: GDDrawUVMeshData) -> Rect2:
	var has_point: bool = false
	var minimum: Vector2 = Vector2.ZERO
	var maximum: Vector2 = Vector2.ZERO
	if source_mesh != null and source_mesh.has_uv_map:
		for face_index: int in source_mesh.uv_faces.size():
			for uv: Vector2 in source_mesh.uv_faces[face_index]:
				var tiled_uv: Vector2 = _face_uv_to_material_tile(source_mesh, face_index, uv)
				if not has_point:
					minimum = tiled_uv
					maximum = tiled_uv
					has_point = true
				else:
					minimum = Vector2(minf(minimum.x, tiled_uv.x), minf(minimum.y, tiled_uv.y))
					maximum = Vector2(maxf(maximum.x, tiled_uv.x), maxf(maximum.y, tiled_uv.y))
	if not has_point:
		return Rect2(Vector2.ZERO, Vector2(float(maxi(material_tile_count, 1)), 1.0))
	minimum = Vector2(minf(minimum.x, 0.0), minf(minimum.y, 0.0))
	maximum = Vector2(
		maxf(maximum.x, float(maxi(material_tile_count, 1))),
		maxf(maximum.y, 1.0)
	)
	return Rect2(minimum, maximum - minimum)


func _get_corner_material_tile_center(source_mesh: GDDrawUVMeshData, corners: Array[Vector2i]) -> Vector2:
	var center: Vector2 = Vector2.ZERO
	var count: int = 0
	if source_mesh == null or not source_mesh.has_uv_map:
		return Vector2(0.5, 0.5)
	for ref: Vector2i in corners:
		if ref.x < 0 or ref.x >= source_mesh.uv_faces.size():
			continue
		if ref.y < 0 or ref.y >= source_mesh.uv_faces[ref.x].size():
			continue
		center += _face_uv_to_material_tile(source_mesh, ref.x, source_mesh.uv_faces[ref.x][ref.y])
		count += 1
	return center / float(count) if count > 0 else Vector2(0.5, 0.5)


func _transform_material_tile_corners(
	source_mesh: GDDrawUVMeshData,
	corners: Array[Vector2i],
	offset: Vector2,
	scale_value: Vector2,
	rotation_degrees: float,
	pivot: Vector2
) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = source_mesh.duplicate_mesh_data_fast()
	var angle: float = deg_to_rad(rotation_degrees)
	var cosine: float = cos(angle)
	var sine: float = sin(angle)
	for ref: Vector2i in corners:
		if ref.x < 0 or ref.x >= result.uv_faces.size():
			continue
		if ref.y < 0 or ref.y >= result.uv_faces[ref.x].size():
			continue
		var tiled_uv: Vector2 = _face_uv_to_material_tile(source_mesh, ref.x, source_mesh.uv_faces[ref.x][ref.y])
		var relative: Vector2 = (tiled_uv - pivot) * scale_value
		var rotated: Vector2 = Vector2(
			relative.x * cosine - relative.y * sine,
			relative.x * sine + relative.y * cosine
		)
		var transformed: Vector2 = pivot + rotated + offset
		var face_uvs: PackedVector2Array = result.uv_faces[ref.x].duplicate()
		face_uvs[ref.y] = _material_tile_uv_to_face(result, ref.x, transformed)
		result.uv_faces[ref.x] = face_uvs
	result.has_uv_map = true
	return result


func _get_material_uv_islands(source_mesh: GDDrawUVMeshData) -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	if source_mesh == null or not source_mesh.has_uv_map:
		return result
	var groups: Array[PackedInt32Array] = []
	var group_count: int = 1
	for face_index: int in source_mesh.faces.size():
		group_count = maxi(group_count, source_mesh.get_face_material(face_index) + 1)
	groups.resize(group_count)
	for group_index: int in group_count:
		groups[group_index] = PackedInt32Array()
	for face_index: int in source_mesh.faces.size():
		var material_index: int = clampi(source_mesh.get_face_material(face_index), 0, group_count - 1)
		groups[material_index].append(face_index)
	for group: PackedInt32Array in groups:
		if group.is_empty():
			continue
		for island: PackedInt32Array in GDDrawUVOperations.get_uv_islands(source_mesh, group):
			result.append(island)
	return result


func _draw_message(message: String) -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 14
	var text_size: Vector2 = font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(font, (size - text_size) * 0.5 + Vector2(0.0, text_size.y), message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.7, 0.73, 0.78))


func _uv_to_screen(uv: Vector2) -> Vector2:
	return _uv_to_screen_unpanned(uv) + pan


func _uv_to_screen_unpanned(uv: Vector2) -> Vector2:
	var scale: float = _base_scale() * zoom
	return size * 0.5 + Vector2(uv.x - 0.5, 0.5 - uv.y) * scale


func _screen_to_uv(position: Vector2) -> Vector2:
	var scale: float = maxf(_base_scale() * zoom, 0.0001)
	var relative: Vector2 = position - pan - size * 0.5
	return Vector2(relative.x / scale + 0.5, 0.5 - relative.y / scale)


func _base_scale() -> float:
	return maxf(80.0, minf(size.x, size.y) * 0.72)


func _point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3:
		return false
	var inside: bool = false
	var j: int = polygon.size() - 1
	for i: int in polygon.size():
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[j]
		if ((a.y > point.y) != (b.y > point.y)):
			var denominator: float = b.y - a.y
			if absf(denominator) <= 0.0000001:
				j = i
				continue
			var cross_x: float = (b.x - a.x) * (point.y - a.y) / denominator + a.x
			if point.x < cross_x:
				inside = not inside
		j = i
	return inside


func _prune_selection() -> void:
	if mesh == null:
		clear_selection()
		return
	for index: int in range(selected_corners.size() - 1, -1, -1):
		var ref: Vector2i = selected_corners[index]
		if ref.x < 0 or ref.x >= mesh.faces.size() or ref.y < 0 or ref.y >= mesh.faces[ref.x].size():
			selected_corners.remove_at(index)
	for index: int in range(selected_edges.size() - 1, -1, -1):
		var ref: Vector2i = selected_edges[index]
		if ref.x < 0 or ref.x >= mesh.faces.size() or ref.y < 0 or ref.y >= mesh.faces[ref.x].size():
			selected_edges.remove_at(index)
	for index: int in range(selected_faces.size() - 1, -1, -1):
		if selected_faces[index] < 0 or selected_faces[index] >= mesh.faces.size():
			selected_faces.remove_at(index)


func _emit_selection_status() -> void:
	var text: String
	match select_mode:
		SelectMode.VERTEX:
			text = "%d UV vertices selected" % selected_corners.size()
		SelectMode.EDGE:
			text = "%d UV edges selected" % selected_edges.size()
		SelectMode.FACE:
			text = "%d UV faces selected" % selected_faces.size()
		_:
			var island_count: int = 0
			if mesh != null:
				for island: PackedInt32Array in _get_material_uv_islands(mesh):
					for face_index: int in island:
						if selected_faces.has(face_index):
							island_count += 1
							break
			text = "%d UV islands selected" % island_count
	status_changed.emit(text)


func _append_unique(values: Array[Vector2i], ref: Vector2i) -> void:
	if not values.has(ref):
		values.append(ref)
