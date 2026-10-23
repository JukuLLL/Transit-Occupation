@tool
# Derived from Gator Model Studio (c) 2026 Blackwater Gator Studios, MIT License.
# See LICENSE-GatorModelStudio.txt. Modified for GDDraw: renamed classes, mesh-rebuild code removed,
# host hooks added to the editor window.
class_name GDDrawUVOperations
extends RefCounted




enum ProjectionAxis {
	X,
	Y,
	Z,
}

const UV_EPSILON: float = 0.00001


static func project_planar(
	mesh: GDDrawUVMeshData,
	face_indices: PackedInt32Array,
	axis: int
) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	var selected: PackedInt32Array = _valid_faces(result, face_indices)
	if selected.is_empty():
		return result

	var raw_points: PackedVector2Array = PackedVector2Array()
	for face_index: int in selected:
		for vertex_index: int in result.faces[face_index]:
			raw_points.append(_planar_coordinates(result.vertices[vertex_index], axis))
	var mapping: Dictionary = _normalization_mapping(raw_points)

	for face_index: int in selected:
		var face_uvs: PackedVector2Array = PackedVector2Array()
		for vertex_index: int in result.faces[face_index]:
			face_uvs.append(
				_normalize_point(
					_planar_coordinates(result.vertices[vertex_index], axis),
					mapping
				)
			)
		result.uv_faces[face_index] = face_uvs
	result.has_uv_map = true
	return result


static func project_box(
	mesh: GDDrawUVMeshData,
	face_indices: PackedInt32Array
) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	var selected: PackedInt32Array = _valid_faces(result, face_indices)
	if selected.is_empty():
		return result

	var bounds: AABB = result.get_aabb()
	var center: Vector3 = bounds.get_center()
	var extent: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if extent <= 0.000001:
		extent = 1.0

	for face_index: int in selected:
		var normal: Vector3 = result.get_face_normal(face_index)
		var axis: int = _dominant_axis(normal)
		var face_uvs: PackedVector2Array = PackedVector2Array()
		for vertex_index: int in result.faces[face_index]:
			var relative: Vector3 = result.vertices[vertex_index] - center
			var uv: Vector2
			match axis:
				ProjectionAxis.X:
					uv = Vector2(
						-relative.z if normal.x >= 0.0 else relative.z,
						relative.y
					)
				ProjectionAxis.Y:
					uv = Vector2(
						relative.x,
						-relative.z if normal.y >= 0.0 else relative.z
					)
				_:
					uv = Vector2(
						relative.x if normal.z >= 0.0 else -relative.x,
						relative.y
					)
			face_uvs.append(uv / extent + Vector2(0.5, 0.5))
		result.uv_faces[face_index] = face_uvs
	result.has_uv_map = true
	return result


static func project_cylindrical(
	mesh: GDDrawUVMeshData,
	face_indices: PackedInt32Array
) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	var selected: PackedInt32Array = _valid_faces(result, face_indices)
	if selected.is_empty():
		return result

	var bounds: AABB = result.get_aabb()
	var center: Vector3 = bounds.get_center()
	var height: float = maxf(bounds.size.y, 0.000001)
	for face_index: int in selected:
		var face_uvs: PackedVector2Array = PackedVector2Array()
		for vertex_index: int in result.faces[face_index]:
			var relative: Vector3 = result.vertices[vertex_index] - center
			var u: float = atan2(relative.x, relative.z) / TAU + 0.5
			var v: float = relative.y / height + 0.5
			face_uvs.append(Vector2(u, v))
		_adjust_wrapped_face(face_uvs)
		result.uv_faces[face_index] = face_uvs
	result.has_uv_map = true
	return result


static func project_spherical(
	mesh: GDDrawUVMeshData,
	face_indices: PackedInt32Array
) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	var selected: PackedInt32Array = _valid_faces(result, face_indices)
	if selected.is_empty():
		return result

	var center: Vector3 = result.get_aabb().get_center()
	for face_index: int in selected:
		var face_uvs: PackedVector2Array = PackedVector2Array()
		for vertex_index: int in result.faces[face_index]:
			var relative: Vector3 = result.vertices[vertex_index] - center
			var radius: float = relative.length()
			if radius <= 0.000001:
				face_uvs.append(Vector2(0.5, 0.5))
				continue
			var u: float = atan2(relative.x, relative.z) / TAU + 0.5
			var v: float = asin(clampf(relative.y / radius, -1.0, 1.0)) / PI + 0.5
			face_uvs.append(Vector2(u, v))
		_adjust_wrapped_face(face_uvs)
		result.uv_faces[face_index] = face_uvs
	result.has_uv_map = true
	return result


static func transform_uvs(
	mesh: GDDrawUVMeshData,
	face_indices: PackedInt32Array,
	offset: Vector2,
	scale: Vector2,
	rotation_degrees: float
) -> GDDrawUVMeshData:
	var corners: Array[Vector2i] = []
	for face_index: int in _valid_faces(mesh, face_indices):
		for corner_index: int in mesh.faces[face_index].size():
			corners.append(Vector2i(face_index, corner_index))
	return transform_corners(mesh, corners, offset, scale, rotation_degrees)


static func transform_corners(
	mesh: GDDrawUVMeshData,
	corners: Array[Vector2i],
	offset: Vector2,
	scale: Vector2,
	rotation_degrees: float,
	pivot: Vector2 = Vector2(100000000000000000000.0, 100000000000000000000.0)
) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	var valid: Array[Vector2i] = _valid_corners(result, corners)
	if valid.is_empty() or not result.has_uv_map:
		return result

	var center: Vector2 = pivot
	if absf(center.x) > 10000000000000000000.0 or absf(center.y) > 10000000000000000000.0:
		center = get_corner_center(result, valid)
	var angle: float = deg_to_rad(rotation_degrees)
	var cosine: float = cos(angle)
	var sine: float = sin(angle)
	for corner: Vector2i in valid:
		var uv: Vector2 = result.uv_faces[corner.x][corner.y]
		var relative: Vector2 = (uv - center) * scale
		var rotated: Vector2 = Vector2(
			relative.x * cosine - relative.y * sine,
			relative.x * sine + relative.y * cosine
		)
		var face_uvs: PackedVector2Array = result.uv_faces[corner.x].duplicate()
		face_uvs[corner.y] = center + rotated + offset
		result.uv_faces[corner.x] = face_uvs
	result.has_uv_map = true
	return result


static func get_uv_center(mesh: GDDrawUVMeshData, face_indices: PackedInt32Array) -> Vector2:
	var corners: Array[Vector2i] = []
	for face_index: int in _valid_faces(mesh, face_indices):
		for corner_index: int in mesh.faces[face_index].size():
			corners.append(Vector2i(face_index, corner_index))
	return get_corner_center(mesh, corners)


static func get_corner_center(mesh: GDDrawUVMeshData, corners: Array[Vector2i]) -> Vector2:
	var valid: Array[Vector2i] = _valid_corners(mesh, corners)
	if valid.is_empty() or not mesh.has_uv_map:
		return Vector2(0.5, 0.5)
	var center: Vector2 = Vector2.ZERO
	for corner: Vector2i in valid:
		center += mesh.uv_faces[corner.x][corner.y]
	return center / float(valid.size())


static func mark_edges_as_seams(
	mesh: GDDrawUVMeshData,
	edges: Array[Vector2i],
	marked: bool
) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	for source_edge: Vector2i in edges:
		var edge: Vector2i = GDDrawUVMeshData.canonical_edge(source_edge.x, source_edge.y)
		var index: int = result.seam_edges.find(edge)
		if marked:
			if index < 0 and result.get_face_edges().has(edge):
				result.seam_edges.append(edge)
		elif index >= 0:
			result.seam_edges.remove_at(index)
	return result


static func mark_seams_by_angle(
	mesh: GDDrawUVMeshData,
	angle_degrees: float,
	clear_existing: bool = false,
	face_indices: PackedInt32Array = PackedInt32Array()
) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	_mark_seams_by_angle_in_place(
		result,
		angle_degrees,
		clear_existing,
		face_indices,
		result.get_topology()
	)
	return result


static func _mark_seams_by_angle_in_place(
	mesh: GDDrawUVMeshData,
	angle_degrees: float,
	clear_existing: bool,
	face_indices: PackedInt32Array,
	topology: GDDrawUVTopology,
	job: GDDrawUVBackgroundJob = null,
	progress_start: float = 0.0,
	progress_end: float = 1.0
) -> void:
	if clear_existing:
		mesh.seam_edges.clear()
	var allowed: Dictionary = {}
	if not face_indices.is_empty():
		for face_index: int in _valid_faces(mesh, face_indices):
			allowed[face_index] = true
	var seam_lookup: Dictionary = _build_edge_lookup(mesh.seam_edges)
	var threshold: float = deg_to_rad(clampf(angle_degrees, 0.0, 180.0))
	var topology_edges: Array = topology.edge_half_edges.keys()
	var edge_count: int = maxi(topology_edges.size(), 1)
	for edge_position: int in topology_edges.size():
		if job != null and edge_position % 128 == 0:
			if job.is_cancelled():
				return
			job.update_progress(
				lerpf(progress_start, progress_end, float(edge_position) / float(edge_count)),
				"Detecting UV seams"
			)
		var edge_value: Variant = topology_edges[edge_position]
		var edge: Vector2i = edge_value
		var attached_half_edges: PackedInt32Array = topology.edge_half_edges[edge]
		if not allowed.is_empty():
			var touches_selection: bool = false
			for half_edge_index: int in attached_half_edges:
				if allowed.has(topology.half_edge_face[half_edge_index]):
					touches_selection = true
					break
			if not touches_selection:
				continue

		var face_a: int = -1
		var face_b: int = -1
		var unique_face_count: int = 0
		for half_edge_index: int in attached_half_edges:
			var attached_face: int = topology.half_edge_face[half_edge_index]
			if attached_face == face_a or attached_face == face_b:
				continue
			if unique_face_count == 0:
				face_a = attached_face
			elif unique_face_count == 1:
				face_b = attached_face
			unique_face_count += 1
			if unique_face_count > 2:
				break

		var should_mark: bool = unique_face_count != 2
		if unique_face_count == 2:
			if not allowed.is_empty() and (not allowed.has(face_a) or not allowed.has(face_b)):
				should_mark = true
			else:
				var normal_a: Vector3 = mesh.get_face_normal(face_a)
				var normal_b: Vector3 = mesh.get_face_normal(face_b)
				var angle: float = acos(clampf(normal_a.dot(normal_b), -1.0, 1.0))
				should_mark = angle >= threshold
		if should_mark and not seam_lookup.has(edge):
			mesh.seam_edges.append(edge)
			seam_lookup[edge] = true

	if job != null:
		job.update_progress(progress_end, "UV seams detected")

static func is_edge_uv_continuous(mesh: GDDrawUVMeshData, edge: Vector2i) -> bool:
	if mesh == null or not mesh.has_uv_map:
		return true
	var canonical: Vector2i = GDDrawUVMeshData.canonical_edge(edge.x, edge.y)
	var topology: GDDrawUVTopology = mesh.get_topology()
	return _edge_uv_continuous_with_faces(mesh, canonical, topology.get_edge_faces(canonical))


static func get_uv_boundary_edges(mesh: GDDrawUVMeshData) -> Dictionary:
	var result: Dictionary = {}
	if mesh == null:
		return result
	var topology: GDDrawUVTopology = mesh.get_topology()
	for edge_value: Variant in topology.edge_half_edges.keys():
		var edge: Vector2i = edge_value
		if mesh.seam_edges.has(edge):
			result[edge] = true
			continue
		var attached_faces: PackedInt32Array = topology.get_edge_faces(edge)
		if attached_faces.size() == 2 and mesh.get_face_material(attached_faces[0]) != mesh.get_face_material(attached_faces[1]):
			result[edge] = true
			continue
		if not _edge_uv_continuous_with_faces(mesh, edge, attached_faces):
			result[edge] = true
	return result


static func unwrap_from_seams(
	mesh: GDDrawUVMeshData,
	face_indices: PackedInt32Array,
	padding: float = 0.02,
	job: GDDrawUVBackgroundJob = null
) -> GDDrawUVMeshData:
	if job != null:
		job.update_progress(0.01, "Preparing seam unwrap")
		if job.is_cancelled():
			return null
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	var selected: PackedInt32Array = _valid_faces(result, face_indices)
	if selected.is_empty():
		return result

	if job != null:
		job.update_progress(0.08, "Building mesh topology")
	var topology: GDDrawUVTopology = result.get_topology()
	if job != null and job.is_cancelled():
		return null
	var seam_lookup: Dictionary = _build_edge_lookup(result.seam_edges)
	var islands: Array[PackedInt32Array] = _get_seam_islands_with_context(
		result,
		selected,
		topology,
		seam_lookup,
		job,
		0.10,
		0.25
	)
	if job != null and job.is_cancelled():
		return null
	var island_count: int = maxi(islands.size(), 1)
	for island_index: int in islands.size():
		var island_start: float = 0.25 + 0.50 * float(island_index) / float(island_count)
		var island_end: float = 0.25 + 0.50 * float(island_index + 1) / float(island_count)
		if not _unfold_island(
			result,
			islands[island_index],
			topology,
			seam_lookup,
			job,
			island_start,
			island_end
		):
			return null
	result.has_uv_map = true
	if not _pack_face_groups_in_place(result, islands, padding, job, 0.75, 1.0):
		return null
	if job != null:
		job.update_progress(1.0, "UV unwrap complete")
	return result


static func smart_uv_project(
	mesh: GDDrawUVMeshData,
	face_indices: PackedInt32Array,
	angle_degrees: float = 66.0,
	padding: float = 0.02,
	job: GDDrawUVBackgroundJob = null
) -> GDDrawUVMeshData:
	if job != null:
		job.update_progress(0.01, "Preparing Smart UV Project")
		if job.is_cancelled():
			return null
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	var selected: PackedInt32Array = _valid_faces(result, face_indices)
	if selected.is_empty():
		return result

	var user_seams: Array[Vector2i] = result.seam_edges.duplicate()
	if job != null:
		job.update_progress(0.07, "Building mesh topology")
	var topology: GDDrawUVTopology = result.get_topology()
	if job != null and job.is_cancelled():
		return null
	_mark_seams_by_angle_in_place(
		result,
		angle_degrees,
		false,
		selected,
		topology,
		job,
		0.10,
		0.23
	)
	if job != null and job.is_cancelled():
		return null
	var seam_lookup: Dictionary = _build_edge_lookup(result.seam_edges)
	var islands: Array[PackedInt32Array] = _get_seam_islands_with_context(
		result,
		selected,
		topology,
		seam_lookup,
		job,
		0.23,
		0.34
	)
	if job != null and job.is_cancelled():
		return null
	var island_count: int = maxi(islands.size(), 1)
	for island_index: int in islands.size():
		var island_start: float = 0.34 + 0.41 * float(island_index) / float(island_count)
		var island_end: float = 0.34 + 0.41 * float(island_index + 1) / float(island_count)
		if not _unfold_island(
			result,
			islands[island_index],
			topology,
			seam_lookup,
			job,
			island_start,
			island_end
		):
			return null
	result.has_uv_map = true
	if not _pack_face_groups_in_place(result, islands, padding, job, 0.75, 1.0):
		return null
	result.seam_edges = user_seams
	if job != null:
		job.update_progress(1.0, "Smart UV Project complete")
	return result



static func auto_unwrap(
	mesh: GDDrawUVMeshData,
	face_indices: PackedInt32Array,
	angle_degrees: float = 66.0,
	padding: float = 0.02
) -> GDDrawUVMeshData:
	return smart_uv_project(mesh, face_indices, angle_degrees, padding)


static func get_seam_islands(
	mesh: GDDrawUVMeshData,
	face_indices: PackedInt32Array = PackedInt32Array()
) -> Array[PackedInt32Array]:
	var islands: Array[PackedInt32Array] = []
	if mesh == null:
		return islands
	var selected: PackedInt32Array = face_indices
	if selected.is_empty():
		selected = all_faces(mesh)
	else:
		selected = _valid_faces(mesh, selected)
	return _get_seam_islands_with_context(
		mesh,
		selected,
		mesh.get_topology(),
		_build_edge_lookup(mesh.seam_edges)
	)


static func _get_seam_islands_with_context(
	mesh: GDDrawUVMeshData,
	selected: PackedInt32Array,
	topology: GDDrawUVTopology,
	seam_lookup: Dictionary,
	job: GDDrawUVBackgroundJob = null,
	progress_start: float = 0.0,
	progress_end: float = 1.0
) -> Array[PackedInt32Array]:
	var islands: Array[PackedInt32Array] = []
	if selected.is_empty():
		return islands
	var allowed: Dictionary = {}
	for face_index: int in selected:
		allowed[face_index] = true
	var visited: Dictionary = {}
	var selected_count: int = maxi(selected.size(), 1)
	for seed_position: int in selected.size():
		if job != null and seed_position % 64 == 0:
			if job.is_cancelled():
				return islands
			job.update_progress(
				lerpf(progress_start, progress_end, float(visited.size()) / float(selected_count)),
				"Finding UV islands"
			)
		var seed: int = selected[seed_position]
		if visited.has(seed):
			continue
		var island: PackedInt32Array = PackedInt32Array()
		var queue: PackedInt32Array = PackedInt32Array([seed])
		var queue_head: int = 0
		visited[seed] = true
		while queue_head < queue.size():
			if job != null and queue_head % 128 == 0 and job.is_cancelled():
				return islands
			var face_index: int = queue[queue_head]
			queue_head += 1
			island.append(face_index)
			var face: PackedInt32Array = mesh.faces[face_index]
			for corner_index: int in face.size():
				var edge: Vector2i = GDDrawUVMeshData.canonical_edge(
					face[corner_index],
					face[(corner_index + 1) % face.size()]
				)
				if seam_lookup.has(edge):
					continue
				var attached_half_edges: PackedInt32Array = topology.edge_half_edges[edge]
				for half_edge_index: int in attached_half_edges:
					var neighbour: int = topology.half_edge_face[half_edge_index]
					if neighbour == face_index or not allowed.has(neighbour) or visited.has(neighbour):
						continue
					visited[neighbour] = true
					queue.append(neighbour)
		islands.append(island)
	if job != null:
		job.update_progress(progress_end, "UV islands found")
	return islands


static func get_uv_islands(
	mesh: GDDrawUVMeshData,
	face_indices: PackedInt32Array = PackedInt32Array(),
	job: GDDrawUVBackgroundJob = null,
	progress_start: float = 0.0,
	progress_end: float = 1.0
) -> Array[PackedInt32Array]:
	var islands: Array[PackedInt32Array] = []
	if mesh == null:
		return islands
	var selected: PackedInt32Array = face_indices
	if selected.is_empty():
		selected = all_faces(mesh)
	else:
		selected = _valid_faces(mesh, selected)
	var allowed: Dictionary = {}
	for face_index: int in selected:
		allowed[face_index] = true
	var topology: GDDrawUVTopology = mesh.get_topology()
	if job != null and job.is_cancelled():
		return islands
	var seam_lookup: Dictionary = _build_edge_lookup(mesh.seam_edges)
	var visited: Dictionary = {}
	var selected_count: int = maxi(selected.size(), 1)
	for seed_position: int in selected.size():
		if job != null and seed_position % 64 == 0:
			if job.is_cancelled():
				return islands
			job.update_progress(
				lerpf(progress_start, progress_end, float(visited.size()) / float(selected_count)),
				"Finding UV islands"
			)
		var seed: int = selected[seed_position]
		if visited.has(seed):
			continue
		var island: PackedInt32Array = PackedInt32Array()
		var queue: PackedInt32Array = PackedInt32Array([seed])
		var queue_head: int = 0
		visited[seed] = true
		while queue_head < queue.size():
			if job != null and queue_head % 128 == 0 and job.is_cancelled():
				return islands
			var face_index: int = queue[queue_head]
			queue_head += 1
			island.append(face_index)
			var face: PackedInt32Array = mesh.faces[face_index]
			for corner_index: int in face.size():
				var edge: Vector2i = GDDrawUVMeshData.canonical_edge(
					face[corner_index],
					face[(corner_index + 1) % face.size()]
				)
				var attached: PackedInt32Array = topology.get_edge_faces(edge)
				if seam_lookup.has(edge) or not _edge_uv_continuous_with_faces(mesh, edge, attached):
					continue
				for neighbour: int in attached:
					if neighbour == face_index or not allowed.has(neighbour) or visited.has(neighbour):
						continue
					if mesh.get_face_material(neighbour) != mesh.get_face_material(face_index):
						continue
					visited[neighbour] = true
					queue.append(neighbour)
		islands.append(island)
	if job != null:
		job.update_progress(progress_end, "UV islands found")
	return islands


static func pack_islands(
	mesh: GDDrawUVMeshData,
	face_indices: PackedInt32Array = PackedInt32Array(),
	padding: float = 0.02,
	job: GDDrawUVBackgroundJob = null
) -> GDDrawUVMeshData:
	if job != null:
		job.update_progress(0.01, "Preparing UV island packing")
		if job.is_cancelled():
			return null
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	if not result.has_uv_map:
		return result
	var selected: PackedInt32Array = face_indices
	if selected.is_empty():
		selected = all_faces(result)
	if job != null:
		job.update_progress(0.10, "Finding UV islands")
	var islands: Array[PackedInt32Array] = get_uv_islands(result, selected, job, 0.10, 0.20)
	if job != null and job.is_cancelled():
		return null
	if not _pack_face_groups_in_place(result, islands, padding, job, 0.20, 1.0):
		return null
	if job != null:
		job.update_progress(1.0, "UV island packing complete")
	return result


static func relax_uvs(
	mesh: GDDrawUVMeshData,
	face_indices: PackedInt32Array,
	iterations: int = 12,
	strength: float = 0.5,
	preserve_boundary: bool = true
) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	if not result.has_uv_map:
		return result
	var selected: PackedInt32Array = _valid_faces(result, face_indices)
	if selected.is_empty():
		return result
	var selected_set: Dictionary = {}
	for face_index: int in selected:
		selected_set[face_index] = true
	var boundary_corners: Dictionary = _get_uv_boundary_corners(result, selected_set)
	var original_bounds: Rect2 = get_uv_bounds(result, selected)
	var blend: float = clampf(strength, 0.0, 1.0)
	for _iteration: int in clampi(iterations, 1, 100):
		var next_values: Dictionary = {}
		for face_index: int in selected:
			var face: PackedInt32Array = result.faces[face_index]
			for corner_index: int in face.size():
				var ref: Vector2i = Vector2i(face_index, corner_index)
				if preserve_boundary and boundary_corners.has(ref):
					continue
				var neighbours: Array[Vector2i] = _get_uv_corner_neighbours(
					result,
					ref,
					selected_set
				)
				if neighbours.is_empty():
					continue
				var average: Vector2 = Vector2.ZERO
				for neighbour: Vector2i in neighbours:
					average += result.uv_faces[neighbour.x][neighbour.y]
				average /= float(neighbours.size())
				var current: Vector2 = result.uv_faces[face_index][corner_index]
				next_values[ref] = current.lerp(average, blend)
		for ref_value: Variant in next_values.keys():
			var ref: Vector2i = ref_value
			var values: PackedVector2Array = result.uv_faces[ref.x].duplicate()
			values[ref.y] = next_values[ref]
			result.uv_faces[ref.x] = values

		var current_bounds: Rect2 = get_uv_bounds(result, selected)
		if current_bounds.size.x > UV_EPSILON and current_bounds.size.y > UV_EPSILON:
			var scale: Vector2 = Vector2(
				original_bounds.size.x / current_bounds.size.x,
				original_bounds.size.y / current_bounds.size.y
			)
			var current_center: Vector2 = current_bounds.get_center()
			var target_center: Vector2 = original_bounds.get_center()
			for face_index: int in selected:
				var values: PackedVector2Array = result.uv_faces[face_index].duplicate()
				for corner_index: int in values.size():
					values[corner_index] = target_center + (values[corner_index] - current_center) * scale
				result.uv_faces[face_index] = values
	return result


static func weld_corners(
	mesh: GDDrawUVMeshData,
	corners: Array[Vector2i]
) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	var valid: Array[Vector2i] = _valid_corners(result, corners)
	if valid.size() < 2 or not result.has_uv_map:
		return result
	var grouped: Dictionary = {}
	for ref: Vector2i in valid:
		var vertex_index: int = result.faces[ref.x][ref.y]
		var values: Array[Vector2i] = []
		if grouped.has(vertex_index):
			values = grouped[vertex_index]
		values.append(ref)
		grouped[vertex_index] = values
	for vertex_value: Variant in grouped.keys():
		var refs: Array[Vector2i] = []
		refs = grouped[vertex_value]
		if refs.size() < 2:
			continue
		var average: Vector2 = Vector2.ZERO
		for ref: Vector2i in refs:
			average += result.uv_faces[ref.x][ref.y]
		average /= float(refs.size())
		for ref: Vector2i in refs:
			var face_uvs: PackedVector2Array = result.uv_faces[ref.x].duplicate()
			face_uvs[ref.y] = average
			result.uv_faces[ref.x] = face_uvs
	return result


static func split_uv_edges(
	mesh: GDDrawUVMeshData,
	edge_refs: Array[Vector2i]
) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	for ref: Vector2i in edge_refs:
		if ref.x < 0 or ref.x >= result.faces.size():
			continue
		var face: PackedInt32Array = result.faces[ref.x]
		if ref.y < 0 or ref.y >= face.size():
			continue
		var edge: Vector2i = GDDrawUVMeshData.canonical_edge(
			face[ref.y],
			face[(ref.y + 1) % face.size()]
		)
		if not result.seam_edges.has(edge):
			result.seam_edges.append(edge)
	return result


static func stitch_uv_edges(
	mesh: GDDrawUVMeshData,
	edge_refs: Array[Vector2i]
) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	if not result.has_uv_map:
		return result
	var processed: Dictionary = {}
	for ref: Vector2i in edge_refs:
		if ref.x < 0 or ref.x >= result.faces.size():
			continue
		var face: PackedInt32Array = result.faces[ref.x]
		if ref.y < 0 or ref.y >= face.size():
			continue
		var a: int = face[ref.y]
		var b: int = face[(ref.y + 1) % face.size()]
		var edge: Vector2i = GDDrawUVMeshData.canonical_edge(a, b)
		if processed.has(edge):
			continue
		processed[edge] = true
		var topology: GDDrawUVTopology = result.get_topology()
		var attached: PackedInt32Array = topology.get_edge_faces(edge)
		if attached.size() != 2:
			continue
		if result.get_face_material(attached[0]) != result.get_face_material(attached[1]):
			continue
		var fixed_a: Array[Vector2i] = _find_face_vertex_corners(result, attached[0], a)
		var fixed_b: Array[Vector2i] = _find_face_vertex_corners(result, attached[0], b)
		var moving_a: Array[Vector2i] = _find_face_vertex_corners(result, attached[1], a)
		var moving_b: Array[Vector2i] = _find_face_vertex_corners(result, attached[1], b)
		if fixed_a.is_empty() or fixed_b.is_empty() or moving_a.is_empty() or moving_b.is_empty():
			continue

		var target_start: Vector2 = result.uv_faces[fixed_a[0].x][fixed_a[0].y]
		var target_end: Vector2 = result.uv_faces[fixed_b[0].x][fixed_b[0].y]
		var source_start: Vector2 = result.uv_faces[moving_a[0].x][moving_a[0].y]
		var source_end: Vector2 = result.uv_faces[moving_b[0].x][moving_b[0].y]
		var source_vector: Vector2 = source_end - source_start
		var target_vector: Vector2 = target_end - target_start
		if source_vector.length_squared() <= UV_EPSILON * UV_EPSILON:
			continue

		var moving_island: PackedInt32Array = _find_island_containing_face(result, attached[1])
		if moving_island.has(attached[0]):

			result.seam_edges.erase(edge)
			continue
		var scale_factor: float = target_vector.length() / maxf(source_vector.length(), UV_EPSILON)
		var angle: float = source_vector.angle_to(target_vector)
		var cosine: float = cos(angle)
		var sine: float = sin(angle)
		for face_index: int in moving_island:
			var values: PackedVector2Array = result.uv_faces[face_index].duplicate()
			for corner_index: int in values.size():
				var relative: Vector2 = (values[corner_index] - source_start) * scale_factor
				values[corner_index] = target_start + Vector2(
					relative.x * cosine - relative.y * sine,
					relative.x * sine + relative.y * cosine
				)
			result.uv_faces[face_index] = values


		_set_corner_value(result, moving_a[0], target_start)
		_set_corner_value(result, moving_b[0], target_end)
		result.seam_edges.erase(edge)
	return result


static func set_texel_density(
	mesh: GDDrawUVMeshData,
	face_indices: PackedInt32Array,
	target_pixels_per_unit: float,
	texture_size: Vector2i
) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	if not result.has_uv_map:
		return result
	var selected: PackedInt32Array = _valid_faces(result, face_indices)
	if selected.is_empty():
		return result
	var target: float = maxf(target_pixels_per_unit, 0.0001)
	var texture_area: float = float(maxi(texture_size.x, 1) * maxi(texture_size.y, 1))
	for island: PackedInt32Array in get_uv_islands(result, selected):
		var surface_area: float = get_surface_area(result, island)
		var uv_area: float = get_uv_area(result, island)
		if surface_area <= UV_EPSILON or uv_area <= UV_EPSILON:
			continue
		var current: float = sqrt(uv_area * texture_area / surface_area)
		if current <= UV_EPSILON:
			continue
		var scale_factor: float = target / current
		var center: Vector2 = get_uv_center(result, island)
		for face_index: int in island:
			var values: PackedVector2Array = result.uv_faces[face_index].duplicate()
			for corner_index: int in values.size():
				values[corner_index] = center + (values[corner_index] - center) * scale_factor
			result.uv_faces[face_index] = values
	return result


static func get_texel_density(
	mesh: GDDrawUVMeshData,
	face_indices: PackedInt32Array,
	texture_size: Vector2i
) -> float:
	if mesh == null or not mesh.has_uv_map:
		return 0.0
	var selected: PackedInt32Array = _valid_faces(mesh, face_indices)
	var surface_area: float = get_surface_area(mesh, selected)
	var uv_area: float = get_uv_area(mesh, selected)
	if surface_area <= UV_EPSILON or uv_area <= UV_EPSILON:
		return 0.0
	var texture_area: float = float(maxi(texture_size.x, 1) * maxi(texture_size.y, 1))
	return sqrt(uv_area * texture_area / surface_area)


static func get_surface_area(mesh: GDDrawUVMeshData, face_indices: PackedInt32Array) -> float:
	var area: float = 0.0
	for face_index: int in _valid_faces(mesh, face_indices):
		var face: PackedInt32Array = mesh.faces[face_index]
		if face.size() < 3:
			continue
		var origin: Vector3 = mesh.vertices[face[0]]
		for triangle_index: int in range(1, face.size() - 1):
			var a: Vector3 = mesh.vertices[face[triangle_index]] - origin
			var b: Vector3 = mesh.vertices[face[triangle_index + 1]] - origin
			area += a.cross(b).length() * 0.5
	return area


static func get_uv_area(mesh: GDDrawUVMeshData, face_indices: PackedInt32Array) -> float:
	var area: float = 0.0
	if mesh == null or not mesh.has_uv_map:
		return area
	for face_index: int in _valid_faces(mesh, face_indices):
		var values: PackedVector2Array = mesh.uv_faces[face_index]
		if values.size() < 3:
			continue
		var origin: Vector2 = values[0]
		for triangle_index: int in range(1, values.size() - 1):
			var a: Vector2 = values[triangle_index] - origin
			var b: Vector2 = values[triangle_index + 1] - origin
			area += absf(a.cross(b)) * 0.5
	return area


static func get_face_distortion(mesh: GDDrawUVMeshData, face_index: int) -> float:
	if mesh == null or not mesh.has_uv_map or face_index < 0 or face_index >= mesh.faces.size():
		return 0.0
	var faces: PackedInt32Array = PackedInt32Array([face_index])
	var surface_area: float = get_surface_area(mesh, faces)
	var uv_area: float = get_uv_area(mesh, faces)
	if surface_area <= UV_EPSILON or uv_area <= UV_EPSILON:
		return 0.0
	var all_surface: float = get_surface_area(mesh, all_faces(mesh))
	var all_uv: float = get_uv_area(mesh, all_faces(mesh))
	if all_surface <= UV_EPSILON or all_uv <= UV_EPSILON:
		return 0.0
	var expected: float = all_uv / all_surface
	var actual: float = uv_area / surface_area
	return log(maxf(actual / expected, UV_EPSILON)) / log(2.0)


static func get_uv_bounds(mesh: GDDrawUVMeshData, face_indices: PackedInt32Array) -> Rect2:
	var selected: PackedInt32Array = _valid_faces(mesh, face_indices)
	var initialized: bool = false
	var minimum: Vector2 = Vector2.ZERO
	var maximum: Vector2 = Vector2.ZERO
	if mesh == null or not mesh.has_uv_map:
		return Rect2()
	for face_index: int in selected:
		for uv: Vector2 in mesh.uv_faces[face_index]:
			if not initialized:
				minimum = uv
				maximum = uv
				initialized = true
			else:
				minimum.x = minf(minimum.x, uv.x)
				minimum.y = minf(minimum.y, uv.y)
				maximum.x = maxf(maximum.x, uv.x)
				maximum.y = maxf(maximum.y, uv.y)
	if not initialized:
		return Rect2()
	return Rect2(minimum, maximum - minimum)


static func clear_uv_map(mesh: GDDrawUVMeshData) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = _duplicate_for_uv(mesh)
	result.invalidate_uvs()
	return result


static func group_faces_by_material(
	mesh: GDDrawUVMeshData,
	face_indices: PackedInt32Array = PackedInt32Array()
) -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	if mesh == null:
		return result
	var selected: PackedInt32Array = _valid_faces(mesh, face_indices)
	if selected.is_empty() and face_indices.is_empty():
		selected = all_faces(mesh)
	if selected.is_empty():
		return result
	var maximum_material_index: int = 0
	for face_index: int in selected:
		maximum_material_index = maxi(maximum_material_index, mesh.get_face_material(face_index))
	var indexed_groups: Array[PackedInt32Array] = []
	indexed_groups.resize(maximum_material_index + 1)
	for group_index: int in indexed_groups.size():
		indexed_groups[group_index] = PackedInt32Array()
	for face_index: int in selected:
		var material_index: int = clampi(mesh.get_face_material(face_index), 0, indexed_groups.size() - 1)
		indexed_groups[material_index].append(face_index)
	for group: PackedInt32Array in indexed_groups:
		if not group.is_empty():
			result.append(group)
	return result


static func all_faces(mesh: GDDrawUVMeshData) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	if mesh == null:
		return result
	for face_index: int in mesh.faces.size():
		result.append(face_index)
	return result


static func all_corners(mesh: GDDrawUVMeshData) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if mesh == null:
		return result
	for face_index: int in mesh.faces.size():
		for corner_index: int in mesh.faces[face_index].size():
			result.append(Vector2i(face_index, corner_index))
	return result


static func create_checker_texture(size: int = 256, cells: int = 8) -> Texture2D:
	var safe_size: int = clampi(size, 16, 2048)
	var safe_cells: int = clampi(cells, 2, 64)
	var image: Image = Image.create(safe_size, safe_size, false, Image.FORMAT_RGBA8)
	var cell_size: int = maxi(1, int(safe_size / safe_cells))
	for y: int in safe_size:
		for x: int in safe_size:
			var dark: bool = (int(x / cell_size) + int(y / cell_size)) % 2 == 0
			image.set_pixel(
				x,
				y,
				Color(0.16, 0.18, 0.22, 1.0) if dark else Color(0.72, 0.75, 0.8, 1.0)
			)
	return ImageTexture.create_from_image(image)


static func _duplicate_for_uv(mesh: GDDrawUVMeshData) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = mesh.duplicate_mesh_data()
	result.prepare_for_use()
	return result


static func _build_edge_lookup(edges: Array[Vector2i]) -> Dictionary:
	var lookup: Dictionary = {}
	for edge: Vector2i in edges:
		lookup[GDDrawUVMeshData.canonical_edge(edge.x, edge.y)] = true
	return lookup


static func _get_face_surface_area(mesh: GDDrawUVMeshData, face_index: int) -> float:
	if face_index < 0 or face_index >= mesh.faces.size():
		return 0.0
	var face: PackedInt32Array = mesh.faces[face_index]
	if face.size() < 3:
		return 0.0
	var area: float = 0.0
	var origin: Vector3 = mesh.vertices[face[0]]
	for triangle_index: int in range(1, face.size() - 1):
		var a: Vector3 = mesh.vertices[face[triangle_index]] - origin
		var b: Vector3 = mesh.vertices[face[triangle_index + 1]] - origin
		area += a.cross(b).length() * 0.5
	return area


static func _pack_face_groups_in_place(
	mesh: GDDrawUVMeshData,
	islands: Array[PackedInt32Array],
	padding: float,
	job: GDDrawUVBackgroundJob = null,
	progress_start: float = 0.0,
	progress_end: float = 1.0
) -> bool:
	if not mesh.has_uv_map or islands.is_empty():
		return true

	var entries: Array[Dictionary] = []
	var island_count: int = maxi(islands.size(), 1)
	for island_index: int in islands.size():
		if job != null and island_index % 32 == 0:
			if job.is_cancelled():
				return false
			job.update_progress(
				lerpf(progress_start, progress_end, 0.20 * float(island_index) / float(island_count)),
				"Measuring UV islands"
			)
		var island: PackedInt32Array = islands[island_index]
		if island.is_empty():
			continue
		var bounds: Rect2 = get_uv_bounds(mesh, island)
		var bounds_size: Vector2 = bounds.size
		if bounds_size.x <= UV_EPSILON:
			bounds_size.x = UV_EPSILON
		if bounds_size.y <= UV_EPSILON:
			bounds_size.y = UV_EPSILON
		bounds.size = bounds_size
		entries.append({"faces": island, "bounds": bounds})
	if entries.is_empty():
		return true
	entries.sort_custom(_sort_pack_entries)

	var safe_padding: float = clampf(padding, 0.0, 0.2)
	var low: float = 0.001
	var high: float = 10.0
	var best_scale: float = low
	var best_positions: Array[Vector2] = []
	for iteration: int in 28:
		if job != null:
			if job.is_cancelled():
				return false
			job.update_progress(
				lerpf(progress_start, progress_end, 0.20 + 0.45 * float(iteration) / 28.0),
				"Packing UV islands"
			)
		var candidate: float = (low + high) * 0.5
		var packing: Dictionary = _try_shelf_pack(entries, candidate, safe_padding)
		if bool(packing["fits"]):
			best_scale = candidate
			best_positions = packing["positions"]
			low = candidate
		else:
			high = candidate
	if best_positions.size() != entries.size():
		var fallback: Dictionary = _try_shelf_pack(entries, best_scale, safe_padding)
		best_positions = fallback["positions"]

	var entry_count: int = maxi(entries.size(), 1)
	for entry_index: int in entries.size():
		if job != null and entry_index % 16 == 0:
			if job.is_cancelled():
				return false
			job.update_progress(
				lerpf(progress_start, progress_end, 0.65 + 0.35 * float(entry_index) / float(entry_count)),
				"Applying packed UV layout"
			)
		var entry: Dictionary = entries[entry_index]
		var island: PackedInt32Array = entry["faces"]
		var bounds: Rect2 = entry["bounds"]
		var destination: Vector2 = best_positions[entry_index]
		for face_index: int in island:
			var values: PackedVector2Array = mesh.uv_faces[face_index].duplicate()
			for corner_index: int in values.size():
				values[corner_index] = destination + (values[corner_index] - bounds.position) * best_scale
			mesh.uv_faces[face_index] = values
	if job != null:
		job.update_progress(progress_end, "UV islands packed")
	return true


static func _unfold_island(
	mesh: GDDrawUVMeshData,
	island: PackedInt32Array,
	topology: GDDrawUVTopology,
	seam_lookup: Dictionary,
	job: GDDrawUVBackgroundJob = null,
	progress_start: float = 0.0,
	progress_end: float = 1.0
) -> bool:
	if island.is_empty():
		return true
	if job != null and job.is_cancelled():
		return false

	var allowed: Dictionary = {}
	var root_face: int = island[0]
	var largest_area: float = -1.0
	var island_count: int = maxi(island.size(), 1)
	for island_position: int in island.size():
		if job != null and island_position % 128 == 0:
			if job.is_cancelled():
				return false
			job.update_progress(
				lerpf(progress_start, progress_end, 0.15 * float(island_position) / float(island_count)),
				"Preparing UV island"
			)
		var face_index: int = island[island_position]
		allowed[face_index] = true
		var area: float = _get_face_surface_area(mesh, face_index)
		if area > largest_area:
			largest_area = area
			root_face = face_index

	_project_root_face(mesh, root_face)
	var placed: Dictionary = {}
	placed[root_face] = true
	var queue: PackedInt32Array = PackedInt32Array([root_face])
	var queue_head: int = 0
	while queue_head < queue.size():
		if job != null and queue_head % 64 == 0:
			if job.is_cancelled():
				return false
			job.update_progress(
				lerpf(
					progress_start,
					progress_end,
					0.15 + 0.70 * float(placed.size()) / float(island_count)
				),
				"Unfolding UV island"
			)
		var face_index: int = queue[queue_head]
		queue_head += 1
		var face: PackedInt32Array = mesh.faces[face_index]
		for corner_index: int in face.size():
			var edge: Vector2i = GDDrawUVMeshData.canonical_edge(
				face[corner_index],
				face[(corner_index + 1) % face.size()]
			)
			if seam_lookup.has(edge):
				continue
			var attached_half_edges: PackedInt32Array = topology.edge_half_edges[edge]
			for half_edge_index: int in attached_half_edges:
				var neighbour: int = topology.half_edge_face[half_edge_index]
				if neighbour == face_index or not allowed.has(neighbour) or placed.has(neighbour):
					continue
				if _unfold_face_across_edge(mesh, face_index, neighbour, edge):
					placed[neighbour] = true
					queue.append(neighbour)

	for island_position: int in island.size():
		if job != null and island_position % 128 == 0:
			if job.is_cancelled():
				return false
			job.update_progress(
				lerpf(
					progress_start,
					progress_end,
					0.85 + 0.15 * float(island_position) / float(island_count)
				),
				"Finishing UV island"
			)
		var face_index: int = island[island_position]
		if not placed.has(face_index):
			_project_root_face(mesh, face_index)
	if job != null:
		job.update_progress(progress_end, "UV island unfolded")
	return true


static func _project_root_face(mesh: GDDrawUVMeshData, face_index: int) -> void:
	if face_index < 0 or face_index >= mesh.faces.size():
		return
	var face: PackedInt32Array = mesh.faces[face_index]
	if face.size() < 3:
		return

	var origin_index: int = face[0]
	var tangent: Vector3 = Vector3.ZERO
	var longest_length: float = 0.0
	for corner_index: int in face.size():
		var a: Vector3 = mesh.vertices[face[corner_index]]
		var b: Vector3 = mesh.vertices[face[(corner_index + 1) % face.size()]]
		var edge_vector: Vector3 = b - a
		if edge_vector.length_squared() > longest_length:
			longest_length = edge_vector.length_squared()
			origin_index = face[corner_index]
			tangent = edge_vector.normalized()
	if tangent.length_squared() <= UV_EPSILON * UV_EPSILON:
		return

	var normal: Vector3 = mesh.get_face_normal(face_index)
	var bitangent: Vector3 = normal.cross(tangent).normalized()
	if bitangent.length_squared() <= UV_EPSILON * UV_EPSILON:
		var reference: Vector3 = Vector3.UP if absf(tangent.y) < 0.92 else Vector3.RIGHT
		bitangent = reference.cross(tangent).normalized()
	var origin: Vector3 = mesh.vertices[origin_index]
	var values: PackedVector2Array = PackedVector2Array()
	for vertex_index: int in face:
		var relative: Vector3 = mesh.vertices[vertex_index] - origin
		values.append(Vector2(relative.dot(tangent), relative.dot(bitangent)))
	mesh.uv_faces[face_index] = values


static func _unfold_face_across_edge(
	mesh: GDDrawUVMeshData,
	current_face: int,
	neighbour_face: int,
	edge: Vector2i
) -> bool:
	var current_a: Array[Vector2i] = _find_face_vertex_corners(mesh, current_face, edge.x)
	var current_b: Array[Vector2i] = _find_face_vertex_corners(mesh, current_face, edge.y)
	if current_a.is_empty() or current_b.is_empty():
		return false
	var uv_a: Vector2 = mesh.uv_faces[current_a[0].x][current_a[0].y]
	var uv_b: Vector2 = mesh.uv_faces[current_b[0].x][current_b[0].y]
	var uv_edge: Vector2 = uv_b - uv_a
	var uv_length: float = uv_edge.length()
	if uv_length <= UV_EPSILON:
		return false

	var position_a: Vector3 = mesh.vertices[edge.x]
	var position_b: Vector3 = mesh.vertices[edge.y]
	var edge_3d: Vector3 = position_b - position_a
	var edge_length: float = edge_3d.length()
	if edge_length <= UV_EPSILON:
		return false
	var edge_direction: Vector3 = edge_3d / edge_length

	var current_center: Vector2 = Vector2.ZERO
	for uv: Vector2 in mesh.uv_faces[current_face]:
		current_center += uv
	current_center /= float(mesh.uv_faces[current_face].size())
	var current_side: float = uv_edge.cross(current_center - uv_a)
	if absf(current_side) <= UV_EPSILON:
		for uv: Vector2 in mesh.uv_faces[current_face]:
			var candidate_side: float = uv_edge.cross(uv - uv_a)
			if absf(candidate_side) > absf(current_side):
				current_side = candidate_side
	if absf(current_side) <= UV_EPSILON:
		current_side = 1.0
	var desired_side: float = -1.0 if current_side > 0.0 else 1.0

	var neighbour_normal: Vector3 = mesh.get_face_normal(neighbour_face)
	var face_perpendicular: Vector3 = neighbour_normal.cross(edge_direction).normalized()
	if face_perpendicular.length_squared() <= UV_EPSILON * UV_EPSILON:
		return false

	var neighbour_face_vertices: PackedInt32Array = mesh.faces[neighbour_face]
	var representative_height: float = 0.0
	for vertex_index: int in neighbour_face_vertices:
		if vertex_index == edge.x or vertex_index == edge.y:
			continue
		var height: float = (mesh.vertices[vertex_index] - position_a).dot(face_perpendicular)
		if absf(height) > absf(representative_height):
			representative_height = height
	if absf(representative_height) <= UV_EPSILON:
		return false

	var natural_side: float = 1.0 if representative_height > 0.0 else -1.0
	var side_flip: float = desired_side * natural_side
	var uv_direction: Vector2 = uv_edge / uv_length
	var uv_perpendicular: Vector2 = Vector2(-uv_direction.y, uv_direction.x)
	var scale: float = uv_length / edge_length
	var values: PackedVector2Array = PackedVector2Array()
	for vertex_index: int in neighbour_face_vertices:
		var relative: Vector3 = mesh.vertices[vertex_index] - position_a
		var along_edge: float = relative.dot(edge_direction)
		var away_from_edge: float = relative.dot(face_perpendicular)
		values.append(
			uv_a
			+ uv_direction * along_edge * scale
			+ uv_perpendicular * away_from_edge * scale * side_flip
		)
	mesh.uv_faces[neighbour_face] = values
	return true


static func _project_island_best_fit(mesh: GDDrawUVMeshData, island: PackedInt32Array) -> void:
	if island.is_empty():
		return
	var normal_sum: Vector3 = Vector3.ZERO
	var total_area: float = 0.0
	var center: Vector3 = Vector3.ZERO
	var unique_vertices: Dictionary = {}
	var maximum_vertical_normal: float = 0.0
	for face_index: int in island:
		var area: float = get_surface_area(mesh, PackedInt32Array([face_index]))
		var face_normal: Vector3 = mesh.get_face_normal(face_index)
		total_area += maxf(area, UV_EPSILON)
		normal_sum += face_normal * maxf(area, UV_EPSILON)
		maximum_vertical_normal = maxf(maximum_vertical_normal, absf(face_normal.y))
		for vertex_index: int in mesh.faces[face_index]:
			unique_vertices[vertex_index] = true
	for vertex_value: Variant in unique_vertices.keys():
		center += mesh.vertices[int(vertex_value)]
	if not unique_vertices.is_empty():
		center /= float(unique_vertices.size())

	var coherence: float = normal_sum.length() / maxf(total_area, UV_EPSILON)
	if coherence < 0.35:
		var use_cylindrical: bool = maximum_vertical_normal < 0.45
		var bounds: AABB = mesh.get_aabb()
		var height: float = maxf(bounds.size.y, UV_EPSILON)
		for face_index: int in island:
			var values: PackedVector2Array = PackedVector2Array()
			for vertex_index: int in mesh.faces[face_index]:
				var relative: Vector3 = mesh.vertices[vertex_index] - center
				var u: float = atan2(relative.x, relative.z) / TAU + 0.5
				var v: float
				if use_cylindrical:
					v = relative.y / height + 0.5
				else:
					var radius: float = maxf(relative.length(), UV_EPSILON)
					v = asin(clampf(relative.y / radius, -1.0, 1.0)) / PI + 0.5
				values.append(Vector2(u, v))
			_adjust_wrapped_face(values)
			mesh.uv_faces[face_index] = values
		_mark_discontinuous_edges_for_faces(mesh, island)
		return

	var normal: Vector3 = normal_sum.normalized()
	var reference: Vector3 = Vector3.UP
	if absf(normal.dot(reference)) > 0.92:
		reference = Vector3.RIGHT
	var tangent: Vector3 = reference.cross(normal).normalized()
	var bitangent: Vector3 = normal.cross(tangent).normalized()
	var vertex_uv: Dictionary = {}
	for face_index: int in island:
		for vertex_index: int in mesh.faces[face_index]:
			if vertex_uv.has(vertex_index):
				continue
			var relative: Vector3 = mesh.vertices[vertex_index] - center
			vertex_uv[vertex_index] = Vector2(relative.dot(tangent), relative.dot(bitangent))
	for face_index: int in island:
		var values: PackedVector2Array = PackedVector2Array()
		for vertex_index: int in mesh.faces[face_index]:
			values.append(vertex_uv[vertex_index])
		mesh.uv_faces[face_index] = values


static func _mark_discontinuous_edges_for_faces(mesh: GDDrawUVMeshData, faces: PackedInt32Array) -> void:
	var allowed: Dictionary = {}
	for face_index: int in faces:
		allowed[face_index] = true
	var topology: GDDrawUVTopology = mesh.get_topology()
	for face_index: int in faces:
		var face: PackedInt32Array = mesh.faces[face_index]
		for corner_index: int in face.size():
			var edge: Vector2i = GDDrawUVMeshData.canonical_edge(
				face[corner_index], face[(corner_index + 1) % face.size()]
			)
			var attached: PackedInt32Array = topology.get_edge_faces(edge)
			if attached.size() != 2 or not allowed.has(attached[0]) or not allowed.has(attached[1]):
				continue
			if not _edge_uv_continuous_with_faces(mesh, edge, attached) and not mesh.seam_edges.has(edge):
				mesh.seam_edges.append(edge)


static func _sort_pack_entries(a: Dictionary, b: Dictionary) -> bool:
	var bounds_a: Rect2 = a["bounds"]
	var bounds_b: Rect2 = b["bounds"]
	return bounds_a.size.y > bounds_b.size.y


static func _try_shelf_pack(
	entries: Array[Dictionary],
	scale: float,
	padding: float
) -> Dictionary:
	var positions: Array[Vector2] = []
	positions.resize(entries.size())
	var cursor: Vector2 = Vector2(padding, padding)
	var row_height: float = 0.0
	for entry_index: int in entries.size():
		var bounds: Rect2 = entries[entry_index]["bounds"]
		var size: Vector2 = bounds.size * scale
		# Upstream only wrapped rows when the cursor had moved, so an island wider than
		# the tile was accepted at the start of a row and overflowed past 1.0.
		if size.x + padding * 2.0 > 1.0:
			return {"fits": false, "positions": positions}
		if cursor.x + size.x + padding > 1.0 and cursor.x > padding:
			cursor.x = padding
			cursor.y += row_height + padding
			row_height = 0.0
		if cursor.y + size.y + padding > 1.0:
			return {"fits": false, "positions": positions}
		positions[entry_index] = cursor
		cursor.x += size.x + padding
		row_height = maxf(row_height, size.y)
	return {"fits": true, "positions": positions}


static func _get_uv_boundary_corners(mesh: GDDrawUVMeshData, selected_faces: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var topology: GDDrawUVTopology = mesh.get_topology()
	for face_value: Variant in selected_faces.keys():
		var face_index: int = int(face_value)
		var face: PackedInt32Array = mesh.faces[face_index]
		for corner_index: int in face.size():
			var edge: Vector2i = GDDrawUVMeshData.canonical_edge(
				face[corner_index],
				face[(corner_index + 1) % face.size()]
			)
			var attached: PackedInt32Array = topology.get_edge_faces(edge)
			var is_boundary: bool = mesh.seam_edges.has(edge) or attached.size() != 2
			if not is_boundary and mesh.get_face_material(attached[0]) != mesh.get_face_material(attached[1]):
				is_boundary = true
			if not is_boundary:
				for neighbour: int in attached:
					if not selected_faces.has(neighbour):
						is_boundary = true
						break
			if is_boundary:
				result[Vector2i(face_index, corner_index)] = true
				result[Vector2i(face_index, (corner_index + 1) % face.size())] = true
	return result


static func _get_uv_corner_neighbours(
	mesh: GDDrawUVMeshData,
	ref: Vector2i,
	selected_faces: Dictionary
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if ref.x < 0 or ref.x >= mesh.faces.size():
		return result
	var face: PackedInt32Array = mesh.faces[ref.x]
	var count: int = face.size()
	_append_unique_corner(result, Vector2i(ref.x, (ref.y - 1 + count) % count))
	_append_unique_corner(result, Vector2i(ref.x, (ref.y + 1) % count))
	var vertex_index: int = face[ref.y]
	for face_value: Variant in selected_faces.keys():
		var other_face: int = int(face_value)
		if other_face == ref.x:
			continue
		for other_corner: int in mesh.faces[other_face].size():
			if mesh.faces[other_face][other_corner] != vertex_index:
				continue
			if _corners_uv_connected(mesh, ref, Vector2i(other_face, other_corner)):
				_append_unique_corner(result, Vector2i(other_face, other_corner))
	return result


static func _corners_uv_connected(mesh: GDDrawUVMeshData, a: Vector2i, b: Vector2i) -> bool:
	if mesh.faces[a.x][a.y] != mesh.faces[b.x][b.y]:
		return false
	if mesh.get_face_material(a.x) != mesh.get_face_material(b.x):
		return false
	var uv_a: Vector2 = mesh.uv_faces[a.x][a.y]
	var uv_b: Vector2 = mesh.uv_faces[b.x][b.y]
	if uv_a.distance_squared_to(uv_b) > UV_EPSILON * UV_EPSILON:
		return false

	var shared_vertex: int = mesh.faces[a.x][a.y]
	for face_index: int in PackedInt32Array([a.x, b.x]):
		var face: PackedInt32Array = mesh.faces[face_index]
		var corner_index: int = face.find(shared_vertex)
		if corner_index < 0:
			continue
		var previous_edge: Vector2i = GDDrawUVMeshData.canonical_edge(
			face[(corner_index - 1 + face.size()) % face.size()], shared_vertex
		)
		var next_edge: Vector2i = GDDrawUVMeshData.canonical_edge(
			shared_vertex, face[(corner_index + 1) % face.size()]
		)
		if mesh.seam_edges.has(previous_edge) or mesh.seam_edges.has(next_edge):
			return false
	return true


static func _edge_uv_continuous_with_faces(
	mesh: GDDrawUVMeshData,
	edge: Vector2i,
	attached_faces: PackedInt32Array
) -> bool:
	if mesh == null or attached_faces.size() != 2:
		return false
	if not mesh.has_uv_map:
		return true
	for vertex_index: int in PackedInt32Array([edge.x, edge.y]):
		var first: Array[Vector2i] = _find_face_vertex_corners(mesh, attached_faces[0], vertex_index)
		var second: Array[Vector2i] = _find_face_vertex_corners(mesh, attached_faces[1], vertex_index)
		if first.is_empty() or second.is_empty():
			return false
		if mesh.uv_faces[first[0].x][first[0].y].distance_squared_to(
			mesh.uv_faces[second[0].x][second[0].y]
		) > UV_EPSILON * UV_EPSILON:
			return false
	return true


static func _find_island_containing_face(mesh: GDDrawUVMeshData, face_index: int) -> PackedInt32Array:
	for island: PackedInt32Array in get_uv_islands(mesh):
		if island.has(face_index):
			return island
	return PackedInt32Array([face_index])


static func _set_corner_value(mesh: GDDrawUVMeshData, ref: Vector2i, value: Vector2) -> void:
	if ref.x < 0 or ref.x >= mesh.uv_faces.size():
		return
	if ref.y < 0 or ref.y >= mesh.uv_faces[ref.x].size():
		return
	var values: PackedVector2Array = mesh.uv_faces[ref.x].duplicate()
	values[ref.y] = value
	mesh.uv_faces[ref.x] = values


static func _find_face_vertex_corners(
	mesh: GDDrawUVMeshData,
	face_index: int,
	vertex_index: int
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if face_index < 0 or face_index >= mesh.faces.size():
		return result
	for corner_index: int in mesh.faces[face_index].size():
		if mesh.faces[face_index][corner_index] == vertex_index:
			result.append(Vector2i(face_index, corner_index))
	return result


static func _set_corner_pair_average(mesh: GDDrawUVMeshData, a: Vector2i, b: Vector2i) -> void:
	var average: Vector2 = (mesh.uv_faces[a.x][a.y] + mesh.uv_faces[b.x][b.y]) * 0.5
	var values_a: PackedVector2Array = mesh.uv_faces[a.x].duplicate()
	values_a[a.y] = average
	mesh.uv_faces[a.x] = values_a
	var values_b: PackedVector2Array = mesh.uv_faces[b.x].duplicate()
	values_b[b.y] = average
	mesh.uv_faces[b.x] = values_b


static func _append_unique_corner(values: Array[Vector2i], ref: Vector2i) -> void:
	if not values.has(ref):
		values.append(ref)


static func _valid_faces(mesh: GDDrawUVMeshData, face_indices: PackedInt32Array) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	if mesh == null:
		return result
	for face_index: int in face_indices:
		if face_index >= 0 and face_index < mesh.faces.size() and not result.has(face_index):
			result.append(face_index)
	return result


static func _valid_corners(mesh: GDDrawUVMeshData, corners: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if mesh == null:
		return result
	for ref: Vector2i in corners:
		if ref.x < 0 or ref.x >= mesh.faces.size():
			continue
		if ref.y < 0 or ref.y >= mesh.faces[ref.x].size():
			continue
		if not result.has(ref):
			result.append(ref)
	return result


static func _planar_coordinates(position: Vector3, axis: int) -> Vector2:
	match axis:
		ProjectionAxis.X:
			return Vector2(-position.z, position.y)
		ProjectionAxis.Y:
			return Vector2(position.x, -position.z)
		_:
			return Vector2(position.x, position.y)


static func _normalization_mapping(points: PackedVector2Array) -> Dictionary:
	if points.is_empty():
		return {"center": Vector2.ZERO, "extent": 1.0}
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point: Vector2 in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	var size: Vector2 = maximum - minimum
	return {
		"center": (minimum + maximum) * 0.5,
		"extent": maxf(maxf(size.x, size.y), 0.000001),
	}


static func _normalize_point(point: Vector2, mapping: Dictionary) -> Vector2:
	var center: Vector2 = mapping["center"]
	return (point - center) / float(mapping["extent"]) + Vector2(0.5, 0.5)


static func _dominant_axis(normal: Vector3) -> int:
	var absolute: Vector3 = normal.abs()
	if absolute.x >= absolute.y and absolute.x >= absolute.z:
		return ProjectionAxis.X
	if absolute.y >= absolute.z:
		return ProjectionAxis.Y
	return ProjectionAxis.Z


static func _adjust_wrapped_face(face_uvs: PackedVector2Array) -> void:
	if face_uvs.is_empty():
		return
	var minimum_u: float = face_uvs[0].x
	var maximum_u: float = face_uvs[0].x
	for uv: Vector2 in face_uvs:
		minimum_u = minf(minimum_u, uv.x)
		maximum_u = maxf(maximum_u, uv.x)
	if maximum_u - minimum_u <= 0.5:
		return
	for corner_index: int in face_uvs.size():
		if face_uvs[corner_index].x < 0.5:
			var adjusted: Vector2 = face_uvs[corner_index]
			adjusted.x += 1.0
			face_uvs[corner_index] = adjusted
