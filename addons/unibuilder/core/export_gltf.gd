@tool
class_name UBExportGLTF
extends RefCounted
## Exports the compiled mesh and materials to .glb or .gltf.


## Exports one mesh to a glTF file.
static func export_file(data, object_name: String, path: String,
		world_transform: Transform3D = Transform3D.IDENTITY) -> Error:
	var mi := MeshInstance3D.new()
	mi.name = object_name if not object_name.is_empty() else "unibuilder"
	mi.mesh = UBMeshCompiler.compile(data, world_transform)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(mi, state)
	if err == OK:
		err = doc.write_to_filesystem(state, path)
	mi.free()
	return err


## Exports several meshes into one glTF scene.
static func export_nodes(entries: Array, path: String) -> Error:
	var root := Node3D.new()
	var base := path.get_file().get_basename()
	root.name = base if not base.is_empty() else "unibuilder"
	var count := 0
	for entry in entries:
		if not (entry is Dictionary) or entry.get("data") == null:
			continue
		var xf: Transform3D = entry.get("transform", Transform3D.IDENTITY)
		var mi := MeshInstance3D.new()
		var object_name := String(entry.get("name", ""))
		mi.name = object_name if not object_name.is_empty() else "mesh%d" % count
		mi.mesh = UBMeshCompiler.compile(entry["data"], xf)
		mi.transform = xf
		root.add_child(mi)

		mi.owner = root
		count += 1
	if count == 0:
		root.free()
		return ERR_INVALID_DATA
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, path)
	root.free()
	return err
