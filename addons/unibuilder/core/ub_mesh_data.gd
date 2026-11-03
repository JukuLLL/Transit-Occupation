@tool
class_name UBMeshData
extends Resource
## The editable mesh: shared vertex positions plus n-gon faces.


@export var positions := PackedVector3Array()
@export var faces: Array[UBFace] = []
@export var material_slots: Array[Material] = []


## The recipe this mesh was drawn from, so its shape parameters can be reopened.
@export var shape_spec: Dictionary = {}


## Hidden storage property that makes a duplicated mesh own its containers.
const OWN_CONTAINERS_PROP := &"_ub_own_containers"


func _get_property_list() -> Array[Dictionary]:
	return [{"name": OWN_CONTAINERS_PROP, "type": TYPE_OBJECT, "usage": PROPERTY_USAGE_STORAGE}]


func _set(property: StringName, _value: Variant) -> bool:
	if property == OWN_CONTAINERS_PROP:
		if resource_path.is_empty():
			own_containers()
		return true
	return false


## Replaces every container with a private copy.
func own_containers() -> void:
	positions = positions.duplicate()
	var owned: Array[UBFace] = []
	for f in faces:
		owned.append(f.duplicate_face())
	faces = owned
	material_slots = material_slots.duplicate()
	shape_spec = shape_spec.duplicate(true)


func add_vertex(p: Vector3) -> int:
	positions.append(p)
	return positions.size() - 1


func add_face(vertex_indices: PackedInt32Array, material_index := 0) -> UBFace:
	var face := UBFace.new()
	face.vertices = vertex_indices
	face.material_index = material_index
	faces.append(face)
	return face


## Returns the face's outward unit normal.
func face_normal(face: UBFace) -> Vector3:
	var pts := PackedVector3Array()
	for vi in face.vertices:
		pts.append(positions[vi])
	var n := UBTriangulate.newell_normal(pts)
	return -n.normalized() if n.length_squared() > 0.0 else Vector3.UP


func face_center(face: UBFace) -> Vector3:
	var c := Vector3.ZERO
	for vi in face.vertices:
		c += positions[vi]
	return c / maxf(1.0, float(face.vertices.size()))


## Emitted when only face or corner colors changed.
signal colors_changed


## Change counter, bumped by every announced mutation.
var version := 0


func notify_changed() -> void:
	version += 1
	emit_changed()


var _watertight := false
var _watertight_version := -1


## True when the mesh is closed and encloses a volume.
func is_watertight() -> bool:
	if _watertight_version != version:
		_watertight = not faces.is_empty() and UBOpBoolean.manifold_errors(self).is_empty()
		_watertight_version = version
	return _watertight


func notify_colors_changed() -> void:
	colors_changed.emit()


## Sets manual UV coords per face from a {face index: PackedVector2Array} map.
func apply_uv_coords(per_face: Dictionary) -> void:
	for fi in per_face:
		if fi is int and fi >= 0 and fi < faces.size():
			faces[fi].uv_coords = per_face[fi]


## Sets each face's frozen projection normal from a {face index: Vector3} map.
func apply_uv_axes(per_face: Dictionary) -> void:
	for fi in per_face:
		if fi is int and fi >= 0 and fi < faces.size():
			faces[fi].uv_axis = per_face[fi]


## Returns a deep copy for undo snapshots.
func duplicate_data() -> UBMeshData:
	var d := UBMeshData.new()
	d.positions = positions.duplicate()
	for f in faces:
		d.faces.append(f.duplicate_face())
	d.material_slots = material_slots.duplicate()
	d.shape_spec = shape_spec.duplicate(true)
	return d


## True when `other` describes exactly the same mesh.
func matches(other: UBMeshData) -> bool:
	if other == null or positions != other.positions or faces.size() != other.faces.size():
		return false
	if material_slots != other.material_slots:
		return false

	if shape_spec != other.shape_spec:
		return false
	for i in faces.size():
		var a: UBFace = faces[i]
		var b: UBFace = other.faces[i]
		if (
			a.vertices != b.vertices
			or a.material_index != b.material_index
			or a.smoothing_group != b.smoothing_group
			or a.color != b.color
			or a.color_corners != b.color_corners
			or a.uv_manual != b.uv_manual
			or a.uv_coords != b.uv_coords
			or a.uv_offset != b.uv_offset
			or a.uv_rotation != b.uv_rotation
			or a.uv_scale != b.uv_scale
			or a.uv_world_space != b.uv_world_space
			or a.uv_axis != b.uv_axis
		):
			return false
	return true


## True when `other` is this mesh apart from material assignment.
func same_shape(other: UBMeshData, eps := 1e-5) -> bool:
	if other == null or positions.size() != other.positions.size():
		return false
	if faces.size() != other.faces.size():
		return false
	for i in positions.size():

		if positions[i].distance_squared_to(other.positions[i]) > eps * eps \
				and not positions[i].is_equal_approx(other.positions[i]):
			return false
	for i in faces.size():
		var a: UBFace = faces[i]
		var b: UBFace = other.faces[i]
		if (
			a.vertices != b.vertices
			or a.smoothing_group != b.smoothing_group
			or a.color != b.color
			or a.color_corners != b.color_corners
			or a.uv_manual != b.uv_manual
			or a.uv_coords != b.uv_coords
			or a.uv_offset != b.uv_offset
			or a.uv_rotation != b.uv_rotation
			or a.uv_scale != b.uv_scale
			or a.uv_world_space != b.uv_world_space
			or a.uv_axis != b.uv_axis
		):
			return false
	return true


## Restores this mesh from a snapshot.
func copy_from(other: UBMeshData) -> void:
	positions = other.positions.duplicate()
	faces.clear()
	for f in other.faces:
		faces.append(f.duplicate_face())
	material_slots = other.material_slots.duplicate()
	shape_spec = other.shape_spec.duplicate(true)
	version += 1
	emit_changed()


## Returns a fingerprint of everything the compiler reads.
func content_hash() -> int:
	var parts: Array = [positions, material_slots.size()]
	for f in faces:
		parts.append([
			f.vertices, f.material_index, f.smoothing_group, f.color, f.color_corners,
			f.uv_manual, f.uv_coords, f.uv_offset, f.uv_rotation, f.uv_scale,
			f.uv_world_space, f.uv_axis,
		])
	return hash(parts)


## True when any face anchors its auto UVs in world space.
func uses_world_space_uvs() -> bool:
	for f in faces:
		if f.uv_world_space:
			return true
	return false


## Checks the topology invariants every op must keep; an empty result means sound.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for fi in faces.size():
		var verts := faces[fi].vertices
		if verts.size() < 3:
			errors.append("Face %d has fewer than 3 vertices" % fi)
		var seen := {}
		for vi in verts:
			if vi < 0 or vi >= positions.size():
				errors.append("Face %d references out-of-range vertex %d" % [fi, vi])
			elif seen.has(vi):
				errors.append("Face %d repeats vertex %d" % [fi, vi])
			seen[vi] = true
	var used := {}
	for f in faces:
		for vi in f.vertices:
			used[vi] = true
	for vi in positions.size():
		if not used.has(vi):
			errors.append("Vertex %d is not used by any face" % vi)
	if errors.is_empty():
		var topo := UBTopology.build(self)
		for key: Vector2i in topo.edge_faces:
			if topo.edge_faces[key].size() > 2:
				errors.append("Edge %s is shared by more than 2 faces" % str(key))
	return errors
