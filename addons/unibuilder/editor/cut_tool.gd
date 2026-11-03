@tool
class_name UBCutTool
extends RefCounted
## Modal Cut tool: draws a sub-face onto a face of the edited mesh.


enum Stage { IDLE, PICK, DRAW }
enum SnapKind { NONE, VERTEX, EDGE }

const CLOSE_PX := 14.0
const ELEMENT_SNAP_PX := 12.0

var plugin: EditorPlugin
var stage := Stage.IDLE
var face := -1
## Drawn points in the node's local space, on the face plane.
var points: Array[Vector3] = []

var _plane_local := Plane()
var _cursor_local := Vector3.ZERO
var _has_cursor := false
var _snap_kind := SnapKind.NONE


func active() -> bool:
	return stage != Stage.IDLE


func begin() -> void:
	cancel()
	if plugin.edited != null and plugin.edited.mesh_data != null:
		stage = Stage.PICK


func cancel() -> void:
	stage = Stage.IDLE
	face = -1
	points.clear()
	_has_cursor = false
	_snap_kind = SnapKind.NONE


func handle_input(camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				cancel()
				plugin.update_overlays()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			KEY_ENTER, KEY_KP_ENTER:
				if stage == Stage.DRAW and points.size() >= 3:
					_commit()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			KEY_BACKSPACE:
				if stage == Stage.DRAW and not points.is_empty():
					points.pop_back()
					plugin.update_overlays()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		if stage == Stage.DRAW:
			_update_cursor(camera, event.position, event.ctrl_pressed)
			plugin.update_overlays()
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var node = plugin.edited
		match stage:
			Stage.PICK:
				var fi := UBPicking.pick_face(node, camera, event.position)
				if fi >= 0:
					face = fi
					var data: UBMeshData = node.mesh_data
					_plane_local = Plane(
						data.face_normal(data.faces[fi]), data.face_center(data.faces[fi]))
					stage = Stage.DRAW
			Stage.DRAW:
				_update_cursor(camera, event.position, event.ctrl_pressed)
				if not _has_cursor:
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				if points.size() >= 3 and _near_first_point(camera, event.position):
					_commit()
				else:
					points.append(_cursor_local)
		plugin.update_overlays()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func draw_overlay(overlay: Control, camera: Camera3D) -> void:
	if camera == null or not active():
		return
	var node = plugin.edited
	if node == null or node.mesh_data == null:
		return

	var accent := Color(0.369, 0.918, 0.831)
	if stage == Stage.DRAW and face >= 0 and face < node.mesh_data.faces.size():

		var data: UBMeshData = node.mesh_data
		var verts: PackedInt32Array = data.faces[face].vertices
		for i in verts.size():
			_segment(overlay, camera, node,
				data.positions[verts[i]], data.positions[verts[(i + 1) % verts.size()]],
				Color(accent, 0.5))
		for i in points.size():
			var closable := i == 0 and points.size() >= 3
			_marker(overlay, camera, node, points[i], Color(0.984, 0.749, 0.141) if closable else accent)
			if i > 0:
				_segment(overlay, camera, node, points[i - 1], points[i], accent)
		if _has_cursor:
			if not points.is_empty():
				_segment(overlay, camera, node, points.back(), _cursor_local, Color(accent, 0.5))

			var cursor_col := Color(0.984, 0.749, 0.141) if _snap_kind != SnapKind.NONE else accent
			_marker(overlay, camera, node, _cursor_local, cursor_col)


func _update_cursor(camera: Camera3D, pos: Vector2, invert_snap := false) -> void:
	var node = plugin.edited
	var inv: Transform3D = node.global_transform.affine_inverse()
	var origin := inv * camera.project_ray_origin(pos)
	var dir := (inv.basis * camera.project_ray_normal(pos)).normalized()
	var hit = _plane_local.intersects_ray(origin, dir)
	_has_cursor = hit != null
	if _has_cursor:
		_cursor_local = hit
		_apply_snap(camera, pos, invert_snap)


func _apply_snap(camera: Camera3D, pos: Vector2, invert: bool) -> void:
	_snap_kind = SnapKind.NONE
	var tb = plugin.toolbar
	if tb == null or face < 0:
		return
	var snap_on: bool = tb.snap_enabled != invert
	if not snap_on:
		return
	var data: UBMeshData = plugin.edited.mesh_data
	if data == null or face >= data.faces.size():
		return
	var step: float = maxf(tb.snap_step, 0.001)
	if _snap_to_elements(camera, pos, plugin.edited.global_transform, data, step):
		return
	var frame := lattice_frame(_plane_local.normal, data.positions[data.faces[face].vertices[0]])
	_cursor_local = snap_to_lattice(_cursor_local, frame, step)


## The cut's 2D lattice frame in the face plane.
static func lattice_frame(n: Vector3, anchor: Vector3) -> Dictionary:
	var axis := Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.UP
	var u := (axis - n * axis.dot(n)).normalized()
	return {"anchor": anchor, "u": u, "w": n.cross(u)}


## `p` snapped to the nearest lattice crossing (both in-plane coordinates).
static func snap_to_lattice(p: Vector3, frame: Dictionary, step: float) -> Vector3:
	var anchor: Vector3 = frame.anchor
	var u: Vector3 = frame.u
	var w: Vector3 = frame.w
	var d := p - anchor
	return anchor + u * snappedf(d.dot(u), step) + w * snappedf(d.dot(w), step)


## The point of edge `a`->`b` nearest `p`, snapped along the edge onto the lattice.
static func snap_on_edge(p: Vector3, a: Vector3, b: Vector3, frame: Dictionary, step: float) -> Vector3:
	var e := b - a
	var len_sq := e.length_squared()
	if len_sq < 1e-12:
		return a
	var cp := Geometry3D.get_closest_point_to_segment(p, a, b)
	if step <= 0.0:
		return cp
	var anchor: Vector3 = frame.anchor
	var axis: Vector3 = frame.u if absf(e.dot(frame.u)) >= absf(e.dot(frame.w)) else frame.w
	var ek := e.dot(axis)
	if absf(ek) < 1e-9:
		return cp
	var target := snappedf((cp - anchor).dot(axis), step)
	var t := (target - (a - anchor).dot(axis)) / ek
	return a + e * clampf(t, 0.0, 1.0)


func _snap_to_elements(camera: Camera3D, pos: Vector2, xf: Transform3D, data: UBMeshData, step: float) -> bool:
	var verts: PackedInt32Array = data.faces[face].vertices
	var best := ELEMENT_SNAP_PX
	var best_local := Vector3.ZERO
	var kind := SnapKind.NONE
	for vi in verts:
		var wp: Vector3 = xf * data.positions[vi]
		if camera.is_position_behind(wp):
			continue
		var d := camera.unproject_position(wp).distance_to(pos)
		if d < best:
			best = d
			best_local = data.positions[vi]
			kind = SnapKind.VERTEX
	if kind == SnapKind.NONE:
		var frame := lattice_frame(_plane_local.normal, data.positions[verts[0]])
		for i in verts.size():
			var a: Vector3 = data.positions[verts[i]]
			var b: Vector3 = data.positions[verts[(i + 1) % verts.size()]]
			var cp := Geometry3D.get_closest_point_to_segment(_cursor_local, a, b)
			var wp: Vector3 = xf * cp
			if camera.is_position_behind(wp):
				continue
			var d := camera.unproject_position(wp).distance_to(pos)
			if d < best:
				best = d
				best_local = snap_on_edge(_cursor_local, a, b, frame, step)
				kind = SnapKind.EDGE
				if best_local.is_equal_approx(a) or best_local.is_equal_approx(b):
					kind = SnapKind.VERTEX
	if kind == SnapKind.NONE:
		return false
	_cursor_local = best_local
	_snap_kind = kind
	return true


func _near_first_point(camera: Camera3D, pos: Vector2) -> bool:
	var wp: Vector3 = plugin.edited.global_transform * points[0]
	if camera.is_position_behind(wp):
		return false
	return camera.unproject_position(wp).distance_to(pos) <= CLOSE_PX


func _commit() -> void:
	var data: UBMeshData = plugin.edited.mesh_data
	var target := face
	var poly := PackedVector3Array(points)
	var faces_before := data.faces.size()
	plugin.commit_cut(target, poly)

	if data.faces.size() > faces_before:
		var sel: UBSelection = plugin.selection
		sel.mode = UBSelection.Mode.FACE
		sel.select_keys([data.faces.size() - 1], false)
	cancel()
	plugin.update_overlays()


func _marker(overlay: Control, camera: Camera3D, node, local: Vector3, color: Color) -> void:
	var wp: Vector3 = node.global_transform * local
	if camera.is_position_behind(wp):
		return
	var p := camera.unproject_position(wp)
	overlay.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), color, false, 2.0)


func _segment(overlay: Control, camera: Camera3D, node, a: Vector3, b: Vector3, color: Color) -> void:
	var wa: Vector3 = node.global_transform * a
	var wb: Vector3 = node.global_transform * b
	if camera.is_position_behind(wa) or camera.is_position_behind(wb):
		return
	overlay.draw_line(camera.unproject_position(wa), camera.unproject_position(wb), color, 2.0, true)
