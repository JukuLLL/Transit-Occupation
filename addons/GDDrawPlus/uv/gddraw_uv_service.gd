@tool
class_name GDDrawUVService
extends RefCounted

## Unwraps the mesh of a MeshInstance3D and assigns the result back to it.
##
## The unwrapped mesh is saved as a NEW resource under res://gddraw/meshes and assigned
## through the editor undo history, so the original mesh (for example one embedded in an
## imported .glb) is never modified and the change can be undone. Skinning data travels
## with the vertices, see GDDrawUVMeshAdapter.

const STATUS := "status"
const MESSAGE := "message"
const STATUS_OK := "ok"
const STATUS_ERROR := "error"
const StoragePaths := preload("res://addons/GDDrawPlus/gddraw_storage_paths.gd")

const DEFAULT_MARGIN := 0.01


func can_unwrap(node: Node) -> bool:
	return node is MeshInstance3D and (node as MeshInstance3D).mesh != null


## Automatically unwraps every triangle surface of the node's mesh (chart-based, via xatlas),
## giving each surface its own 0-1 UV tile. Returns {status, message, mesh, path, ...}.
func unwrap_mesh_instance(
	mesh_instance: MeshInstance3D,
	editor_plugin: EditorPlugin = null,
	margin := DEFAULT_MARGIN,
	save_dir := StoragePaths.DEFAULT_MESH_DIR,
	method := GDDrawUVMeshAdapter.UnwrapMethod.SMART
) -> Dictionary:
	if not is_instance_valid(mesh_instance) or mesh_instance.mesh == null:
		return _result(STATUS_ERROR, "Select a MeshInstance3D with a mesh to unwrap.")
	var previous_mesh := mesh_instance.mesh
	var adapter := GDDrawUVMeshAdapter.from_mesh(previous_mesh)
	if adapter == null:
		return _result(STATUS_ERROR, "%s has no triangle geometry that can be unwrapped." % mesh_instance.name)
	var unwrapped := adapter.unwrap(method, margin)
	if unwrapped == null:
		return _result(STATUS_ERROR, "Unwrapping %s failed." % mesh_instance.name)
	return finalize_unwrap(mesh_instance, adapter, adapter.build_mesh(unwrapped), editor_plugin, save_dir)


## Second half of unwrap_mesh_instance(), split out so the heavy part (auto_unwrap_xatlas and
## build_mesh) can run on a worker thread while saving and assigning stay on the main thread.
func finalize_unwrap(
	mesh_instance: MeshInstance3D,
	adapter: GDDrawUVMeshAdapter,
	new_mesh: ArrayMesh,
	editor_plugin: EditorPlugin = null,
	save_dir := StoragePaths.DEFAULT_MESH_DIR,
	action_name := "Auto-Unwrap UVs"
) -> Dictionary:
	if new_mesh == null:
		return _result(STATUS_ERROR, "Unwrapping %s failed." % (mesh_instance.name if is_instance_valid(mesh_instance) else "the mesh"))
	var result := commit_mesh(mesh_instance, new_mesh, editor_plugin, save_dir, action_name)
	if str(result.get(STATUS)) == STATUS_OK and adapter and not adapter.xatlas_fallback_surfaces.is_empty():
		result[MESSAGE] = str(result[MESSAGE]) + " %d surface(s) could not be unwrapped automatically and used angle-based cuts instead; check them in the UV editor." % adapter.xatlas_fallback_surfaces.size()
	return result


## Triangle count of all triangle surfaces, used to warn before slow unwraps.
static func count_triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for surface_index in range(mesh.get_surface_count()):
		var index_count := 0
		var vertex_count := 0
		if mesh is ArrayMesh:
			index_count = mesh.surface_get_array_index_len(surface_index)
			vertex_count = mesh.surface_get_array_len(surface_index)
		else:
			# Built-in shapes (CylinderMesh, SphereMesh, ...) only expose their arrays.
			var arrays := mesh.surface_get_arrays(surface_index)
			if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
				index_count = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
			if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				vertex_count = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		total += (index_count if index_count > 0 else vertex_count) / 3
	return total


## Rough xatlas duration in seconds for a mesh of `triangles`, measured on a desktop CPU:
## about 1 s at 12k triangles, growing faster than linearly on dense meshes.
static func estimate_unwrap_seconds(triangles: int) -> float:
	return 0.9 * pow(float(maxi(triangles, 1)) / 12600.0, 2.2)


## Saves `new_mesh` as a new resource and assigns it to the node (undoable in the editor).
func commit_mesh(
	mesh_instance: MeshInstance3D,
	new_mesh: ArrayMesh,
	editor_plugin: EditorPlugin,
	save_dir := StoragePaths.DEFAULT_MESH_DIR,
	action_name := "Edit UVs"
) -> Dictionary:
	if not is_instance_valid(mesh_instance) or new_mesh == null:
		return _result(STATUS_ERROR, "There is no mesh to save.")
	var previous_mesh := mesh_instance.mesh
	if not StoragePaths.is_writable_project_path(save_dir):
		return _result(STATUS_ERROR, "%s is not a writable project folder." % save_dir)
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(StoragePaths.normalize_path(save_dir)))
	if dir_error != OK:
		return _result(STATUS_ERROR, "Could not create %s (error %d)." % [save_dir, dir_error])
	var path := _make_unique_path(save_dir, str(mesh_instance.name))
	new_mesh.resource_name = path.get_file().get_basename()
	var save_error := ResourceSaver.save(new_mesh, path)
	if save_error != OK:
		return _result(STATUS_ERROR, "Could not save %s (error %d)." % [path, save_error])
	# Bind the in-memory mesh to the file, otherwise the scene would embed a copy of it
	# instead of referencing the saved resource. (FLAG_CHANGE_PATH does not do this.)
	new_mesh.take_over_path(path)
	if editor_plugin:
		editor_plugin.get_editor_interface().get_resource_filesystem().scan()

	var undo_redo := editor_plugin.get_undo_redo() if editor_plugin else null
	if undo_redo:
		undo_redo.create_action(action_name)
		undo_redo.add_do_property(mesh_instance, "mesh", new_mesh)
		undo_redo.add_undo_property(mesh_instance, "mesh", previous_mesh)
		undo_redo.commit_action()
	else:
		mesh_instance.mesh = new_mesh
	# Instanced or inherited scene nodes do not always take the property change
	# synchronously; apply it directly the same way GDDraw's material assignment does.
	if mesh_instance.mesh != new_mesh:
		mesh_instance.mesh = new_mesh
	if mesh_instance.mesh != new_mesh:
		return {
			STATUS: STATUS_ERROR,
			MESSAGE: "Saved %s, but %s would not accept the new mesh." % [path, mesh_instance.name],
			"path": path,
		}
	return {
		STATUS: STATUS_OK,
		MESSAGE: "Saved %s and assigned it to %s." % [path, mesh_instance.name],
		"mesh": new_mesh,
		"previous_mesh": previous_mesh,
		"path": path,
	}


func _make_unique_path(dir_path: String, source_name: String) -> String:
	var safe_name := source_name.to_snake_case().validate_filename()
	if safe_name.is_empty():
		safe_name = "mesh"
	var base := dir_path.trim_suffix("/")
	for index in range(1, 1000):
		var suffix := "" if index == 1 else "_%03d" % index
		var candidate := "%s/%s_uv%s.res" % [base, safe_name, suffix]
		if not FileAccess.file_exists(candidate):
			return candidate
	return "%s/%s_uv_%d.res" % [base, safe_name, Time.get_unix_time_from_system()]


func _result(status: String, message: String) -> Dictionary:
	return {STATUS: status, MESSAGE: message}
