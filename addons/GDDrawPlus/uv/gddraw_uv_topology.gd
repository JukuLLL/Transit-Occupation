@tool
# Derived from Gator Model Studio (c) 2026 Blackwater Gator Studios, MIT License.
# See LICENSE-GatorModelStudio.txt. Modified for GDDraw: renamed classes, mesh-rebuild code removed,
# host hooks added to the editor window.
class_name GDDrawUVTopology
extends RefCounted





var mesh: GDDrawUVMeshData
var half_edge_origin: PackedInt32Array = PackedInt32Array()
var half_edge_destination: PackedInt32Array = PackedInt32Array()
var half_edge_face: PackedInt32Array = PackedInt32Array()
var half_edge_next: PackedInt32Array = PackedInt32Array()
var half_edge_previous: PackedInt32Array = PackedInt32Array()
var half_edge_twin: PackedInt32Array = PackedInt32Array()
var face_half_edge: PackedInt32Array = PackedInt32Array()
var vertex_half_edges: Array[PackedInt32Array] = []
var vertex_faces: Array[PackedInt32Array] = []
var vertex_neighbors: Array[PackedInt32Array] = []
var edge_half_edges: Dictionary = {}
var non_manifold_edges: Array[Vector2i] = []


func _init(source: GDDrawUVMeshData = null) -> void:
	if source != null:
		build(source)


func build(source: GDDrawUVMeshData) -> void:
	mesh = source
	half_edge_origin.clear()
	half_edge_destination.clear()
	half_edge_face.clear()
	half_edge_next.clear()
	half_edge_previous.clear()
	half_edge_twin.clear()
	face_half_edge.clear()
	vertex_half_edges.clear()
	vertex_faces.clear()
	vertex_neighbors.clear()
	edge_half_edges.clear()
	non_manifold_edges.clear()
	if mesh == null:
		return

	vertex_half_edges.resize(mesh.vertices.size())
	vertex_faces.resize(mesh.vertices.size())
	vertex_neighbors.resize(mesh.vertices.size())
	for vertex_index: int in vertex_half_edges.size():
		vertex_half_edges[vertex_index] = PackedInt32Array()
		vertex_faces[vertex_index] = PackedInt32Array()
		vertex_neighbors[vertex_index] = PackedInt32Array()
	face_half_edge.resize(mesh.faces.size())
	face_half_edge.fill(-1)

	for face_index: int in mesh.faces.size():
		var face: PackedInt32Array = mesh.faces[face_index]
		if face.size() < 3:
			continue
		var first_half_edge: int = half_edge_origin.size()
		face_half_edge[face_index] = first_half_edge
		for corner_index: int in face.size():
			var origin: int = face[corner_index]
			var destination: int = face[(corner_index + 1) % face.size()]
			var half_edge_index: int = half_edge_origin.size()
			half_edge_origin.append(origin)
			half_edge_destination.append(destination)
			half_edge_face.append(face_index)
			half_edge_next.append(first_half_edge + (corner_index + 1) % face.size())
			half_edge_previous.append(
				first_half_edge + (corner_index - 1 + face.size()) % face.size()
			)
			half_edge_twin.append(-1)
			if origin >= 0 and origin < vertex_half_edges.size():
				vertex_half_edges[origin].append(half_edge_index)
				if not vertex_faces[origin].has(face_index):
					vertex_faces[origin].append(face_index)
				if destination >= 0 and destination < vertex_neighbors.size() and not vertex_neighbors[origin].has(destination):
					vertex_neighbors[origin].append(destination)
			if destination >= 0 and destination < vertex_faces.size():
				if not vertex_faces[destination].has(face_index):
					vertex_faces[destination].append(face_index)
				if origin >= 0 and origin < vertex_neighbors.size() and not vertex_neighbors[destination].has(origin):
					vertex_neighbors[destination].append(origin)
			var edge: Vector2i = GDDrawUVMeshData.canonical_edge(origin, destination)
			var attached: PackedInt32Array = edge_half_edges.get(edge, PackedInt32Array())
			attached.append(half_edge_index)
			edge_half_edges[edge] = attached

	for edge_value: Variant in edge_half_edges.keys():
		var edge: Vector2i = edge_value
		var attached: PackedInt32Array = edge_half_edges[edge]
		if attached.size() == 2:
			half_edge_twin[attached[0]] = attached[1]
			half_edge_twin[attached[1]] = attached[0]
		elif attached.size() > 2:
			non_manifold_edges.append(edge)

	for loose_edge: Vector2i in mesh.loose_edges:
		if loose_edge.x >= 0 and loose_edge.x < vertex_neighbors.size() and loose_edge.y >= 0 and loose_edge.y < vertex_neighbors.size():
			if not vertex_neighbors[loose_edge.x].has(loose_edge.y):
				vertex_neighbors[loose_edge.x].append(loose_edge.y)
			if not vertex_neighbors[loose_edge.y].has(loose_edge.x):
				vertex_neighbors[loose_edge.y].append(loose_edge.x)


func is_manifold() -> bool:
	return non_manifold_edges.is_empty()


func get_edge_faces(edge: Vector2i) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	var key: Vector2i = GDDrawUVMeshData.canonical_edge(edge.x, edge.y)
	var attached: PackedInt32Array = edge_half_edges.get(key, PackedInt32Array())
	for half_edge_index: int in attached:
		var face_index: int = half_edge_face[half_edge_index]
		if face_index >= 0 and not result.has(face_index):
			result.append(face_index)
	return result


func get_vertex_faces(vertex_index: int) -> PackedInt32Array:
	if vertex_index < 0 or vertex_index >= vertex_faces.size():
		return PackedInt32Array()
	return vertex_faces[vertex_index]


func get_vertex_neighbors(vertex_index: int) -> PackedInt32Array:
	if vertex_index < 0 or vertex_index >= vertex_neighbors.size():
		return PackedInt32Array()
	return vertex_neighbors[vertex_index]


func get_boundary_edges() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for edge_value: Variant in edge_half_edges.keys():
		var edge: Vector2i = edge_value
		var attached: PackedInt32Array = edge_half_edges[edge]
		if attached.size() == 1:
			result.append(edge)
	return result


func get_boundary_loops() -> Array[PackedInt32Array]:
	var outgoing: Dictionary = {}
	for edge_value: Variant in edge_half_edges.keys():
		var edge: Vector2i = edge_value
		var attached: PackedInt32Array = edge_half_edges[edge]
		if attached.size() != 1:
			continue
		var half_edge_index: int = attached[0]

		var origin: int = half_edge_destination[half_edge_index]
		var destination: int = half_edge_origin[half_edge_index]
		var values: PackedInt32Array = outgoing.get(origin, PackedInt32Array())
		values.append(destination)
		outgoing[origin] = values

	var remaining: Dictionary = {}
	for origin_value: Variant in outgoing.keys():
		var origin: int = int(origin_value)
		for destination: int in outgoing[origin]:
			remaining[Vector2i(origin, destination)] = true

	var loops: Array[PackedInt32Array] = []
	while not remaining.is_empty():
		var first_value: Variant = remaining.keys()[0]
		var first: Vector2i = first_value
		remaining.erase(first)
		var loop: PackedInt32Array = PackedInt32Array([first.x, first.y])
		var current: int = first.y
		var closed: bool = false
		while current != first.x:
			var candidates: PackedInt32Array = outgoing.get(current, PackedInt32Array())
			var next_vertex: int = -1
			for candidate: int in candidates:
				var key: Vector2i = Vector2i(current, candidate)
				if remaining.has(key):
					next_vertex = candidate
					remaining.erase(key)
					break
			if next_vertex < 0:
				break
			if next_vertex == first.x:
				closed = true
				break
			loop.append(next_vertex)
			current = next_vertex
		if closed and loop.size() >= 3:
			loops.append(loop)
	return loops
