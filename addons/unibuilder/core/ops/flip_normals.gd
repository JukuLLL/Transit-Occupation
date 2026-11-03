@tool
class_name UBOpFlipNormals
extends RefCounted
## Reverses the winding of the given faces, or of every face for an empty set.


static func apply(data, face_set: Dictionary) -> void:
	var targets: Array = (
		UBOpUtils.valid_faces(data, face_set).keys() if not face_set.is_empty()
		else range(data.faces.size())
	)
	for fi in targets:
		UBOpUtils.reverse_face_loop(data.faces[fi])
