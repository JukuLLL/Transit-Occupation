@tool
class_name UBVertexSnap
extends RefCounted
## Vertex snapping (hold V during a move drag) onto the vertex nearest the cursor.


## Cursor-to-target screen distance that arms a snap, in pixels.
const SNAP_PX := 22.0


## World-space candidates from one mesh: every vertex not in `exclude`, through `xf`.
static func collect_targets(data, xf: Transform3D, exclude: Dictionary) -> PackedVector3Array:
	return collect_positions(data.positions, xf, exclude)


## collect_targets over a bare positions array.
static func collect_positions(positions: PackedVector3Array, xf: Transform3D,
		exclude: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	for vi in positions.size():
		if not exclude.has(vi):
			out.append(xf * positions[vi])
	return out


## Appends every UBMeshInstance3D vertex under `root` except `skip`'s, in world space.
static func collect_scene_targets(root: Node, skip: Node, out: PackedVector3Array) -> void:
	if root is UBMeshInstance3D and root != skip and root.mesh_data != null:
		var xf: Transform3D = root.global_transform
		for p in root.mesh_data.positions:
			out.append(xf * p)
	for child in root.get_children():
		collect_scene_targets(child, skip, out)


## Index of the target projecting nearest `cursor` within `max_px`, or -1.
static func nearest_target(
	targets: PackedVector3Array, project: Callable, cursor: Vector2, max_px: float
) -> int:
	var best := -1
	var best_d := max_px
	for i in targets.size():
		var sp: Variant = project.call(targets[i])
		if sp == null:
			continue
		var d: float = (sp as Vector2).distance_to(cursor)
		if d < best_d:
			best_d = d
			best = i
	return best
