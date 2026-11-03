@tool
class_name UBOpDeleteFaces
extends RefCounted
## Deletes faces and compacts away any vertices left unused.


static func apply(data, face_set: Dictionary) -> void:
	if face_set.is_empty():
		return
	var keep: Array[UBFace] = []
	for fi in data.faces.size():
		if not face_set.has(fi):
			keep.append(data.faces[fi])
	data.faces = keep
	UBOpUtils.remove_unused_vertices(data)
