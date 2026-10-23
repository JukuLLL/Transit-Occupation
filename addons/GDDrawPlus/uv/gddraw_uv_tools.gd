@tool
class_name GDDrawUVTools
extends Node

## UI controller for GDDraw's UV tools. The dock hosts one button and forwards it here;
## this node owns the dialogs and reports back through `unwrap_finished`.

signal unwrap_finished(result: Dictionary, mesh_instance: MeshInstance3D)

const DEFAULT_MARGIN := 0.01

var _plugin: EditorPlugin
var _service := GDDrawUVService.new()
var _unwrap_dialog: ConfirmationDialog
var _unwrap_target_label: Label
var _unwrap_session_warning: Label
var _margin_spin: SpinBox
var _pending_target: MeshInstance3D

# Full UV editor state. The editor works on an in-memory GDDrawUVMeshData; nothing touches
# the scene until "Apply to Mesh", which saves a new mesh file and assigns it (undoable).
var _editor_window: GDDrawUVEditorWindow
var _editor_target: MeshInstance3D
var _editor_adapter: GDDrawUVMeshAdapter
var _editor_history: Array[GDDrawUVMeshData] = []
var _editor_history_index := -1
var _editor_saved_index := -1
var _editor_active_material := 0
var _close_dialog: ConfirmationDialog
var _unwrap_size_label: Label
var _method_option: OptionButton
var _method_description: Label
var _pending_triangles := 0

# Single background job at a time: xatlas can take a minute on dense meshes, so the heavy
# step runs on a worker thread while a small dialog tells the user what is happening.
var _bg_task_id := -1
var _bg_holder := {}
var _bg_done := Callable()
var _busy_dialog: AcceptDialog
var _busy_label: Label


func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin
	set_process(false)


func is_busy() -> bool:
	return _bg_task_id >= 0


func _exit_tree() -> void:
	# Never leave a worker running against objects that are being freed.
	if _bg_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_bg_task_id)
		_bg_task_id = -1


func _process(_delta: float) -> void:
	if _bg_task_id < 0:
		set_process(false)
		return
	if not WorkerThreadPool.is_task_completed(_bg_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_bg_task_id)
	_bg_task_id = -1
	set_process(false)
	if _busy_dialog:
		_busy_dialog.hide()
	var done := _bg_done
	_bg_done = Callable()
	if done.is_valid():
		done.call(_bg_holder.get("result"))


## Runs `worker` on a worker thread and calls `done(result)` on the main thread afterwards.
## Returns false (and does nothing) when another job is still running.
func _run_in_background(title_text: String, detail: String, worker: Callable, done: Callable) -> bool:
	if is_busy():
		return false
	if not _busy_dialog:
		_busy_dialog = AcceptDialog.new()
		_busy_dialog.exclusive = true
		_busy_dialog.unresizable = true
		_busy_dialog.min_size = Vector2i(420, 110)
		_busy_dialog.get_ok_button().hide()
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		_busy_label = Label.new()
		_busy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_busy_label.custom_minimum_size.x = 380.0
		box.add_child(_busy_label)
		var bar := ProgressBar.new()
		bar.indeterminate = true
		bar.custom_minimum_size.y = 18.0
		box.add_child(bar)
		_busy_dialog.add_child(box)
		add_child(_busy_dialog)
	_busy_dialog.title = title_text
	_busy_label.text = detail
	_busy_dialog.popup_centered(Vector2i(420, 110))
	_bg_holder = {}
	_bg_done = done
	var holder := _bg_holder
	_bg_task_id = WorkerThreadPool.add_task(func() -> void: holder["result"] = worker.call(), false, title_text)
	set_process(true)
	return true


## Shows the auto-unwrap confirmation for `mesh_instance`. `paint_session_active` adds a
## warning that pixels already painted will not follow the new UV layout.
func request_unwrap(mesh_instance: MeshInstance3D, paint_session_active := false) -> void:
	if not is_instance_valid(mesh_instance) or mesh_instance.mesh == null:
		unwrap_finished.emit(
			{"status": "error", "message": "Select a MeshInstance3D with a mesh to unwrap."},
			null
		)
		return
	if is_busy():
		unwrap_finished.emit({"status": "error", "message": "A UV operation is still running; wait for it to finish."}, null)
		return
	_ensure_unwrap_dialog()
	_pending_target = mesh_instance
	_unwrap_target_label.text = "Target: %s" % mesh_instance.name
	_pending_triangles = GDDrawUVService.count_triangles(mesh_instance.mesh)
	_on_unwrap_method_selected(_method_option.selected)
	_unwrap_session_warning.visible = paint_session_active
	_unwrap_dialog.popup_centered(Vector2i(520, 380))


## Refreshes the method description and the time estimate (only the Smart method is slow).
func _on_unwrap_method_selected(index: int) -> void:
	var method := _method_option.get_item_id(index)
	_method_description.text = _method_option.get_item_tooltip(index)
	var text := "%s triangles" % format_count(_pending_triangles)
	var seconds := GDDrawUVService.estimate_unwrap_seconds(_pending_triangles)
	if method == GDDrawUVMeshAdapter.UnwrapMethod.SMART and seconds >= 5.0:
		text += " — dense mesh: Smart can take about %s (the editor stays responsive). Simple methods are instant." % _format_duration(seconds)
	_unwrap_size_label.text = text


static func format_count(value: int) -> String:
	return "%.1fk" % (value / 1000.0) if value >= 10000 else str(value)


static func _format_duration(seconds: float) -> String:
	if seconds < 90.0:
		return "%d seconds" % (int(seconds / 5.0) * 5 + 5)
	return "%d minutes" % ceili(seconds / 60.0)


## Opens the full UV editor for `mesh_instance`.
func open_editor(mesh_instance: MeshInstance3D) -> void:
	if not is_instance_valid(mesh_instance) or mesh_instance.mesh == null:
		unwrap_finished.emit({"status": "error", "message": "Select a MeshInstance3D with a mesh to edit its UVs."}, null)
		return
	if _editor_window and _editor_window.visible and _editor_window.is_dirty() and _editor_target != mesh_instance:
		unwrap_finished.emit(
			{"status": "error", "message": "The UV editor has unapplied edits for %s. Apply or discard them first." % _editor_target.name},
			null
		)
		_editor_window.open_editor()
		return
	if _editor_window and _editor_window.visible and _editor_target == mesh_instance:
		_editor_window.open_editor()
		return
	var adapter := GDDrawUVMeshAdapter.from_mesh(mesh_instance.mesh)
	if adapter == null:
		unwrap_finished.emit({"status": "error", "message": "%s has no triangle geometry the UV editor can use." % mesh_instance.name}, null)
		return
	_ensure_editor_window()
	_editor_target = mesh_instance
	_editor_active_material = 0
	_reset_editor_history(adapter)
	_refresh_editor()
	_editor_window.open_editor()


func _ensure_editor_window() -> void:
	if _editor_window:
		return
	_editor_window = GDDrawUVEditorWindow.new()
	_editor_window.mesh_commit_requested.connect(_on_editor_commit)
	_editor_window.active_material_changed.connect(func(index: int) -> void: _editor_active_material = index)
	_editor_window.apply_requested.connect(_on_editor_apply_requested)
	_editor_window.undo_requested.connect(_on_editor_undo_requested)
	_editor_window.redo_requested.connect(_on_editor_redo_requested)
	_editor_window.auto_unwrap_requested.connect(_on_editor_auto_unwrap_requested)
	_editor_window.close_guard = _can_close_editor
	add_child(_editor_window)


func _reset_editor_history(adapter: GDDrawUVMeshAdapter) -> void:
	_editor_adapter = adapter
	_editor_history.clear()
	_editor_history.push_back(adapter.data)
	_editor_history_index = 0
	_editor_saved_index = 0


func _editor_is_dirty() -> bool:
	return _editor_history_index != _editor_saved_index


func _refresh_editor() -> void:
	if not _editor_window or _editor_history_index < 0:
		return
	var names := PackedStringArray()
	var textures: Array[Texture2D] = []
	for surface_index in range(_editor_adapter.get_surface_count()):
		names.push_back(_editor_adapter.get_surface_name(surface_index))
		var texture: Texture2D = null
		if is_instance_valid(_editor_target):
			var material := _editor_target.get_active_material(surface_index) as StandardMaterial3D
			if material:
				texture = material.albedo_texture
		textures.push_back(texture)
	_editor_window.set_data(_editor_history[_editor_history_index], textures, names, _editor_active_material)
	_editor_window.set_document_state(
		str(_editor_target.name) if is_instance_valid(_editor_target) else "mesh",
		_editor_is_dirty(),
		_editor_history_index > 0,
		_editor_history_index < _editor_history.size() - 1
	)


func _on_editor_commit(new_data: GDDrawUVMeshData, action_name: String) -> void:
	# A new edit discards the redo branch, exactly like a normal undo stack.
	_editor_history.resize(_editor_history_index + 1)
	if _editor_saved_index > _editor_history_index:
		_editor_saved_index = -1
	_editor_history.push_back(new_data)
	_editor_history_index += 1
	_refresh_editor()
	_editor_window.set_status_text("%s applied. Undo with Ctrl+Z; changes reach the mesh when you press Apply to Mesh." % action_name)


func _on_editor_auto_unwrap_requested(material_index: int, margin: float, method: int) -> void:
	if _editor_history_index < 0:
		return
	var adapter := _editor_adapter
	var base := _editor_history[_editor_history_index]
	var surfaces := PackedInt32Array([material_index])
	var started_at := _editor_history_index
	var started_size := _editor_history.size()
	var method_label := GDDrawUVMeshAdapter.get_method_label(method)
	var started := _run_in_background(
		"Auto Unwrap",
		"Unwrapping the active material (%s). Large meshes can take a while with the Smart method." % method_label,
		func() -> Variant: return adapter.unwrap(method, margin, base, surfaces),
		func(result: Variant) -> void:
			if result == null:
				_editor_window.set_status_text("Auto Unwrap failed.")
			elif adapter != _editor_adapter or started_at != _editor_history_index or started_size != _editor_history.size():
				# The editor state moved on while xatlas was running; applying would corrupt it.
				_editor_window.set_status_text("Auto Unwrap result discarded because the UVs changed while it was running.")
			else:
				_on_editor_commit(result as GDDrawUVMeshData, "Auto Unwrap (%s)" % method_label)
				if not adapter.xatlas_fallback_surfaces.is_empty():
					_editor_window.set_status_text("Auto Unwrap could not process this material automatically and used angle-based cuts instead.")
	)
	if not started:
		_editor_window.set_status_text("Another UV operation is still running.")


func _on_editor_undo_requested() -> void:
	if _editor_history_index > 0:
		_editor_history_index -= 1
		_refresh_editor()


func _on_editor_redo_requested() -> void:
	if _editor_history_index < _editor_history.size() - 1:
		_editor_history_index += 1
		_refresh_editor()


func _on_editor_apply_requested() -> void:
	_apply_editor(false)


## Saves the edited UVs as a new mesh and assigns it. Returns true on success.
func _apply_editor(close_afterwards: bool) -> bool:
	if not _editor_is_dirty():
		return true
	if not is_instance_valid(_editor_target):
		_editor_window.set_status_text("The target node was removed from the scene; nothing to apply to.")
		return false
	var new_mesh := _editor_adapter.build_mesh(_editor_history[_editor_history_index])
	var result := _service.commit_mesh(_editor_target, new_mesh, _plugin, GDDrawStoragePaths.DEFAULT_MESH_DIR, "Edit UVs")
	if str(result.get("status", "error")) != "ok":
		_editor_window.set_status_text(str(result.get("message", "Could not apply the UV edits.")))
		unwrap_finished.emit(result, _editor_target)
		return false
	# Re-import from the mesh that was just saved: its vertices were split along the new
	# seams, so the editor's indices must be rebuilt against it. The editor's own undo
	# history restarts here; Ctrl+Z in the scene reverts the mesh assignment itself.
	var adapter := GDDrawUVMeshAdapter.from_mesh(result["mesh"])
	if adapter:
		_reset_editor_history(adapter)
	unwrap_finished.emit(result, _editor_target)
	if close_afterwards:
		_editor_window.force_close()
	else:
		_refresh_editor()
		_editor_window.set_status_text(str(result.get("message", "Applied.")) + " The editor's own undo history restarted; Ctrl+Z in the scene reverts the mesh.")
	return true


## Close guard for the editor window: unapplied edits ask what to do first.
func _can_close_editor() -> bool:
	if not _editor_is_dirty():
		return true
	if not _close_dialog:
		_close_dialog = ConfirmationDialog.new()
		_close_dialog.title = "Unapplied UV Edits"
		_close_dialog.dialog_text = "This mesh has UV edits that were not applied. Apply them before closing?"
		_close_dialog.ok_button_text = "Apply and Close"
		_close_dialog.cancel_button_text = "Keep Editing"
		_close_dialog.add_button("Discard", true, "discard")
		_close_dialog.confirmed.connect(func() -> void: _apply_editor(true))
		_close_dialog.custom_action.connect(_on_close_dialog_custom_action)
		add_child(_close_dialog)
	_close_dialog.popup_centered()
	return false


func _on_close_dialog_custom_action(action: StringName) -> void:
	if action == &"discard":
		_close_dialog.hide()
		# Discarded edits are dropped when the editor is next opened, which re-imports
		# from the node's mesh; marking the state clean is enough to let the window close.
		_editor_saved_index = _editor_history_index
		_editor_window.force_close()


func _ensure_unwrap_dialog() -> void:
	if _unwrap_dialog:
		return
	_unwrap_dialog = ConfirmationDialog.new()
	_unwrap_dialog.title = "Auto-Unwrap UVs"
	_unwrap_dialog.ok_button_text = "Unwrap"
	_unwrap_dialog.cancel_button_text = "Cancel"
	_unwrap_dialog.min_size = Vector2i(520, 260)
	_unwrap_dialog.confirmed.connect(_on_unwrap_confirmed)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_unwrap_dialog.add_child(content)

	var description := Label.new()
	description.text = (
		"Automatically cut the mesh into low-distortion charts and pack them without overlap. Each "
		+ "material slot gets its own 0-1 UV tile. The result is saved as a new mesh file and assigned "
		+ "to the node (undoable); the original mesh is not modified and bone weights are kept."
	)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 470.0
	content.add_child(description)

	_unwrap_target_label = Label.new()
	_unwrap_target_label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.94))
	content.add_child(_unwrap_target_label)

	_unwrap_size_label = Label.new()
	_unwrap_size_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unwrap_size_label.custom_minimum_size.x = 470.0
	content.add_child(_unwrap_size_label)

	var method_row := HBoxContainer.new()
	method_row.add_theme_constant_override("separation", 8)
	content.add_child(method_row)
	var method_label := Label.new()
	method_label.text = "Method"
	method_label.custom_minimum_size.x = 120.0
	method_row.add_child(method_label)
	_method_option = OptionButton.new()
	_method_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry: Dictionary in GDDrawUVMeshAdapter.METHODS:
		_method_option.add_item(str(entry["label"]), int(entry["id"]))
		_method_option.set_item_tooltip(_method_option.item_count - 1, str(entry["tooltip"]))
	_method_option.select(0)
	_method_option.item_selected.connect(_on_unwrap_method_selected)
	method_row.add_child(_method_option)
	_method_description = Label.new()
	_method_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_method_description.custom_minimum_size.x = 470.0
	_method_description.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	content.add_child(_method_description)

	_margin_spin = _add_spin_row(
		content,
		"Island margin",
		"Approximate empty space between islands, as a fraction of the texture. Increase it if paint bleeds across island borders; decrease it to use more of the texture.",
		0.002, 0.1, 0.002, DEFAULT_MARGIN
	)

	_unwrap_session_warning = Label.new()
	_unwrap_session_warning.text = (
		"A paint session is open: its current pixels were painted for the old UVs and will not match "
		+ "the new layout. Save your texture first, then paint on a fresh texture."
	)
	_unwrap_session_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unwrap_session_warning.custom_minimum_size.x = 470.0
	_unwrap_session_warning.add_theme_color_override("font_color", Color(1.0, 0.78, 0.4))
	_unwrap_session_warning.visible = false
	content.add_child(_unwrap_session_warning)

	add_child(_unwrap_dialog)


func _add_spin_row(
	parent: Control,
	label_text: String,
	tooltip: String,
	minimum: float,
	maximum: float,
	step: float,
	value: float
) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 120.0
	label.tooltip_text = tooltip
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.tooltip_text = tooltip
	spin.custom_minimum_size.x = 110.0
	row.add_child(spin)
	return spin


func _on_unwrap_confirmed() -> void:
	var target := _pending_target
	_pending_target = null
	if not is_instance_valid(target):
		unwrap_finished.emit({"status": "error", "message": "The target node was removed from the scene."}, null)
		return
	var adapter := GDDrawUVMeshAdapter.from_mesh(target.mesh)
	if adapter == null:
		unwrap_finished.emit({"status": "error", "message": "%s has no triangle geometry that can be unwrapped." % target.name}, target)
		return
	var margin: float = _margin_spin.value
	var method := _method_option.get_selected_id()
	var method_label := GDDrawUVMeshAdapter.get_method_label(method)
	var mesh_at_start := target.mesh
	_run_in_background(
		"Auto-Unwrapping %s" % target.name,
		"Unwrapping %s (%s). Large meshes can take a while with the Smart method." % [target.name, method_label],
		func() -> Variant:
			var unwrapped := adapter.unwrap(method, margin)
			return adapter.build_mesh(unwrapped) if unwrapped != null else null,
		func(new_mesh: Variant) -> void:
			if not is_instance_valid(target):
				unwrap_finished.emit({"status": "error", "message": "The target node was removed while unwrapping."}, null)
			elif target.mesh != mesh_at_start:
				unwrap_finished.emit({"status": "error", "message": "%s's mesh changed while unwrapping; nothing was applied." % target.name}, target)
			else:
				unwrap_finished.emit(_service.finalize_unwrap(target, adapter, new_mesh as ArrayMesh, _plugin, GDDrawStoragePaths.DEFAULT_MESH_DIR, "Auto-Unwrap UVs (%s)" % method_label), target)
	)
