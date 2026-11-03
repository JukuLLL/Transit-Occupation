@tool
class_name UBOpSetFaceProps
extends RefCounted
## Applies material, color, smoothing group and auto-UV settings to a set of faces.


## Assigns `material` to the faces, reusing or creating its slot; returns the slot.
static func assign_material(data, face_set: Dictionary, material: Material) -> int:
	var slot: int = data.material_slots.find(material)
	if slot < 0:
		slot = data.material_slots.size()
		for f in data.faces:
			slot = maxi(slot, f.material_index + 1)
		while data.material_slots.size() < slot:
			data.material_slots.append(null)
		data.material_slots.append(material)
	apply(data, face_set, {"material_index": slot})
	return slot


## Tiling range the face panel offers, and the clamp of the relative keys.
const UV_SCALE_MIN := 1.0 / 512.0
const UV_SCALE_MAX := 64.0


## Applies the keys present in `props` to every face in `face_set`.
static func apply(data, face_set: Dictionary, props: Dictionary) -> void:
	for fi in UBOpUtils.valid_faces(data, face_set):
		var f: UBFace = data.faces[fi]
		if props.has("material_index"):
			f.material_index = props.material_index
		if props.has("color"):
			f.color = props.color
		if props.has("smoothing_group"):
			f.smoothing_group = props.smoothing_group
		if props.has("uv_offset"):
			f.uv_offset = props.uv_offset
		if props.has("uv_offset_u"):
			f.uv_offset.x = props.uv_offset_u
		if props.has("uv_offset_v"):
			f.uv_offset.y = props.uv_offset_v
		if props.has("uv_rotation"):
			f.uv_rotation = props.uv_rotation
		if props.has("uv_scale"):
			f.uv_scale = props.uv_scale
		if props.has("uv_scale_u"):
			f.uv_scale.x = props.uv_scale_u
		if props.has("uv_scale_v"):
			f.uv_scale.y = props.uv_scale_v
		if props.has("uv_scale_equalize"):
			f.uv_scale.y = f.uv_scale.x
		if props.has("uv_scale_mul"):
			var k: Vector2 = props.uv_scale_mul
			f.uv_scale = Vector2(
				clampf(f.uv_scale.x * k.x, UV_SCALE_MIN, UV_SCALE_MAX),
				clampf(f.uv_scale.y * k.y, UV_SCALE_MIN, UV_SCALE_MAX))
		if props.has("uv_world_space"):
			f.uv_world_space = props.uv_world_space
		if props.has("uv_projection"):
			f.uv_axis = projection_axis(data, f, props.uv_projection)


## Whether uv_scale_mul `k` would change any face in `face_set`.
static func scale_mul_changes(data, face_set: Dictionary, k: Vector2) -> bool:
	for fi in UBOpUtils.valid_faces(data, face_set):
		var s: Vector2 = data.faces[fi].uv_scale
		var t := Vector2(clampf(s.x * k.x, UV_SCALE_MIN, UV_SCALE_MAX),
			clampf(s.y * k.y, UV_SCALE_MIN, UV_SCALE_MAX))
		if t != s:
			return true
	return false


## Which way the auto mapping projects a face (UBFace.uv_axis).
enum UVProjection { FACE, X, Y, Z }


## The uv_axis for a UVProjection choice.
static func projection_axis(data, face: UBFace, projection: int) -> Vector3:
	if projection < UVProjection.X or projection > UVProjection.Z:
		return Vector3.ZERO
	var axis := Vector3.ZERO
	axis[projection - 1] = 1.0
	return -axis if data.face_normal(face).dot(axis) < 0.0 else axis


## The UVProjection a face's uv_axis reads as, or -1.
static func projection_of(face: UBFace) -> int:
	if face.uv_axis == Vector3.ZERO:
		return UVProjection.FACE
	var n := face.uv_axis.normalized().abs()
	for i in 3:
		if n[i] > 1.0 - 1e-6:
			return UVProjection.X + i
	return -1
