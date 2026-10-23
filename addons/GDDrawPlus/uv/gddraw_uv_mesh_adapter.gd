@tool
class_name GDDrawUVMeshAdapter
extends RefCounted

## Bridges a Godot Mesh and the polygon-based GDDrawUVMeshData used by the UV tools.
##
## The UV algorithms need welded topology (shared vertices between neighbouring
## faces), but a Godot mesh duplicates vertices wherever normals, UVs or other
## attributes differ. This adapter therefore:
##   1. welds vertices by position into a GDDrawUVMeshData (one face per triangle,
##      face material = surface index), remembering which source vertex every face
##      corner came from, and
##   2. rebuilds each surface after editing by splitting a source vertex wherever
##      its corners ended up with different UVs, copying EVERY other attribute
##      (bones, weights, normals, tangents, colors, UV2, custom data, blend shapes)
##      from the source vertex. Skinning therefore survives an unwrap unchanged.
##
## Only the UV1 channel (ARRAY_TEX_UV) is ever modified.

## Marked seams are stored on the saved mesh as pairs of 3D positions (not vertex
## indices, which change whenever vertices are split) so they survive re-import.
const SEAM_META_KEY := "gddraw_uv_seams"
## Packing grid xatlas works at. Only affects how charts are segmented and flattened, the
## final layout is repacked with the requested margin.
const XATLAS_RESOLUTION := 512
const WELD_PRECISION := 100000.0
const UV_PRECISION := 1000000.0
const PRESERVED_FORMAT_FLAGS := (
	Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	| Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE
	| Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
)

var source_mesh: ArrayMesh
var data: GDDrawUVMeshData

## Unwrap methods offered in the UI. SMART is the default and the best choice for characters;
## the others are Gator's simple projections, useful for props, quick tests and hard surfaces.
enum UnwrapMethod {
	SMART,
	BOX,
	CYLINDER,
	SPHERE,
	PLANAR_FRONT,
	PLANAR_SIDE,
	PLANAR_TOP,
}

const METHODS := [
	{
		"id": UnwrapMethod.SMART,
		"label": "Smart (automatic)",
		"tooltip": "Cuts the mesh into low-distortion charts and packs them. Best for characters and organic shapes. Slow on very dense meshes.",
	},
	{
		"id": UnwrapMethod.BOX,
		"label": "Box",
		"tooltip": "Projects every face along the nearest of the three axes, like a cube map. Fast; good for crates, walls and other hard surfaces.",
	},
	{
		"id": UnwrapMethod.CYLINDER,
		"label": "Cylinder",
		"tooltip": "Wraps the UVs around the vertical axis like a label on a can. Fast; good for pillars, limbs and bottles. Caps get squashed.",
	},
	{
		"id": UnwrapMethod.SPHERE,
		"label": "Sphere",
		"tooltip": "Wraps the UVs around the center like a globe. Fast; good for heads, balls and planets. The poles get pinched.",
	},
	{
		"id": UnwrapMethod.PLANAR_FRONT,
		"label": "Planar, front (Z axis)",
		"tooltip": "Projects straight through the model along the Z axis. Front and back overlap; meant for flat things like signs and decals.",
	},
	{
		"id": UnwrapMethod.PLANAR_SIDE,
		"label": "Planar, side (X axis)",
		"tooltip": "Projects straight through the model along the X axis. Left and right overlap; meant for flat things.",
	},
	{
		"id": UnwrapMethod.PLANAR_TOP,
		"label": "Planar, top (Y axis)",
		"tooltip": "Projects straight down along the Y axis. Top and bottom overlap; meant for flat things like floors and roofs.",
	},
]

## Surfaces the last xatlas unwrap could not handle and that fell back to angle-based cuts.
var xatlas_fallback_surfaces := PackedInt32Array()

var _weld_lookup := {}
var _surface_arrays: Array = []
var _surface_indices: Array[PackedInt32Array] = []
var _surface_welded: Array[PackedInt32Array] = []
var _surface_supported: Array[bool] = []
var _triangle_face: Array[PackedInt32Array] = []
var _welded_positions := PackedVector3Array()


## Returns null when the mesh has no triangle geometry the UV tools can use.
## Non-ArrayMesh sources (BoxMesh, CapsuleMesh, ...) are converted to an ArrayMesh first.
static func from_mesh(mesh: Mesh) -> GDDrawUVMeshAdapter:
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null:
		array_mesh = _convert_to_array_mesh(mesh)
	var adapter := GDDrawUVMeshAdapter.new()
	if not adapter._import(array_mesh):
		return null
	return adapter


static func _convert_to_array_mesh(mesh: Mesh) -> ArrayMesh:
	var converted := ArrayMesh.new()
	converted.resource_name = mesh.resource_name
	for surface_index in range(mesh.get_surface_count()):
		converted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(surface_index))
		converted.surface_set_material(surface_index, mesh.surface_get_material(surface_index))
	return converted


func get_surface_count() -> int:
	return source_mesh.get_surface_count() if source_mesh else 0


func get_surface_name(surface_index: int) -> String:
	if source_mesh == null or surface_index < 0 or surface_index >= source_mesh.get_surface_count():
		return ""
	var surface_name := source_mesh.surface_get_name(surface_index)
	return surface_name if not surface_name.is_empty() else "Surface %d" % surface_index


func is_surface_supported(surface_index: int) -> bool:
	return surface_index >= 0 and surface_index < _surface_supported.size() and _surface_supported[surface_index]


## Chart-based automatic unwrap using Godot's built-in xatlas (ArrayMesh.lightmap_unwrap):
## the mesh is segmented into low-distortion charts, flattened and packed without overlap.
## This is the recommended one-click unwrap. Each surface gets its own 0-1 tile, because
## GDDraw paints one material slot texture at a time.
##
## xatlas is used for what it does best, cutting the mesh into charts and flattening them.
## Its own packer pads by less than one texel (islands nearly touch, which bleeds paint on
## mipmapped textures), so the resulting islands are repacked with a true `margin`: the
## empty gap between every pair of islands and around the tile border, as a fraction of it.
##
## `base` is the data to write into (defaults to the imported data, seams and other
## surfaces are kept); `surfaces` limits the unwrap to those surface indices.
## Surfaces xatlas cannot handle fall back to Smart UV Project and are listed in
## `xatlas_fallback_surfaces`.
func auto_unwrap_xatlas(margin := 0.01, base: GDDrawUVMeshData = null, surfaces := PackedInt32Array()) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = (base if base != null else data).duplicate_mesh_data()
	xatlas_fallback_surfaces = PackedInt32Array()
	var unwrapped_surfaces := PackedInt32Array()
	for surface_index in range(get_surface_count()):
		if not is_surface_supported(surface_index):
			continue
		if not surfaces.is_empty() and not surfaces.has(surface_index):
			continue
		if _xatlas_surface(surface_index, XATLAS_RESOLUTION, result):
			unwrapped_surfaces.push_back(surface_index)
		else:
			xatlas_fallback_surfaces.push_back(surface_index)
	result.has_uv_map = true
	for surface_index in unwrapped_surfaces:
		var repacked := GDDrawUVOperations.pack_islands(result, _faces_of_surface(result, surface_index), margin)
		if repacked != null:
			result = repacked
	for surface_index in xatlas_fallback_surfaces:
		var group := _faces_of_surface(result, surface_index)
		if group.is_empty():
			continue
		var fallback := GDDrawUVOperations.smart_uv_project(result, group, 66.0, margin)
		if fallback != null:
			result = fallback
	result.has_uv_map = true
	result.mark_changed()
	return result


## Single entry point for every unwrap method. Each surface gets its own 0-1 tile and every
## method ends with the same margin-honouring repack. `surfaces` limits it to some surfaces.
func unwrap(method: int, margin := 0.01, base: GDDrawUVMeshData = null, surfaces := PackedInt32Array()) -> GDDrawUVMeshData:
	if method == UnwrapMethod.SMART:
		return auto_unwrap_xatlas(margin, base, surfaces)
	xatlas_fallback_surfaces = PackedInt32Array()
	var result: GDDrawUVMeshData = (base if base != null else data).duplicate_mesh_data()
	for surface_index in range(get_surface_count()):
		if not is_surface_supported(surface_index):
			continue
		if not surfaces.is_empty() and not surfaces.has(surface_index):
			continue
		var faces := _faces_of_surface(result, surface_index)
		if faces.is_empty():
			continue
		var projected := _project(result, faces, method)
		if projected == null:
			continue
		result = projected
		var repacked := GDDrawUVOperations.pack_islands(result, faces, margin)
		if repacked != null:
			result = repacked
	result.has_uv_map = true
	result.mark_changed()
	return result


static func get_method_label(method: int) -> String:
	for entry in METHODS:
		if entry["id"] == method:
			return entry["label"]
	return "Unknown"


static func _project(uv_data: GDDrawUVMeshData, faces: PackedInt32Array, method: int) -> GDDrawUVMeshData:
	match method:
		UnwrapMethod.BOX:
			return GDDrawUVOperations.project_box(uv_data, faces)
		UnwrapMethod.CYLINDER:
			return GDDrawUVOperations.project_cylindrical(uv_data, faces)
		UnwrapMethod.SPHERE:
			return GDDrawUVOperations.project_spherical(uv_data, faces)
		UnwrapMethod.PLANAR_FRONT:
			return GDDrawUVOperations.project_planar(uv_data, faces, GDDrawUVOperations.ProjectionAxis.Z)
		UnwrapMethod.PLANAR_SIDE:
			return GDDrawUVOperations.project_planar(uv_data, faces, GDDrawUVOperations.ProjectionAxis.X)
		UnwrapMethod.PLANAR_TOP:
			return GDDrawUVOperations.project_planar(uv_data, faces, GDDrawUVOperations.ProjectionAxis.Y)
	return null


func _faces_of_surface(uv_data: GDDrawUVMeshData, surface_index: int) -> PackedInt32Array:
	var faces := PackedInt32Array()
	for face_index in range(uv_data.faces.size()):
		if uv_data.get_face_material(face_index) == surface_index:
			faces.push_back(face_index)
	return faces


## Angle-based alternative (Gator's Smart UV Project) applied to every supported surface.
## Only cuts where faces meet at a sharp angle, so smooth closed shapes stay a single
## tangled island; prefer auto_unwrap_xatlas() for one-click results.
func auto_unwrap(angle_degrees := 66.0, padding := 0.02) -> GDDrawUVMeshData:
	var result: GDDrawUVMeshData = data
	var groups := GDDrawUVOperations.group_faces_by_material(result)
	for group in groups:
		result = GDDrawUVOperations.smart_uv_project(result, group, angle_degrees, padding)
		if result == null:
			return null
	return result


## Builds a new ArrayMesh from the source mesh, taking UV1 from `uv_data`
## (defaults to the adapter's current data). Everything except UV1 is copied
## from the source; vertices are split where UV corners differ.
func build_mesh(uv_data: GDDrawUVMeshData = null) -> ArrayMesh:
	if uv_data == null:
		uv_data = data
	var welded_uvs := _collect_welded_uvs(uv_data)
	var result := ArrayMesh.new()
	result.resource_name = source_mesh.resource_name
	result.blend_shape_mode = source_mesh.blend_shape_mode
	result.custom_aabb = source_mesh.custom_aabb
	for blend_index in range(source_mesh.get_blend_shape_count()):
		result.add_blend_shape(source_mesh.get_blend_shape_name(blend_index))

	for surface_index in range(source_mesh.get_surface_count()):
		var primitive: int = source_mesh.surface_get_primitive_type(surface_index)
		var flags: int = source_mesh.surface_get_format(surface_index) & PRESERVED_FORMAT_FLAGS
		var blend_arrays: Array = source_mesh.surface_get_blend_shape_arrays(surface_index)
		var arrays: Array
		if is_surface_supported(surface_index):
			var rebuilt := _rebuild_surface(surface_index, uv_data, welded_uvs)
			arrays = rebuilt["arrays"]
			blend_arrays = _remap_blend_shapes(blend_arrays, rebuilt["source_indices"], rebuilt["source_vertex_count"])
			if _has_eight_weights(arrays):
				flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		else:
			arrays = source_mesh.surface_get_arrays(surface_index)
		result.add_surface_from_arrays(primitive, arrays, blend_arrays, {}, flags)
		var new_index := result.get_surface_count() - 1
		result.surface_set_material(new_index, source_mesh.surface_get_material(surface_index))
		result.surface_set_name(new_index, source_mesh.surface_get_name(surface_index))
	_store_seams(result, uv_data)
	return result


func _store_seams(target: ArrayMesh, uv_data: GDDrawUVMeshData) -> void:
	var points := PackedVector3Array()
	for edge in uv_data.seam_edges:
		if edge.x < 0 or edge.y < 0 or edge.x >= uv_data.vertices.size() or edge.y >= uv_data.vertices.size():
			continue
		points.push_back(uv_data.vertices[edge.x])
		points.push_back(uv_data.vertices[edge.y])
	if points.is_empty():
		if target.has_meta(SEAM_META_KEY):
			target.remove_meta(SEAM_META_KEY)
	else:
		target.set_meta(SEAM_META_KEY, points)


func _import(mesh: ArrayMesh) -> bool:
	source_mesh = mesh
	var vertices := PackedVector3Array()
	var faces: Array[PackedInt32Array] = []
	var uv_faces: Array[PackedVector2Array] = []
	var face_materials := PackedInt32Array()
	var weld_lookup := {}
	var any_uvs := false
	var any_faces := false

	for surface_index in range(mesh.get_surface_count()):
		var supported := false
		var arrays: Array = []
		var indices := PackedInt32Array()
		var triangle_face := PackedInt32Array()
		var welded := PackedInt32Array()
		if mesh.surface_get_primitive_type(surface_index) == Mesh.PRIMITIVE_TRIANGLES:
			arrays = mesh.surface_get_arrays(surface_index)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array else PackedVector3Array()
			if positions.size() >= 3:
				indices = _get_triangle_indices(arrays, positions.size())
				var uvs := PackedVector2Array()
				if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array and (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == positions.size():
					uvs = arrays[Mesh.ARRAY_TEX_UV]
					any_uvs = true
				welded.resize(positions.size())
				for vertex_index in range(positions.size()):
					var position := positions[vertex_index]
					var key := _weld_key(position)
					var welded_index: int = weld_lookup.get(key, -1)
					if welded_index < 0:
						welded_index = vertices.size()
						weld_lookup[key] = welded_index
						vertices.push_back(position)
					welded[vertex_index] = welded_index
				var triangle_count := indices.size() / 3
				triangle_face.resize(triangle_count)
				for triangle in range(triangle_count):
					var a := indices[triangle * 3]
					var b := indices[triangle * 3 + 1]
					var c := indices[triangle * 3 + 2]
					var wa := welded[a]
					var wb := welded[b]
					var wc := welded[c]
					if wa == wb or wb == wc or wc == wa:
						triangle_face[triangle] = -1
						continue
					triangle_face[triangle] = faces.size()
					faces.push_back(PackedInt32Array([wa, wb, wc]))
					if uvs.is_empty():
						uv_faces.push_back(PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]))
					else:
						uv_faces.push_back(PackedVector2Array([uvs[a], uvs[b], uvs[c]]))
					face_materials.push_back(surface_index)
					any_faces = true
				supported = true
		_surface_arrays.push_back(arrays)
		_surface_indices.push_back(indices)
		_surface_welded.push_back(welded)
		_surface_supported.push_back(supported)
		_triangle_face.push_back(triangle_face)

	if not any_faces:
		return false
	_welded_positions = vertices
	_weld_lookup = weld_lookup
	var seams := _read_stored_seams(mesh, weld_lookup)
	data = GDDrawUVMeshData.new()
	data.set_geometry(
		vertices,
		faces,
		PackedByteArray(),
		uv_faces,
		any_uvs,
		[],
		false,
		[],
		[],
		PackedFloat32Array(),
		seams,
		face_materials
	)
	return data.is_valid()


## Unwraps one surface with xatlas and writes the resulting per-corner UVs into `target`.
## Output triangles are matched back to source faces by their (welded) corner positions.
func _xatlas_surface(surface_index: int, resolution: int, target: GDDrawUVMeshData) -> bool:
	var arrays: Array = _surface_arrays[surface_index]
	var indices: PackedInt32Array = _surface_indices[surface_index]
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var triangle_face: PackedInt32Array = _triangle_face[surface_index]
	if indices.size() < 3:
		return false

	var area := 0.0
	for triangle in range(indices.size() / 3):
		var a := positions[indices[triangle * 3]]
		area += (positions[indices[triangle * 3 + 1]] - a).cross(positions[indices[triangle * 3 + 2]] - a).length() * 0.5
	if area <= 0.0000001:
		return false

	var temp_arrays: Array = []
	temp_arrays.resize(Mesh.ARRAY_MAX)
	temp_arrays[Mesh.ARRAY_VERTEX] = positions
	var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
	if normals is PackedVector3Array and (normals as PackedVector3Array).size() == positions.size():
		temp_arrays[Mesh.ARRAY_NORMAL] = normals
	else:
		temp_arrays[Mesh.ARRAY_NORMAL] = _compute_smooth_normals(positions, indices)
	temp_arrays[Mesh.ARRAY_INDEX] = indices
	var temp := ArrayMesh.new()
	temp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, temp_arrays)

	# About 70% of the atlas ends up covered, so size one texel to make the whole
	# surface area span roughly `resolution` texels across.
	var texel_size := sqrt(area / (0.7 * float(resolution) * float(resolution)))
	if temp.lightmap_unwrap(Transform3D.IDENTITY, texel_size) != OK or temp.get_surface_count() == 0:
		return false
	var output := temp.surface_get_arrays(0)
	if not (output[Mesh.ARRAY_TEX_UV2] is PackedVector2Array) or not (output[Mesh.ARRAY_VERTEX] is PackedVector3Array) or not (output[Mesh.ARRAY_INDEX] is PackedInt32Array):
		return false
	var out_uvs: PackedVector2Array = output[Mesh.ARRAY_TEX_UV2]
	var out_positions: PackedVector3Array = output[Mesh.ARRAY_VERTEX]
	var out_indices: PackedInt32Array = output[Mesh.ARRAY_INDEX]

	# Source triangle lookup keyed by the sorted welded corner ids; duplicate triangles
	# (coincident faces) are consumed one by one.
	var lookup := {}
	for triangle in range(triangle_face.size()):
		var face := triangle_face[triangle]
		if face < 0:
			continue
		var corners: PackedInt32Array = target.faces[face]
		var key := _sorted_key(corners[0], corners[1], corners[2])
		if not lookup.has(key):
			lookup[key] = []
		(lookup[key] as Array).push_back(face)

	var assigned_faces := {}
	var out_welded := PackedInt32Array()
	out_welded.resize(out_positions.size())
	for vertex_index in range(out_positions.size()):
		out_welded[vertex_index] = _weld_lookup.get(_weld_key(out_positions[vertex_index]), -1)
	for triangle in range(out_indices.size() / 3):
		var o0 := out_indices[triangle * 3]
		var o1 := out_indices[triangle * 3 + 1]
		var o2 := out_indices[triangle * 3 + 2]
		var w0 := out_welded[o0]
		var w1 := out_welded[o1]
		var w2 := out_welded[o2]
		if w0 < 0 or w1 < 0 or w2 < 0:
			continue
		var key := _sorted_key(w0, w1, w2)
		if not lookup.has(key) or (lookup[key] as Array).is_empty():
			continue
		var face: int = (lookup[key] as Array).pop_front()
		var corners: PackedInt32Array = target.faces[face]
		var face_uvs := PackedVector2Array()
		face_uvs.resize(3)
		var corner_uv := {w0: out_uvs[o0], w1: out_uvs[o1], w2: out_uvs[o2]}
		for corner in range(3):
			face_uvs[corner] = corner_uv.get(corners[corner], Vector2.ZERO)
		target.uv_faces[face] = face_uvs
		assigned_faces[face] = true
	var expected := 0
	for face in triangle_face:
		if face >= 0:
			expected += 1
	# A mostly unmatched result means the matching failed and the surface should fall back.
	if expected == 0 or assigned_faces.size() < int(expected * 0.9):
		return false
	# Faces xatlas dropped (zero-area slivers) take the UV their vertex received from a
	# neighbouring face, so they sit inside the layout instead of keeping stale UVs.
	if assigned_faces.size() < expected:
		var welded_uv := {}
		for face in assigned_faces:
			var face_corners: PackedInt32Array = target.faces[face]
			for corner in range(3):
				welded_uv[face_corners[corner]] = target.uv_faces[face][corner]
		for face in triangle_face:
			if face < 0 or assigned_faces.has(face):
				continue
			var face_corners: PackedInt32Array = target.faces[face]
			var patched := PackedVector2Array()
			patched.resize(3)
			for corner in range(3):
				patched[corner] = welded_uv.get(face_corners[corner], Vector2.ZERO)
			target.uv_faces[face] = patched
	return true


static func _sorted_key(a: int, b: int, c: int) -> Vector3i:
	var ids := [a, b, c]
	ids.sort()
	return Vector3i(ids[0], ids[1], ids[2])


static func _compute_smooth_normals(positions: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(positions.size())
	for triangle in range(indices.size() / 3):
		var a := indices[triangle * 3]
		var b := indices[triangle * 3 + 1]
		var c := indices[triangle * 3 + 2]
		var face_normal := (positions[b] - positions[a]).cross(positions[c] - positions[a])
		normals[a] += face_normal
		normals[b] += face_normal
		normals[c] += face_normal
	for index in range(normals.size()):
		normals[index] = normals[index].normalized() if normals[index].length_squared() > 0.0 else Vector3.UP
	return normals


static func _weld_key(position: Vector3) -> Vector3i:
	return Vector3i(
		roundi(position.x * WELD_PRECISION),
		roundi(position.y * WELD_PRECISION),
		roundi(position.z * WELD_PRECISION)
	)


func _read_stored_seams(mesh: ArrayMesh, weld_lookup: Dictionary) -> Array[Vector2i]:
	var seams: Array[Vector2i] = []
	if not mesh.has_meta(SEAM_META_KEY):
		return seams
	var stored: Variant = mesh.get_meta(SEAM_META_KEY)
	if not (stored is PackedVector3Array):
		return seams
	var points: PackedVector3Array = stored
	for index in range(0, points.size() - 1, 2):
		var a: int = weld_lookup.get(_weld_key(points[index]), -1)
		var b: int = weld_lookup.get(_weld_key(points[index + 1]), -1)
		if a < 0 or b < 0 or a == b:
			continue
		var edge := GDDrawUVMeshData.canonical_edge(a, b)
		if not seams.has(edge):
			seams.push_back(edge)
	return seams


## Degenerate triangles (collapsed by welding, e.g. at capsule poles) are not part of
## the UV data. Their corners take the UV their welded position received from a real
## face, so they stay inside the layout instead of keeping stray pre-unwrap UVs.
## Returns {welded index: UV} for every welded vertex used by at least one face.
func _collect_welded_uvs(uv_data: GDDrawUVMeshData) -> Dictionary:
	var result := {}
	for face_index in range(mini(uv_data.faces.size(), uv_data.uv_faces.size())):
		var face := uv_data.faces[face_index]
		var face_uvs := uv_data.uv_faces[face_index]
		for corner in range(mini(face.size(), face_uvs.size())):
			if not result.has(face[corner]):
				result[face[corner]] = face_uvs[corner]
	return result


func _rebuild_surface(surface_index: int, uv_data: GDDrawUVMeshData, welded_uvs: Dictionary) -> Dictionary:
	var arrays: Array = _surface_arrays[surface_index]
	var indices: PackedInt32Array = _surface_indices[surface_index]
	var triangle_face: PackedInt32Array = _triangle_face[surface_index]
	var welded: PackedInt32Array = _surface_welded[surface_index]
	var source_positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var source_uvs := PackedVector2Array()
	if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array and (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == source_positions.size():
		source_uvs = arrays[Mesh.ARRAY_TEX_UV]

	var lookup := {}
	var source_indices := PackedInt32Array()
	var new_uvs := PackedVector2Array()
	var new_indices := PackedInt32Array()
	new_indices.resize(indices.size())
	for triangle in range(triangle_face.size()):
		var face := triangle_face[triangle]
		for corner in range(3):
			var source_index := indices[triangle * 3 + corner]
			var uv := Vector2.ZERO
			if face >= 0 and face < uv_data.uv_faces.size() and corner < uv_data.uv_faces[face].size():
				uv = uv_data.uv_faces[face][corner]
			elif welded_uvs.has(welded[source_index]):
				uv = welded_uvs[welded[source_index]]
			elif not source_uvs.is_empty():
				uv = source_uvs[source_index]
			var key := Vector3i(source_index, roundi(uv.x * UV_PRECISION), roundi(uv.y * UV_PRECISION))
			var new_index: int = lookup.get(key, -1)
			if new_index < 0:
				new_index = source_indices.size()
				lookup[key] = new_index
				source_indices.push_back(source_index)
				new_uvs.push_back(uv)
			new_indices[triangle * 3 + corner] = new_index

	var source_vertex_count := source_positions.size()
	var rebuilt: Array = []
	rebuilt.resize(Mesh.ARRAY_MAX)
	for array_type in range(Mesh.ARRAY_MAX):
		if array_type == Mesh.ARRAY_INDEX:
			rebuilt[array_type] = new_indices
		elif array_type == Mesh.ARRAY_TEX_UV:
			rebuilt[array_type] = new_uvs
		else:
			rebuilt[array_type] = _remap_vertex_array(arrays[array_type], source_indices, source_vertex_count)
	return {
		"arrays": rebuilt,
		"source_indices": source_indices,
		"source_vertex_count": source_vertex_count,
	}


func _remap_blend_shapes(blend_arrays: Array, source_indices: PackedInt32Array, source_vertex_count: int) -> Array:
	var result: Array = []
	for blend_shape in blend_arrays:
		var remapped: Array = []
		remapped.resize(Mesh.ARRAY_MAX)
		for array_type in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT]:
			remapped[array_type] = _remap_vertex_array(blend_shape[array_type], source_indices, source_vertex_count)
		result.push_back(remapped)
	return result


## Copies per-vertex data from `source_indices`. The stride (values per vertex) is
## derived from the array itself, so 4/8 bone influences, tangents and custom
## channels of any format are all handled by the same code.
func _remap_vertex_array(source: Variant, source_indices: PackedInt32Array, source_vertex_count: int) -> Variant:
	if source == null or source_vertex_count <= 0:
		return source
	if not (
		source is PackedVector3Array or source is PackedVector2Array or source is PackedColorArray
		or source is PackedFloat32Array or source is PackedInt32Array or source is PackedByteArray
	):
		return source
	var source_size: int = source.size()
	if source_size == 0 or source_size % source_vertex_count != 0:
		return source
	var stride := source_size / source_vertex_count
	var result: Variant = source.duplicate()
	result.resize(source_indices.size() * stride)
	if stride == 1:
		for index in range(source_indices.size()):
			result[index] = source[source_indices[index]]
	else:
		for index in range(source_indices.size()):
			var from_offset := source_indices[index] * stride
			var to_offset := index * stride
			for element in range(stride):
				result[to_offset + element] = source[from_offset + element]
	return result


func _has_eight_weights(arrays: Array) -> bool:
	var bones: Variant = arrays[Mesh.ARRAY_BONES]
	var positions: Variant = arrays[Mesh.ARRAY_VERTEX]
	if not (bones is PackedInt32Array) or not (positions is PackedVector3Array):
		return false
	return (positions as PackedVector3Array).size() > 0 and (bones as PackedInt32Array).size() == (positions as PackedVector3Array).size() * 8


func _get_triangle_indices(arrays: Array, vertex_count: int) -> PackedInt32Array:
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices.resize(vertex_count)
		for index in range(vertex_count):
			indices[index] = index
	var usable := indices.size() - indices.size() % 3
	if usable != indices.size():
		indices.resize(usable)
	return indices
