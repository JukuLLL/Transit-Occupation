@tool
class_name UBOpBoolean
extends RefCounted
## Union, intersect, or subtract two meshes, keeping the result editable.


const UNION := CSGShape3D.OPERATION_UNION
const INTERSECT := CSGShape3D.OPERATION_INTERSECTION
const SUBTRACT := CSGShape3D.OPERATION_SUBTRACTION


## Returns the edges that break manifoldness.
static func manifold_errors(data) -> Array[Vector2i]:
	var topo := UBTopology.build(data)
	var directed := {}
	for f in data.faces:
		var verts: PackedInt32Array = f.vertices
		for i in verts.size():
			var key := Vector2i(verts[i], verts[(i + 1) % verts.size()])
			directed[key] = directed.get(key, 0) + 1
	var bad: Array[Vector2i] = []
	for e: Vector2i in topo.edge_faces:
		if topo.edge_faces[e].size() != 2:
			bad.append(e)
		elif directed.get(Vector2i(e.x, e.y), 0) != 1 or directed.get(Vector2i(e.y, e.x), 0) != 1:
			bad.append(e)
	return bad


## Boolean of two meshes in A's local space, `b_relative_to_a` placing B. Await it.
static func apply(parent: Node, a_data, b_data, b_relative_to_a: Transform3D, operation: int) -> UBMeshData:
	if parent == null:
		return null

	var root := CSGMesh3D.new()
	root.mesh = UBMeshCompiler.compile(a_data)
	var child := CSGMesh3D.new()
	child.operation = operation
	child.mesh = UBMeshCompiler.compile(b_data)
	child.transform = b_relative_to_a
	root.add_child(child)
	parent.add_child(root)

	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var baked: ArrayMesh = root.bake_static_mesh()
	if baked == null or baked.get_surface_count() == 0:

		await tree.process_frame
		baked = root.bake_static_mesh()
	parent.remove_child(root)
	root.free()
	if baked == null or baked.get_surface_count() == 0:
		return null
	return UBConvertMesh.from_mesh(baked, true)
