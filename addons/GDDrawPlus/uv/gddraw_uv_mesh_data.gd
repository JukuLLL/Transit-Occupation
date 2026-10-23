@tool
# Derived from Gator Model Studio (c) 2026 Blackwater Gator Studios, MIT License.
# See LICENSE-GatorModelStudio.txt. Modified for GDDraw: renamed classes, mesh-rebuild code removed,
# host hooks added to the editor window.
class_name GDDrawUVMeshData
extends Resource








@export var vertices: PackedVector3Array = PackedVector3Array()
@export var faces: Array[PackedInt32Array] = []
@export var loose_edges: Array[Vector2i] = []
@export var smooth_faces: PackedByteArray = PackedByteArray()
@export var uv_faces: Array[PackedVector2Array] = []
@export var has_uv_map: bool = false
@export var corner_normals: Array[PackedVector3Array] = []
@export var has_custom_normals: bool = false
@export var crease_edges: Array[Vector2i] = []
@export var crease_weights: PackedFloat32Array = PackedFloat32Array()
@export var seam_edges: Array[Vector2i] = []
@export var face_materials: PackedInt32Array = PackedInt32Array()
@export var uv_seam_analysis_pending: bool = false

var _change_revision: int = 1
var _position_revision: int = 1
var _topology_revision: int = 1
var _last_position_change_indices: PackedInt32Array = PackedInt32Array()
var _cache_enabled: bool = true
var _cached_aabb_revision: int = -1
var _cached_aabb: AABB = AABB()
var _cached_face_data_revision: int = -1
var _cached_face_centers: PackedVector3Array = PackedVector3Array()
var _cached_face_normals: PackedVector3Array = PackedVector3Array()
var _cached_face_edges_revision: int = -1
var _cached_face_edges: Array[Vector2i] = []
var _cached_edges_revision: int = -1
var _cached_edges: Array[Vector2i] = []
var _cached_edge_lookup_revision: int = -1
var _cached_edge_lookup: Dictionary = {}
var _cached_topology_revision: int = -1
var _cached_topology: GDDrawUVTopology


func set_geometry(
	new_vertices: PackedVector3Array,
	new_faces: Array[PackedInt32Array],
	new_smooth_faces: PackedByteArray = PackedByteArray(),
	new_uv_faces: Array[PackedVector2Array] = [],
	new_has_uv_map: bool = false,
	new_corner_normals: Array[PackedVector3Array] = [],
	new_has_custom_normals: bool = false,
	new_loose_edges: Array[Vector2i] = [],
	new_crease_edges: Array[Vector2i] = [],
	new_crease_weights: PackedFloat32Array = PackedFloat32Array(),
	new_seam_edges: Array[Vector2i] = [],
	new_face_materials: PackedInt32Array = PackedInt32Array()
) -> void:
	var previous_faces: Array[PackedInt32Array] = _duplicate_faces(faces)
	var previous_materials: PackedInt32Array = face_materials.duplicate()
	vertices = new_vertices
	faces = _duplicate_faces(new_faces)
	loose_edges = new_loose_edges.duplicate()
	smooth_faces = new_smooth_faces.duplicate()
	uv_faces = _duplicate_uv_faces(new_uv_faces)
	has_uv_map = new_has_uv_map
	corner_normals = _duplicate_normal_faces(new_corner_normals)
	has_custom_normals = new_has_custom_normals
	crease_edges = new_crease_edges.duplicate()
	crease_weights = new_crease_weights.duplicate()
	seam_edges = new_seam_edges.duplicate()
	face_materials = _remap_or_copy_face_materials(previous_faces, previous_materials, new_faces, new_face_materials)
	_reset_derived_caches()
	_normalize_smooth_flags()
	_normalize_uv_layout()
	_normalize_normal_layout()
	_normalize_loose_edges()
	_normalize_creases()
	_normalize_seams()
	_normalize_face_materials()
	mark_changed()


func set_geometry_internal(
	new_vertices: PackedVector3Array,
	new_faces: Array[PackedInt32Array],
	new_smooth_faces: PackedByteArray = PackedByteArray(),
	new_uv_faces: Array[PackedVector2Array] = [],
	new_has_uv_map: bool = false,
	new_corner_normals: Array[PackedVector3Array] = [],
	new_has_custom_normals: bool = false,
	new_loose_edges: Array[Vector2i] = [],
	new_crease_edges: Array[Vector2i] = [],
	new_crease_weights: PackedFloat32Array = PackedFloat32Array(),
	new_seam_edges: Array[Vector2i] = [],
	new_face_materials: PackedInt32Array = PackedInt32Array()
) -> void:
	vertices = new_vertices
	faces = new_faces
	loose_edges = new_loose_edges
	smooth_faces = new_smooth_faces
	uv_faces = new_uv_faces
	has_uv_map = new_has_uv_map
	corner_normals = new_corner_normals
	has_custom_normals = new_has_custom_normals
	crease_edges = new_crease_edges
	crease_weights = new_crease_weights
	seam_edges = new_seam_edges
	face_materials = new_face_materials
	_change_revision += 1
	_position_revision += 1
	_topology_revision += 1
	_last_position_change_indices.clear()
	_cache_enabled = false
	_reset_derived_caches()


func duplicate_mesh_data() -> GDDrawUVMeshData:
	return duplicate_mesh_data_fast()


func duplicate_mesh_data_fast() -> GDDrawUVMeshData:
	var copy: GDDrawUVMeshData = GDDrawUVMeshData.new()
	copy.vertices = vertices.duplicate()
	copy.faces = _duplicate_faces(faces)
	copy.loose_edges = loose_edges.duplicate()
	copy.smooth_faces = smooth_faces.duplicate()
	copy.uv_faces = _duplicate_uv_faces(uv_faces)
	copy.has_uv_map = has_uv_map
	copy.corner_normals = _duplicate_normal_faces(corner_normals)
	copy.has_custom_normals = has_custom_normals
	copy.crease_edges = crease_edges.duplicate()
	copy.crease_weights = crease_weights.duplicate()
	copy.seam_edges = seam_edges.duplicate()
	copy.face_materials = face_materials.duplicate()
	copy.uv_seam_analysis_pending = uv_seam_analysis_pending
	copy._change_revision = 1
	copy._position_revision = 1
	copy._topology_revision = 1
	copy._last_position_change_indices.clear()
	copy._cache_enabled = false
	return copy


func duplicate_mesh_data_validated() -> GDDrawUVMeshData:
	var copy: GDDrawUVMeshData = duplicate_mesh_data_fast()
	copy._normalize_smooth_flags()
	copy._normalize_uv_layout()
	copy._normalize_normal_layout()
	copy._normalize_loose_edges()
	copy._normalize_creases()
	copy._normalize_seams()
	copy._normalize_face_materials()
	copy.prepare_for_use()
	return copy


func get_change_revision() -> int:
	return _change_revision


func get_position_revision() -> int:
	return _position_revision


func get_topology_revision() -> int:
	return _topology_revision


func get_last_position_change_indices() -> PackedInt32Array:
	return _last_position_change_indices


func get_vertex_positions(indices: PackedInt32Array) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	result.resize(indices.size())
	for index: int in indices.size():
		var vertex_index: int = indices[index]
		result[index] = vertices[vertex_index] if vertex_index >= 0 and vertex_index < vertices.size() else Vector3.ZERO
	return result


func set_vertex_positions(indices: PackedInt32Array, positions: PackedVector3Array) -> void:
	var count: int = mini(indices.size(), positions.size())
	if count <= 0:
		return
	var changed_indices: PackedInt32Array = PackedInt32Array()
	changed_indices.resize(count)
	var changed_count: int = 0
	for index: int in count:
		var vertex_index: int = indices[index]
		if vertex_index < 0 or vertex_index >= vertices.size():
			continue
		var new_position: Vector3 = positions[index]
		if vertices[vertex_index].is_equal_approx(new_position):
			continue
		vertices[vertex_index] = new_position
		changed_indices[changed_count] = vertex_index
		changed_count += 1
	if changed_count <= 0:
		return
	changed_indices.resize(changed_count)
	mark_positions_changed(changed_indices)


func mark_changed() -> void:
	_change_revision += 1
	_position_revision += 1
	_topology_revision += 1
	_last_position_change_indices.clear()
	_reset_derived_caches()
	emit_changed()


func mark_positions_changed(indices: PackedInt32Array = PackedInt32Array()) -> void:
	var previous_revision: int = _change_revision
	_change_revision += 1
	_position_revision += 1
	_last_position_change_indices = indices.duplicate()
	_cached_aabb_revision = -1
	_cached_face_data_revision = -1
	_cached_face_centers = PackedVector3Array()
	_cached_face_normals = PackedVector3Array()
	if _cached_face_edges_revision == previous_revision:
		_cached_face_edges_revision = _change_revision
	if _cached_edges_revision == previous_revision:
		_cached_edges_revision = _change_revision
	if _cached_edge_lookup_revision == previous_revision:
		_cached_edge_lookup_revision = _change_revision
	if _cached_topology_revision == previous_revision:
		_cached_topology_revision = _change_revision
	emit_changed()


func prepare_for_use() -> void:
	if _cache_enabled:
		return
	_cache_enabled = true
	_change_revision += 1
	_position_revision += 1
	_topology_revision += 1
	_last_position_change_indices.clear()
	_reset_derived_caches()


func _reset_derived_caches() -> void:
	_cached_aabb_revision = -1
	_cached_face_data_revision = -1
	_cached_face_edges_revision = -1
	_cached_edges_revision = -1
	_cached_edge_lookup_revision = -1
	_cached_topology_revision = -1
	_cached_face_centers = PackedVector3Array()
	_cached_face_normals = PackedVector3Array()
	_cached_face_edges.clear()
	_cached_edges.clear()
	_cached_edge_lookup.clear()
	_cached_topology = null


func is_valid() -> bool:
	_normalize_face_materials()
	if vertices.is_empty() or (faces.is_empty() and loose_edges.is_empty()):
		return false

	for face_index: int in faces.size():
		var face: PackedInt32Array = faces[face_index]
		if face.size() < 3:
			return false
		if face.size() == 3:
			if face[0] == face[1] or face[1] == face[2] or face[2] == face[0]:
				return false
			for vertex_index: int in face:
				if vertex_index < 0 or vertex_index >= vertices.size():
					return false
		else:
			var unique: Dictionary = {}
			for vertex_index: int in face:
				if vertex_index < 0 or vertex_index >= vertices.size():
					return false
				unique[vertex_index] = true
			if unique.size() < 3:
				return false
		if has_uv_map:
			if face_index >= uv_faces.size() or uv_faces[face_index].size() != face.size():
				return false
		if has_custom_normals:
			if face_index >= corner_normals.size() or corner_normals[face_index].size() != face.size():
				return false
		if face_index >= face_materials.size() or face_materials[face_index] < 0:
			return false

	for edge: Vector2i in loose_edges:
		if edge.x < 0 or edge.y < 0 or edge.x >= vertices.size() or edge.y >= vertices.size():
			return false
		if edge.x == edge.y:
			return false

	return true


func get_aabb() -> AABB:
	if _cache_enabled and _cached_aabb_revision == _change_revision:
		return _cached_aabb
	if vertices.is_empty():
		_cached_aabb = AABB()
	else:
		var bounds: AABB = AABB(vertices[0], Vector3.ZERO)
		for vertex_index: int in range(1, vertices.size()):
			bounds = bounds.expand(vertices[vertex_index])
		_cached_aabb = bounds
	if _cache_enabled:
		_cached_aabb_revision = _change_revision
	return _cached_aabb


func _ensure_face_data_cache() -> void:
	if _cache_enabled and _cached_face_data_revision == _change_revision:
		return
	_cached_face_centers.resize(faces.size())
	_cached_face_normals.resize(faces.size())
	for face_index: int in faces.size():
		var face: PackedInt32Array = faces[face_index]
		if face.is_empty():
			_cached_face_centers[face_index] = Vector3.ZERO
			_cached_face_normals[face_index] = Vector3.UP
			continue
		var center: Vector3 = Vector3.ZERO
		var normal: Vector3 = Vector3.ZERO
		for corner_index: int in face.size():
			var current: Vector3 = vertices[face[corner_index]]
			var next: Vector3 = vertices[face[(corner_index + 1) % face.size()]]
			center += current
			normal.x += (current.y - next.y) * (current.z + next.z)
			normal.y += (current.z - next.z) * (current.x + next.x)
			normal.z += (current.x - next.x) * (current.y + next.y)
		_cached_face_centers[face_index] = center / float(face.size())
		_cached_face_normals[face_index] = Vector3.UP if normal.is_zero_approx() else normal.normalized()
	if _cache_enabled:
		_cached_face_data_revision = _change_revision


func get_face_center(face_index: int) -> Vector3:
	if face_index < 0 or face_index >= faces.size():
		return Vector3.ZERO
	_ensure_face_data_cache()
	return _cached_face_centers[face_index]


func get_face_normal(face_index: int) -> Vector3:
	if face_index < 0 or face_index >= faces.size():
		return Vector3.UP
	_ensure_face_data_cache()
	return _cached_face_normals[face_index]


func get_face_edges() -> Array[Vector2i]:
	if _cache_enabled and _cached_face_edges_revision == _change_revision:
		return _cached_face_edges
	_cached_face_edges = []
	var known: Dictionary = {}
	for face: PackedInt32Array in faces:
		for corner_index: int in face.size():
			var edge: Vector2i = canonical_edge(
				face[corner_index],
				face[(corner_index + 1) % face.size()]
			)
			if not known.has(edge):
				known[edge] = true
				_cached_face_edges.append(edge)
	if _cache_enabled:
		_cached_face_edges_revision = _change_revision
	return _cached_face_edges


func get_edges() -> Array[Vector2i]:
	if _cache_enabled and _cached_edges_revision == _change_revision:
		return _cached_edges
	_cached_edges = get_face_edges().duplicate()
	var known: Dictionary = {}
	for edge: Vector2i in _cached_edges:
		known[edge] = true
	for source_edge: Vector2i in loose_edges:
		var edge: Vector2i = canonical_edge(source_edge.x, source_edge.y)
		if not known.has(edge):
			known[edge] = true
			_cached_edges.append(edge)
	if _cache_enabled:
		_cached_edges_revision = _change_revision
	return _cached_edges


func get_edge_count() -> int:
	return get_edges().size()


func has_cached_edges() -> bool:
	return _cache_enabled and _cached_edges_revision == _change_revision


func get_cached_edge_count() -> int:
	return _cached_edges.size() if has_cached_edges() else -1


func install_precomputed_edges(
	face_edges: Array[Vector2i],
	all_edges: Array[Vector2i],
	edge_lookup: Dictionary,
	source_revision: int
) -> void:
	if not _cache_enabled or source_revision != _change_revision:
		return
	_cached_face_edges = face_edges
	_cached_edges = all_edges
	_cached_edge_lookup = edge_lookup
	_cached_face_edges_revision = _change_revision
	_cached_edges_revision = _change_revision
	_cached_edge_lookup_revision = _change_revision


func get_edge_index(a: int, b: int) -> int:
	if not _cache_enabled:
		return get_edges().find(canonical_edge(a, b))
	if _cached_edge_lookup_revision != _change_revision:
		_cached_edge_lookup.clear()
		var edges: Array[Vector2i] = get_edges()
		for edge_index: int in edges.size():
			_cached_edge_lookup[edges[edge_index]] = edge_index
		_cached_edge_lookup_revision = _change_revision
	return int(_cached_edge_lookup.get(canonical_edge(a, b), -1))


func get_topology() -> GDDrawUVTopology:
	if not _cache_enabled:
		return GDDrawUVTopology.new(self)
	if _cached_topology_revision != _change_revision or _cached_topology == null:
		_cached_topology = GDDrawUVTopology.new(self)
		_cached_topology_revision = _change_revision
	return _cached_topology


func is_loose_edge(edge: Vector2i) -> bool:
	var canonical: Vector2i = canonical_edge(edge.x, edge.y)
	return loose_edges.has(canonical)


func get_edge_crease_by_vertices(a: int, b: int) -> float:
	_normalize_creases()
	var index: int = crease_edges.find(canonical_edge(a, b))
	if index < 0 or index >= crease_weights.size():
		return 0.0
	return crease_weights[index]


func get_edge_crease(edge_index: int) -> float:
	var edges: Array[Vector2i] = get_edges()
	if edge_index < 0 or edge_index >= edges.size():
		return 0.0
	return get_edge_crease_by_vertices(edges[edge_index].x, edges[edge_index].y)


func set_edge_crease_by_vertices(a: int, b: int, weight: float) -> void:
	var edge: Vector2i = canonical_edge(a, b)
	var clamped: float = clampf(weight, 0.0, 1.0)
	var index: int = crease_edges.find(edge)
	if clamped <= 0.000001:
		if index >= 0:
			crease_edges.remove_at(index)
			crease_weights.remove_at(index)
	else:
		if index < 0:
			crease_edges.append(edge)
			crease_weights.append(clamped)
		else:
			crease_weights[index] = clamped
	mark_changed()


func is_edge_seam_by_vertices(a: int, b: int) -> bool:
	_normalize_seams()
	return seam_edges.has(canonical_edge(a, b))


func set_edge_seam_by_vertices(a: int, b: int, marked: bool) -> void:
	var edge: Vector2i = canonical_edge(a, b)
	var index: int = seam_edges.find(edge)
	if marked:
		if index < 0 and get_edges().has(edge):
			seam_edges.append(edge)
	else:
		if index >= 0:
			seam_edges.remove_at(index)
	_normalize_seams()
	mark_changed()


func clear_seams() -> void:
	seam_edges.clear()
	mark_changed()


func get_face_uvs(face_index: int) -> PackedVector2Array:
	_normalize_uv_layout()
	if face_index < 0 or face_index >= uv_faces.size():
		return PackedVector2Array()
	return uv_faces[face_index].duplicate()


func set_face_uvs(face_index: int, values: PackedVector2Array) -> void:
	if face_index < 0 or face_index >= faces.size():
		return
	if values.size() != faces[face_index].size():
		return
	_normalize_uv_layout()
	uv_faces[face_index] = values.duplicate()
	has_uv_map = true
	mark_changed()


func get_face_material(face_index: int) -> int:
	if face_materials.size() != faces.size():
		_normalize_face_materials()
	if face_index < 0 or face_index >= face_materials.size():
		return 0
	var material_index: int = face_materials[face_index]
	if material_index < 0:
		face_materials[face_index] = 0
		return 0
	return material_index


func set_face_material(face_index: int, material_index: int) -> void:
	if face_index < 0 or face_index >= faces.size():
		return
	_normalize_face_materials()
	face_materials[face_index] = maxi(material_index, 0)
	mark_changed()


func assign_material_to_faces(face_indices: PackedInt32Array, material_index: int) -> void:
	_normalize_face_materials()
	var safe_index: int = maxi(material_index, 0)
	for face_index: int in face_indices:
		if face_index >= 0 and face_index < face_materials.size():
			face_materials[face_index] = safe_index
	mark_changed()


func remap_removed_material_slot(removed_index: int) -> void:
	_normalize_face_materials()
	for face_index: int in face_materials.size():
		var current: int = face_materials[face_index]
		if current == removed_index:
			face_materials[face_index] = 0
		elif current > removed_index:
			face_materials[face_index] = current - 1
	mark_changed()


func offset_face_material_indices(offset: int) -> void:
	if offset == 0:
		return
	_normalize_face_materials()
	for face_index: int in face_materials.size():
		face_materials[face_index] = maxi(face_materials[face_index] + offset, 0)
	mark_changed()


func invalidate_uvs() -> void:
	has_uv_map = false
	uv_faces.clear()
	_normalize_uv_layout()
	mark_changed()


func invalidate_custom_normals() -> void:
	has_custom_normals = false
	corner_normals.clear()
	_normalize_normal_layout()
	mark_changed()


func _normalize_smooth_flags() -> void:
	if smooth_faces.size() == faces.size():
		return

	var normalized: PackedByteArray = PackedByteArray()
	normalized.resize(faces.size())
	for face_index: int in mini(smooth_faces.size(), faces.size()):
		normalized[face_index] = smooth_faces[face_index]
	smooth_faces = normalized


func _normalize_uv_layout() -> void:
	if uv_faces.size() == faces.size():
		var layout_valid: bool = true
		for face_index: int in faces.size():
			if uv_faces[face_index].size() != faces[face_index].size():
				layout_valid = false
				break
		if layout_valid:
			return
	var normalized: Array[PackedVector2Array] = []
	for face_index: int in faces.size():
		var face_uvs: PackedVector2Array = PackedVector2Array()
		face_uvs.resize(faces[face_index].size())
		if face_index < uv_faces.size() and uv_faces[face_index].size() == faces[face_index].size():
			face_uvs = uv_faces[face_index].duplicate()
		normalized.append(face_uvs)
	uv_faces = normalized


func _normalize_normal_layout() -> void:
	if corner_normals.size() == faces.size():
		var layout_valid: bool = true
		for face_index: int in faces.size():
			if corner_normals[face_index].size() != faces[face_index].size():
				layout_valid = false
				break
		if layout_valid:
			return
	var normalized: Array[PackedVector3Array] = []
	for face_index: int in faces.size():
		var values: PackedVector3Array = PackedVector3Array()
		values.resize(faces[face_index].size())
		if (
			face_index < corner_normals.size()
			and corner_normals[face_index].size() == faces[face_index].size()
		):
			values = corner_normals[face_index].duplicate()
		normalized.append(values)
	corner_normals = normalized


func _normalize_loose_edges() -> void:
	if loose_edges.is_empty():
		return
	var normalized: Array[Vector2i] = []
	var known: Dictionary = {}
	var face_edges: Dictionary = {}
	for edge: Vector2i in get_face_edges():
		face_edges[edge] = true
	for source_edge: Vector2i in loose_edges:
		var edge: Vector2i = canonical_edge(source_edge.x, source_edge.y)
		if (
			edge.x < 0 or edge.y < 0
			or edge.x >= vertices.size() or edge.y >= vertices.size()
			or edge.x == edge.y
			or known.has(edge)
			or face_edges.has(edge)
		):
			continue
		known[edge] = true
		normalized.append(edge)
	loose_edges = normalized


func _normalize_creases() -> void:
	if crease_edges.is_empty():
		crease_weights.clear()
		return
	var normalized_edges: Array[Vector2i] = []
	var normalized_weights: PackedFloat32Array = PackedFloat32Array()
	var known: Dictionary = {}
	var valid_edges: Dictionary = {}
	for edge: Vector2i in get_edges():
		valid_edges[edge] = true
	for index: int in crease_edges.size():
		if index >= crease_weights.size():
			break
		var edge: Vector2i = canonical_edge(crease_edges[index].x, crease_edges[index].y)
		var weight: float = clampf(crease_weights[index], 0.0, 1.0)
		if weight <= 0.000001 or known.has(edge) or not valid_edges.has(edge):
			continue
		known[edge] = true
		normalized_edges.append(edge)
		normalized_weights.append(weight)
	crease_edges = normalized_edges
	crease_weights = normalized_weights


func _normalize_seams() -> void:
	if seam_edges.is_empty():
		return
	var normalized: Array[Vector2i] = []
	var known: Dictionary = {}
	var valid_edges: Dictionary = {}
	for edge: Vector2i in get_face_edges():
		valid_edges[edge] = true
	for source_edge: Vector2i in seam_edges:
		var edge: Vector2i = canonical_edge(source_edge.x, source_edge.y)
		if known.has(edge) or not valid_edges.has(edge):
			continue
		known[edge] = true
		normalized.append(edge)
	seam_edges = normalized


func _normalize_face_materials() -> void:
	if face_materials.size() == faces.size():
		for face_index: int in face_materials.size():
			face_materials[face_index] = maxi(face_materials[face_index], 0)
		return
	var normalized: PackedInt32Array = PackedInt32Array()
	normalized.resize(faces.size())
	for face_index: int in mini(face_materials.size(), faces.size()):
		normalized[face_index] = maxi(face_materials[face_index], 0)
	face_materials = normalized


static func _remap_or_copy_face_materials(
	old_faces: Array[PackedInt32Array],
	old_materials: PackedInt32Array,
	new_faces: Array[PackedInt32Array],
	explicit_materials: PackedInt32Array
) -> PackedInt32Array:
	if explicit_materials.size() == new_faces.size():
		return explicit_materials.duplicate()

	var result: PackedInt32Array = PackedInt32Array()
	result.resize(new_faces.size())
	if old_materials.is_empty() or old_faces.is_empty():
		return result

	var old_lookup: Dictionary = {}
	for old_index: int in mini(old_faces.size(), old_materials.size()):
		old_lookup[_face_vertex_key(old_faces[old_index])] = maxi(old_materials[old_index], 0)
	for new_index: int in new_faces.size():
		var key: String = _face_vertex_key(new_faces[new_index])
		if old_lookup.has(key):
			result[new_index] = int(old_lookup[key])
	return result


static func _face_vertex_key(face: PackedInt32Array) -> String:
	var values: Array[int] = []
	for vertex_index: int in face:
		values.append(vertex_index)
	values.sort()
	var parts: PackedStringArray = PackedStringArray()
	for value: int in values:
		parts.append(str(value))
	return ",".join(parts)


static func canonical_edge(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


static func _duplicate_faces(source: Array[PackedInt32Array]) -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	for face: PackedInt32Array in source:
		result.append(face.duplicate())
	return result


static func _duplicate_uv_faces(source: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for face_uvs: PackedVector2Array in source:
		result.append(face_uvs.duplicate())
	return result


static func _duplicate_normal_faces(source: Array[PackedVector3Array]) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	for face_normals: PackedVector3Array in source:
		result.append(face_normals.duplicate())
	return result
