@tool
class_name UBOpUV
extends RefCounted
## Manual-UV operations for the UV editor.


## Every corner of every face in the set, as corner keys.
static func corners_of(data, face_set: Dictionary) -> Dictionary:
	var out := {}
	for fi in UBOpUtils.valid_faces(data, face_set):
		for ci in data.faces[fi].vertices.size():
			out[Vector2i(fi, ci)] = true
	return out


## Converts faces to manual UVs from their current auto projection.
static func bake_manual(data, face_set: Dictionary, world_transform := Transform3D.IDENTITY) -> void:
	for fi in UBOpUtils.valid_faces(data, face_set):
		var face: UBFace = data.faces[fi]
		if face.uv_manual and face.uv_coords.size() == face.vertices.size():
			continue
		var corners := PackedVector3Array()
		for vi in face.vertices:
			corners.append(data.positions[vi])
		face.uv_coords = UBUVUnwrap.face_uvs(
			corners, data.face_normal(face), face, world_transform)
		face.uv_manual = true


## Returns faces to auto projection along their own normal.
static func clear_manual(data, face_set: Dictionary) -> void:
	for fi in UBOpUtils.valid_faces(data, face_set):
		var face: UBFace = data.faces[fi]
		face.uv_manual = false
		face.uv_coords = PackedVector2Array()
		face.uv_axis = Vector3.ZERO


## Apply an affine transform to the given corners' UVs.
static func transform_uvs(data, corner_set: Dictionary, xf: Transform2D) -> void:
	for key: Vector2i in _valid_corners(corner_set):
		var face := _manual_face(data, key.x)
		if face == null or key.y < 0 or key.y >= face.uv_coords.size():
			continue
		var coords := face.uv_coords
		coords[key.y] = xf * coords[key.y]
		face.uv_coords = coords


## Set corners' UVs outright. A drag-move passes original + delta, not an increment.
static func set_uvs(data, corner_uvs: Dictionary) -> void:
	for key: Vector2i in _valid_corners(corner_uvs):
		var face := _manual_face(data, key.x)
		if face == null or key.y < 0 or key.y >= face.uv_coords.size() \
				or not corner_uvs[key] is Vector2:
			continue
		var coords := face.uv_coords
		coords[key.y] = corner_uvs[key]
		face.uv_coords = coords


## Projects the set as one island along its average normal; makes the faces manual.
static func planar_project(data, face_set: Dictionary, fit := true) -> void:
	face_set = UBOpUtils.valid_faces(data, face_set)
	var normal := Vector3.ZERO
	for fi in face_set:
		normal += data.face_normal(data.faces[fi])
	if normal.length_squared() < 1e-10:
		normal = Vector3.UP
	normal = normal.normalized()
	var axis := Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.UP
	var u := (axis - normal * axis.dot(normal)).normalized()
	var w := normal.cross(u)
	for fi in face_set:
		var face: UBFace = data.faces[fi]
		var coords := PackedVector2Array()
		for vi in face.vertices:
			var p: Vector3 = data.positions[vi]
			coords.append(Vector2(p.dot(u), p.dot(w)))
		face.uv_coords = coords
		face.uv_manual = true
	if fit:
		fit_to_unit(data, face_set)


## Per-face dominant-axis projection; makes the faces manual.
static func box_project(data, face_set: Dictionary, fit := true) -> void:
	face_set = UBOpUtils.valid_faces(data, face_set)
	for fi in face_set:
		var face: UBFace = data.faces[fi]
		var frame: Array = UBUVUnwrap.projection_frame(data.face_normal(face))
		var coords := PackedVector2Array()
		for vi in face.vertices:
			var p: Vector3 = data.positions[vi]
			coords.append(Vector2(p.dot(frame[0]), p.dot(frame[1])))
		face.uv_coords = coords
		face.uv_manual = true
	if fit:
		fit_to_unit(data, face_set)


## Sew: corners in the set that share a 3D vertex move to their average UV.
static func weld_uvs(data, corner_set: Dictionary) -> void:
	var by_vertex := {}
	for key: Vector2i in _valid_corners(corner_set):
		var face := _manual_face(data, key.x)
		if face == null or key.y < 0 or key.y >= face.uv_coords.size():
			continue
		var vi: int = face.vertices[key.y]
		if not by_vertex.has(vi):
			by_vertex[vi] = []
		by_vertex[vi].append(key)
	for vi in by_vertex:
		var keys: Array = by_vertex[vi]
		if keys.size() < 2:
			continue
		var avg := Vector2.ZERO
		for key: Vector2i in keys:
			avg += data.faces[key.x].uv_coords[key.y]
		avg /= keys.size()
		for key: Vector2i in keys:
			var face: UBFace = data.faces[key.x]
			var coords := face.uv_coords
			coords[key.y] = avg
			face.uv_coords = coords


## Bounding rect of the set's manual UVs (Rect2() when the set has none).
static func uv_bounds(data, corner_set: Dictionary) -> Rect2:
	var has_any := false
	var rect := Rect2()
	for key: Vector2i in _valid_corners(corner_set):
		var face := _manual_face(data, key.x)
		if face == null or key.y < 0 or key.y >= face.uv_coords.size():
			continue
		var uv: Vector2 = face.uv_coords[key.y]
		if has_any:
			rect = rect.expand(uv)
		else:
			rect = Rect2(uv, Vector2.ZERO)
			has_any = true
	return rect


## Which extent fit_to_unit brings to exactly 1.
enum FitAxis { BOTH, U, V }


## Scales the set uniformly and moves its minimum corner to the origin.
static func fit_to_unit(data, face_set: Dictionary, axis: FitAxis = FitAxis.BOTH) -> void:
	var corner_set := corners_of(data, face_set)
	var rect := uv_bounds(data, corner_set)
	var extent := maxf(rect.size.x, rect.size.y)
	if axis == FitAxis.U:
		extent = rect.size.x
	elif axis == FitAxis.V:
		extent = rect.size.y
	var s := 1.0 / extent if extent > 1e-9 else 1.0
	transform_uvs(data, corner_set,
		Transform2D(0.0, Vector2(s, s), 0.0, -rect.position * s))


## The smallest translation that puts `rect` inside the unit square.
static func unit_lock_offset(rect: Rect2) -> Vector2:
	return Vector2(
		_unit_lock_axis(rect.position.x, rect.end.x),
		_unit_lock_axis(rect.position.y, rect.end.y))


static func _unit_lock_axis(lo: float, hi: float) -> float:
	var a := -lo
	var b := 1.0 - hi
	return clampf(0.0, minf(a, b), maxf(a, b))


## Scale factors capped so an island of `size` stays within the unit square.
static func unit_lock_factors(size: Vector2, factors: Vector2, uniform: bool) -> Vector2:
	var k := Vector2.ONE
	for a in 2:
		var grown := absf(size[a] * factors[a])
		var limit := maxf(1.0, size[a])
		if grown > limit and grown > 1e-12:
			k[a] = limit / grown
	if uniform:
		var m := minf(k.x, k.y)
		k = Vector2(m, m)
	return factors * k


## Faces in the same UV island as seed_face.
static func island_faces(data, seed_face: int, eps := 1e-5) -> Dictionary:
	if _manual_face(data, seed_face) == null:
		return {seed_face: true} if seed_face >= 0 and seed_face < data.faces.size() else {}

	var by_vertex := {}
	for fi in data.faces.size():
		var face := _manual_face(data, fi)
		if face == null:
			continue
		for ci in face.vertices.size():
			var vi: int = face.vertices[ci]
			if not by_vertex.has(vi):
				by_vertex[vi] = []
			by_vertex[vi].append([fi, face.uv_coords[ci]])
	var out := {seed_face: true}
	var queue: Array[int] = [seed_face]
	while not queue.is_empty():
		var fi: int = queue.pop_back()
		var face: UBFace = data.faces[fi]
		for ci in face.vertices.size():
			var uv: Vector2 = face.uv_coords[ci]
			for entry in by_vertex.get(face.vertices[ci], []):
				var nf: int = entry[0]
				if out.has(nf):
					continue
				if (entry[1] as Vector2).distance_to(uv) <= eps:
					out[nf] = true
					queue.append(nf)
	return out


## Copies UVs onto every same-arity target face; returns the count applied.
static func copy_uvs(data, coords: PackedVector2Array, to_faces: Dictionary) -> int:
	var applied := 0
	for fi in UBOpUtils.valid_faces(data, to_faces):
		var face: UBFace = data.faces[fi]
		if face.vertices.size() != coords.size():
			continue
		face.uv_coords = coords.duplicate()
		face.uv_manual = true
		applied += 1
	return applied


## Area of a face after `world_transform`, the node's global transform.
static func face_world_area(data, fi: int, world_transform := Transform3D.IDENTITY) -> float:
	var pts := PackedVector3Array()
	for vi in data.faces[fi].vertices:
		pts.append(world_transform * data.positions[vi])
	return UBTriangulate.newell_normal(pts).length() * 0.5


## UV-space area of a manual face (shoelace).
static func face_uv_area(data, fi: int) -> float:
	var face := _manual_face(data, fi)
	if face == null:
		return 0.0
	var area := 0.0
	var coords := face.uv_coords
	for i in coords.size():
		area += coords[i].cross(coords[(i + 1) % coords.size()])
	return absf(area) * 0.5


## Matches every touched island's texel density to the reference face.
static func texel_normalize(data, face_set: Dictionary, reference_face: int,
		world_transform := Transform3D.IDENTITY) -> void:
	if reference_face < 0 or reference_face >= data.faces.size():
		return
	face_set = UBOpUtils.valid_faces(data, face_set)
	var ref_world := face_world_area(data, reference_face, world_transform)
	var ref_uv := face_uv_area(data, reference_face)
	if ref_world <= 1e-12 or ref_uv <= 1e-12:
		return
	var ref_density := sqrt(ref_uv / ref_world)
	var done := {}
	for fi in face_set:
		if done.has(fi) or _manual_face(data, fi) == null:
			continue
		var island := island_faces(data, fi)
		var world := 0.0
		var uv := 0.0
		for isle_fi in island:
			done[isle_fi] = true
			world += face_world_area(data, isle_fi, world_transform)
			uv += face_uv_area(data, isle_fi)
		if world <= 1e-12 or uv <= 1e-12:
			continue
		var s := ref_density / sqrt(uv / world)
		if is_equal_approx(s, 1.0):
			continue
		var corners := corners_of(data, island)
		var pivot := uv_bounds(data, corners).get_center()
		transform_uvs(data, corners, Transform2D(0.0, pivot)
			* Transform2D(0.0, Vector2(s, s), 0.0, Vector2.ZERO)
			* Transform2D(0.0, -pivot))


## Dot-product margin under which two start projection axes count as the same.
const TILT_EPS := 1e-5


## Corner travel spread along the start normal, times coordinate scale, that counts as a tilt.
const PLANE_EPS := 1e-5


## Dot-product floor for a rigid face to follow its neighbours' fixed axis.
const FOLLOW_DOT := 0.70710678


## Drag start state for every face touching any vertex in `verts`.
static func drag_uv_frames(data, verts: Dictionary, positions: PackedVector3Array) -> Dictionary:
	var out := {}
	for fi in data.faces.size():
		var face: UBFace = data.faces[fi]
		var touched := false
		for vi in face.vertices:
			if verts.has(vi):
				touched = true
				break
		if not touched:
			continue
		var corners := _corners_from(face, positions)

		var normal := -UBTriangulate.newell_normal(corners)
		if normal.length_squared() <= 0.0:
			continue
		if _manual_face(data, fi) == null:
			var unit := normal.normalized()
			out[fi] = {
				"normal": unit, "axis": face.uv_axis, "dist": _pair_distances(corners),
				"lift": _lifts(corners, unit),
			}
			continue
		var frame := UBUVFrame.fit(corners, face.uv_coords, normal)
		if frame == null:
			continue
		out[fi] = {"frame": frame, "uvs": face.uv_coords.duplicate(), "dist": _pair_distances(corners)}
	link_drag_patches(data, out)
	return out


## Links each auto entry to its texture-continuous neighbours (`adj`).
static func link_drag_patches(data, frames: Dictionary) -> void:
	var by_edge := {}
	for fi in frames:
		var entry: Dictionary = frames[fi]
		if entry.has("frame"):
			continue
		entry["adj"] = []
		var loop: PackedInt32Array = data.faces[fi].vertices
		for i in loop.size():
			var a: int = loop[i]
			var b: int = loop[(i + 1) % loop.size()]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not by_edge.has(key):
				by_edge[key] = []
			by_edge[key].append(fi)
	for key in by_edge:
		var sharing: Array = by_edge[key]
		for i in sharing.size():
			for j in range(i + 1, sharing.size()):
				var ea: Dictionary = frames[sharing[i]]
				var eb: Dictionary = frames[sharing[j]]
				if _start_axis(ea).dot(_start_axis(eb)) >= 1.0 - TILT_EPS:
					ea.adj.append(sharing[j])
					eb.adj.append(sharing[i])


static func _start_axis(entry: Dictionary) -> Vector3:
	var axis: Vector3 = entry.axis
	return axis.normalized() if axis != Vector3.ZERO else entry.normal


## Refits the dragged faces' UVs against data.positions.
static func refit_drag_uvs(data, frames: Dictionary) -> void:

	var sources := []
	var rigid_tilted := {}
	for fi in frames:
		if fi < 0 or fi >= data.faces.size():
			continue
		var entry: Dictionary = frames[fi]
		var face: UBFace = data.faces[fi]
		var corners := _corners_from(face, data.positions)
		var rigid := _same_distances(_pair_distances(corners), entry.dist)
		if not entry.has("frame"):
			var axis: Vector3 = entry.axis
			if axis == Vector3.ZERO:
				if _tilted(entry, corners):
					if rigid:
						rigid_tilted[fi] = -UBTriangulate.newell_normal(corners).normalized()
					else:
						axis = entry.normal
			face.uv_axis = axis
			if axis != Vector3.ZERO:
				sources.append(fi)
			continue
		if _manual_face(data, fi) == null:
			continue
		if rigid:
			face.uv_coords = (entry.uvs as PackedVector2Array).duplicate()
			continue
		var frame: UBUVFrame = entry.frame
		var uvs := PackedVector2Array()
		uvs.resize(corners.size())
		for i in corners.size():
			uvs[i] = frame.uv_at(corners[i])
		face.uv_coords = uvs

	while not sources.is_empty() and not rigid_tilted.is_empty():
		var fi: int = sources.pop_back()
		for other in (frames[fi] as Dictionary).get("adj", []):
			if not rigid_tilted.has(other):
				continue
			var axis: Vector3 = data.faces[fi].uv_axis

			if (rigid_tilted[other] as Vector3).dot(axis.normalized()) < FOLLOW_DOT:
				continue
			rigid_tilted.erase(other)
			data.faces[other].uv_axis = axis
			sources.append(other)


## The framed faces' coords for the drag's undo entry.
static func drag_uv_coords(data, frames: Dictionary, start: bool) -> Dictionary:
	var out := {}
	for fi in frames:
		var entry: Dictionary = frames[fi]
		if not entry.has("frame"):
			continue
		if start:
			out[fi] = (entry.uvs as PackedVector2Array).duplicate()
		else:
			var face := _manual_face(data, fi)
			if face != null:
				out[fi] = face.uv_coords.duplicate()
	return out


## The auto faces' frozen projection axes for the drag's undo entry.
static func drag_uv_axes(data, frames: Dictionary, start: bool) -> Dictionary:
	var out := {}
	for fi in frames:
		var entry: Dictionary = frames[fi]
		if entry.has("frame") or fi < 0 or fi >= data.faces.size():
			continue
		var now: Vector3 = data.faces[fi].uv_axis
		if now == entry.axis:
			continue
		out[fi] = entry.axis if start else now
	return out


static func _lifts(corners: PackedVector3Array, normal: Vector3) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for p in corners:
		out.append(p.dot(normal))
	return out


static func _tilted(entry: Dictionary, corners: PackedVector3Array) -> bool:
	var start: PackedFloat64Array = entry.lift
	if start.size() != corners.size():
		return false
	var now := _lifts(corners, entry.normal)
	var low := INF
	var high := -INF
	var scale := 1.0
	for i in now.size():
		var travel := now[i] - start[i]
		low = minf(low, travel)
		high = maxf(high, travel)
		scale = maxf(scale, maxf(absf(corners[i].x), maxf(absf(corners[i].y), absf(corners[i].z))))
	return high - low > PLANE_EPS * scale


static func _corners_from(face: UBFace, positions: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for vi in face.vertices:
		out.append(positions[vi] if vi >= 0 and vi < positions.size() else Vector3.ZERO)
	return out


static func _pair_distances(corners: PackedVector3Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in corners.size():
		for j in range(i + 1, corners.size()):
			out.append(corners[i].distance_to(corners[j]))
	return out


static func _same_distances(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(a[i] - b[i]) > 1e-5 * maxf(1.0, b[i]):
			return false
	return true


static func _valid_corners(corner_set: Dictionary) -> Array:
	var out := []
	for key in corner_set:
		if key is Vector2i:
			out.append(key)
	return out


static func _manual_face(data, fi: int) -> UBFace:
	if fi < 0 or fi >= data.faces.size():
		return null
	var face: UBFace = data.faces[fi]
	if not face.uv_manual or face.uv_coords.size() != face.vertices.size():
		return null
	return face
