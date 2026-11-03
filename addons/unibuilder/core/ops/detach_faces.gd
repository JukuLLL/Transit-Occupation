@tool
class_name UBOpDetachFaces
extends RefCounted
## Removes the selected faces and returns them as a new UBMeshData.


static func apply(data, face_set: Dictionary) -> UBMeshData:
	face_set = UBOpUtils.valid_faces(data, face_set)
	var out := UBMeshData.new()
	out.material_slots = data.material_slots.duplicate()
	var indices: Array = face_set.keys()
	indices.sort()
	var map := {}
	for fi in indices:
		var face: UBFace = data.faces[fi]
		var copy: UBFace = face.duplicate_face()
		var verts := PackedInt32Array()
		for vi in face.vertices:
			if not map.has(vi):
				map[vi] = out.add_vertex(data.positions[vi])
			verts.append(map[vi])
		copy.vertices = verts
		out.faces.append(copy)
	UBOpDeleteFaces.apply(data, face_set)
	return out
