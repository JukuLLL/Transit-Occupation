@tool
class_name UBOpCollapseVertices
extends RefCounted
## Collapses the selected vertices into one at their center.


static func apply(data, vert_set: Dictionary) -> void:
	vert_set = UBOpUtils.valid_vertices(data, vert_set)
	if vert_set.size() < 2:
		return
	var indices: Array = vert_set.keys()
	indices.sort()
	var rep: int = indices[0]
	var target := Vector3.ZERO
	for vi in indices:
		target += data.positions[vi]
	target /= indices.size()
	var remap := PackedInt32Array()
	remap.resize(data.positions.size())
	for i in data.positions.size():
		remap[i] = i
	for vi in indices:
		remap[vi] = rep
	if UBOpUtils.remap_overshares(data, remap):
		return
	data.positions[rep] = target
	UBOpUtils.remap_faces(data, remap)
