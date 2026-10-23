@tool
# Derived from Gator Model Studio (c) 2026 Blackwater Gator Studios, MIT License.
# See LICENSE-GatorModelStudio.txt. Modified for GDDraw: renamed classes, mesh-rebuild code removed,
# host hooks added to the editor window.
class_name GDDrawUVEditorWindow
extends Window

signal mesh_commit_requested(mesh: GDDrawUVMeshData, action_name: String)
signal mesh_preview_requested(mesh: GDDrawUVMeshData)
signal mesh_preview_cancelled
signal checker_preview_toggled(enabled: bool)
signal face_selection_changed(face_indices: PackedInt32Array)
signal active_material_changed(material_index: int)
## Emitted by the document bar; the host owns the undo history and the mesh.
signal apply_requested
signal undo_requested
signal redo_requested
## Automatic unwrap of one material tile with the chosen method (see GDDrawUVMeshAdapter.UnwrapMethod);
## the host runs it on its adapter.
signal auto_unwrap_requested(material_index: int, margin: float, method: int)

## Return false to keep the window open (used to protect unapplied edits).
var close_guard: Callable = Callable()

var _undo_button: Button
var _redo_button: Button
var _apply_button: Button
var _title_text: String = "GDDraw — UV Editor"
var _dirty: bool = false
var _mesh: GDDrawUVMeshData
var _textures: Array[Texture2D] = []
var _material_names: PackedStringArray = PackedStringArray()
var _active_material_index: int = 0
var _material_option: OptionButton
var _canvas: GDDrawUVEditorCanvas
var _status_label: Label
var _mode_buttons: Dictionary = {}
var _checker_3d_button: CheckButton
var _method_option: OptionButton
var _padding_spin: SpinBox
var _relax_iterations: SpinBox
var _relax_strength: SpinBox
var _relax_boundary: CheckBox
var _texel_density_spin: SpinBox
var _density_label: Label
var _background_operation_row: HBoxContainer
var _background_operation_label: Label
var _background_operation_progress: ProgressBar
var _background_operation_cancel_button: Button
var _background_operation_buttons: Array[Button] = []
var _background_operation_job: GDDrawUVBackgroundJob
var _background_operation_task_id: int = -1
var _background_operation_result_holder: Dictionary = {}
var _background_operation_completion: Callable = Callable()
var _background_operation_poll_timer: Timer
var _background_operation_title: String = ""
var _data_generation: int = 0
var _unfold_preview_window: GDDrawUVUnfoldPreviewWindow


func _ready() -> void:
	visible = false
	title = _title_text
	initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	min_size = Vector2i(720, 480)
	size = Vector2i(1040, 700)
	always_on_top = false
	transient = true
	unresizable = false
	wrap_controls = false
	close_requested.connect(_on_close_requested)
	_build_interface()
	_background_operation_poll_timer = Timer.new()
	_background_operation_poll_timer.wait_time = 0.05
	_background_operation_poll_timer.one_shot = false
	_background_operation_poll_timer.timeout.connect(_poll_background_operation)
	add_child(_background_operation_poll_timer)


func _exit_tree() -> void:
	if _background_operation_task_id < 0:
		return
	if _background_operation_job != null:
		_background_operation_job.request_cancel()
	WorkerThreadPool.wait_for_task_completion(_background_operation_task_id)
	_background_operation_task_id = -1
	_background_operation_job = null


func set_data(
	mesh: GDDrawUVMeshData,
	textures: Array[Texture2D] = [],
	material_names: PackedStringArray = PackedStringArray(),
	active_material_index: int = 0
) -> void:
	if _canvas != null and _mesh != mesh:
		_canvas.cancel_transform()
	_data_generation += 1
	_mesh = mesh
	_textures.clear()
	for source_texture: Texture2D in textures:
		_textures.append(source_texture)
	_material_names = material_names.duplicate()
	_active_material_index = clampi(active_material_index, 0, maxi(_material_count() - 1, 0))
	_update_material_option()
	if _canvas != null:
		_canvas.set_data(mesh, _textures, _material_names)
	if _unfold_preview_window != null:
		_unfold_preview_window.set_data(mesh, _textures)
	_update_density_label()


func set_checker_preview_enabled(enabled: bool) -> void:
	if _checker_3d_button == null:
		return
	_checker_3d_button.set_pressed_no_signal(enabled)


## Host-driven document state: the title shows an asterisk while edits are unapplied.
func set_document_state(document_name: String, dirty: bool, can_undo: bool, can_redo: bool) -> void:
	_dirty = dirty
	_title_text = "GDDraw — UV Editor — %s%s" % [document_name, " *" if dirty else ""]
	title = _title_text
	if _undo_button != null:
		_undo_button.disabled = not can_undo
	if _redo_button != null:
		_redo_button.disabled = not can_redo
	if _apply_button != null:
		_apply_button.disabled = not dirty


func get_selected_method() -> int:
	return _method_option.get_selected_id() if _method_option != null else 0


func set_status_text(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func is_dirty() -> bool:
	return _dirty


## Closes without consulting the close guard.
func force_close() -> void:
	_close_now()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not visible:
		return
	if not (key.ctrl_pressed or key.meta_pressed):
		return
	if key.keycode == KEY_Z and not key.shift_pressed:
		undo_requested.emit()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_Y or (key.keycode == KEY_Z and key.shift_pressed):
		redo_requested.emit()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_S:
		apply_requested.emit()
		get_viewport().set_input_as_handled()


func open_editor() -> void:
	if visible:
		grab_focus()
	else:
		popup_centered_clamped(Vector2i(1040, 700), 0.9)
		call_deferred("grab_focus")
	if _canvas != null:
		_canvas.grab_focus()
		_canvas.frame_all()


func _build_interface() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	var document_bar: HFlowContainer = HFlowContainer.new()
	document_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(document_bar)
	_undo_button = _add_button(document_bar, "Undo", func() -> void: undo_requested.emit(), "Undo the last UV edit (Ctrl+Z)")
	_undo_button.disabled = true
	_redo_button = _add_button(document_bar, "Redo", func() -> void: redo_requested.emit(), "Redo the last undone UV edit (Ctrl+Y)")
	_redo_button.disabled = true
	document_bar.add_child(VSeparator.new())
	_apply_button = _add_button(
		document_bar,
		"Apply to Mesh",
		func() -> void: apply_requested.emit(),
		"Save these UVs as a new mesh file and assign it to the MeshInstance3D (undoable in the editor). Bone weights are kept. Ctrl+S"
	)
	_apply_button.disabled = true

	var selection_bar: HFlowContainer = HFlowContainer.new()
	selection_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(selection_bar)
	var mode_group: ButtonGroup = ButtonGroup.new()
	_add_mode_button(selection_bar, "UV Vertex", GDDrawUVEditorCanvas.SelectMode.VERTEX, mode_group, "Select UV vertices. Shortcut: 1")
	_add_mode_button(selection_bar, "UV Edge", GDDrawUVEditorCanvas.SelectMode.EDGE, mode_group, "Select UV edges. Shortcut: 2")
	_add_mode_button(selection_bar, "UV Face", GDDrawUVEditorCanvas.SelectMode.FACE, mode_group, "Select individual UV faces. Shortcut: 3")
	_add_mode_button(selection_bar, "UV Island", GDDrawUVEditorCanvas.SelectMode.ISLAND, mode_group, "Select connected UV islands separated by seams. Shortcut: 4")
	_add_button(selection_bar, "All", _on_select_all, "Select everything in the active UV selection mode (A)")
	_add_button(selection_bar, "Clear", _on_clear_selection, "Clear UV selection (Alt+A)")
	_add_button(selection_bar, "Frame", _on_frame_all, "Frame the complete UV map (Home)")
	selection_bar.add_child(VSeparator.new())
	_add_button(selection_bar, "Move", _on_begin_move, "Move selected UVs with the mouse (G)")
	_add_button(selection_bar, "Rotate", _on_begin_rotate, "Rotate selected UVs around their centre (R)")
	_add_button(selection_bar, "Scale", _on_begin_scale, "Scale selected UVs around their centre (S)")

	var operation_bar: HFlowContainer = HFlowContainer.new()
	operation_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(operation_bar)
	_material_option = OptionButton.new()
	_material_option.tooltip_text = "UV operations affect only the selected material. Selecting UVs in another tile switches the active material automatically."
	_material_option.item_selected.connect(_on_material_option_selected)
	operation_bar.add_child(_material_option)
	_update_material_option()
	_method_option = OptionButton.new()
	_method_option.tooltip_text = "How Auto Unwrap builds the UVs. Smart is the automatic, low-distortion method (best for characters); the others are simple projections."
	for entry: Dictionary in GDDrawUVMeshAdapter.METHODS:
		_method_option.add_item(str(entry["label"]), int(entry["id"]))
		_method_option.set_item_tooltip(_method_option.item_count - 1, str(entry["tooltip"]))
	_method_option.select(0)
	operation_bar.add_child(_method_option)
	_add_button(
		operation_bar,
		"Auto Unwrap",
		func() -> void: auto_unwrap_requested.emit(_active_material_index, float(_padding_spin.value), get_selected_method()),
		"Unwrap the active material with the chosen method and pack the islands with the Padding value as margin. Ignores marked seams."
	)
	var unwrap_button: Button = _add_button(operation_bar, "Unwrap", _on_unwrap, "Unwrap selected faces from the currently marked seams, ignoring the previous UV layout")
	_background_operation_buttons.append(unwrap_button)
	_padding_spin = _spin(0.0, 0.2, 0.005, 0.01)
	_padding_spin.prefix = "Padding "
	_padding_spin.tooltip_text = "Empty space between UV islands and around the tile border, as a fraction of the tile. Used by Auto Unwrap, Unwrap and Pack Islands."
	operation_bar.add_child(_padding_spin)
	var pack_button: Button = _add_button(operation_bar, "Pack Islands", _on_pack, "Pack selected islands independently inside each material tile")
	_background_operation_buttons.append(pack_button)
	operation_bar.add_child(VSeparator.new())
	_add_button(operation_bar, "Mark Seam", _on_mark_seam, "Mark selected UV edges as cuts between islands")
	_add_button(operation_bar, "Clear Seam", _on_clear_seam, "Clear seam flags from selected UV edges")
	_add_button(operation_bar, "Split", _on_split, "Split selected UV edges into separate islands. The UVs do not move until one side is transformed.")
	_add_button(operation_bar, "Stitch", _on_stitch, "Align both sides of selected UV seams and weld them back together")
	_add_button(operation_bar, "Weld Vertices", _on_weld, "Average selected UV corners that belong to the same model vertex")

	var relax_bar: HFlowContainer = HFlowContainer.new()
	relax_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(relax_bar)
	_relax_iterations = _spin(1.0, 100.0, 1.0, 12.0)
	_relax_iterations.prefix = "Relax passes "
	_relax_iterations.tooltip_text = "More passes distribute UV spacing more evenly but take longer"
	relax_bar.add_child(_relax_iterations)
	_relax_strength = _spin(0.0, 1.0, 0.05, 0.5)
	_relax_strength.prefix = "Strength "
	relax_bar.add_child(_relax_strength)
	_relax_boundary = CheckBox.new()
	_relax_boundary.text = "Preserve Boundary"
	_relax_boundary.button_pressed = true
	_relax_boundary.tooltip_text = "Keep seam and outer boundary UVs fixed while relaxing the interior"
	relax_bar.add_child(_relax_boundary)
	_add_button(relax_bar, "Relax", _on_relax, "Reduce uneven UV spacing and stretching inside selected islands")
	relax_bar.add_child(VSeparator.new())
	_texel_density_spin = _spin(1.0, 8192.0, 1.0, 128.0)
	_texel_density_spin.prefix = "Target px/unit "
	_texel_density_spin.tooltip_text = "Scale selected islands so one local 3D unit receives approximately this many texture pixels"
	relax_bar.add_child(_texel_density_spin)
	_add_button(relax_bar, "Set Density", _on_set_density, "Apply the target texel density using the loaded texture resolution, then pack if needed")
	_density_label = Label.new()
	_density_label.text = "Current: —"
	_density_label.tooltip_text = "Measured texel density for the selected faces or islands"
	relax_bar.add_child(_density_label)

	var display_bar: HFlowContainer = HFlowContainer.new()
	display_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(display_bar)
	var checker: CheckBox = CheckBox.new()
	checker.text = "2D Checker"
	checker.button_pressed = true
	checker.tooltip_text = "Show a checkerboard behind the UV layout"
	checker.toggled.connect(_on_show_checker_toggled)
	display_bar.add_child(checker)
	var texture_check: CheckBox = CheckBox.new()
	texture_check.text = "Show Albedo"
	texture_check.button_pressed = true
	texture_check.tooltip_text = "Show each material's albedo texture beneath its UV tile"
	texture_check.toggled.connect(_on_show_texture_toggled)
	display_bar.add_child(texture_check)
	var distortion: CheckBox = CheckBox.new()
	distortion.text = "Distortion"
	distortion.tooltip_text = "Colour UV faces by relative area distortion: red is stretched and blue is compressed"
	distortion.toggled.connect(_on_show_distortion_toggled)
	display_bar.add_child(distortion)
	var seams: CheckBox = CheckBox.new()
	seams.text = "Show Seams"
	seams.button_pressed = true
	seams.tooltip_text = "Draw marked seam edges in red"
	seams.toggled.connect(_on_show_seams_toggled)
	display_bar.add_child(seams)
	_checker_3d_button = CheckButton.new()
	_checker_3d_button.text = "3D Checker Preview"
	_checker_3d_button.tooltip_text = "Temporarily replace the viewport albedo with a checker texture. This preview is not saved or exported."
	_checker_3d_button.toggled.connect(_on_checker_3d_toggled)
	# Gator drew this preview in its own 3D viewport; GDDraw's painter shows the result
	# after Apply instead, so the toggle is kept (for the ported code paths) but hidden.
	_checker_3d_button.visible = false
	display_bar.add_child(_checker_3d_button)
	_add_button(
		display_bar,
		"3D → UV Preview",
		_on_open_unfold_preview,
		"Animate the model from its 3D shape into the flattened UV islands. This is a temporary preview and does not change the mesh."
	)

	_unfold_preview_window = GDDrawUVUnfoldPreviewWindow.new()
	add_child(_unfold_preview_window)

	_canvas = GDDrawUVEditorCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.mesh_commit_requested.connect(_on_canvas_mesh_commit)
	_canvas.mesh_preview_requested.connect(_on_canvas_mesh_preview_requested)
	_canvas.mesh_preview_cancelled.connect(_on_canvas_mesh_preview_cancelled)
	_canvas.selection_changed.connect(_on_canvas_selection_changed)
	_canvas.status_changed.connect(_on_canvas_status)
	_canvas.select_mode_changed.connect(_on_canvas_select_mode_changed)
	root.add_child(_canvas)

	_background_operation_row = HBoxContainer.new()
	_background_operation_row.visible = false
	_background_operation_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_background_operation_label = Label.new()
	_background_operation_label.text = "UV Operation: Preparing"
	_background_operation_row.add_child(_background_operation_label)
	_background_operation_progress = ProgressBar.new()
	_background_operation_progress.min_value = 0.0
	_background_operation_progress.max_value = 100.0
	_background_operation_progress.value = 0.0
	_background_operation_progress.show_percentage = true
	_background_operation_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_background_operation_row.add_child(_background_operation_progress)
	_background_operation_cancel_button = Button.new()
	_background_operation_cancel_button.text = "Cancel"
	_background_operation_cancel_button.tooltip_text = "Cancel the current UV operation without changing the mesh"
	_background_operation_cancel_button.pressed.connect(_on_background_operation_cancel_pressed)
	_background_operation_row.add_child(_background_operation_cancel_button)
	root.add_child(_background_operation_row)

	var status_panel: PanelContainer = PanelContainer.new()
	_status_label = Label.new()
	_status_label.text = "UV Editor: each material has its own tile. Mouse wheel zooms, middle mouse pans, G/R/S transform, 1–4 change selection mode."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_panel.add_child(_status_label)
	root.add_child(status_panel)

	(_mode_buttons[GDDrawUVEditorCanvas.SelectMode.ISLAND] as Button).button_pressed = true


func _add_mode_button(parent: Control, label: String, mode: int, group: ButtonGroup, tooltip: String) -> void:
	var button: Button = Button.new()
	button.text = label
	button.toggle_mode = true
	button.button_group = group
	button.tooltip_text = tooltip
	button.pressed.connect(_on_mode_pressed.bind(mode))
	parent.add_child(button)
	_mode_buttons[mode] = button


func _add_button(parent: Control, label: String, callback: Callable, tooltip: String) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.tooltip_text = tooltip
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _spin(minimum: float, maximum: float, step: float, value: float) -> SpinBox:
	var control: SpinBox = SpinBox.new()
	control.min_value = minimum
	control.max_value = maximum
	control.step = step
	control.value = value
	control.custom_arrow_step = step
	return control


func _target_faces() -> PackedInt32Array:
	if _mesh == null:
		return PackedInt32Array()
	var selected: PackedInt32Array = _canvas.get_selected_face_indices()
	if not selected.is_empty():
		var first_valid_face: int = -1
		for face_index: int in selected:
			if face_index >= 0 and face_index < _mesh.faces.size():
				first_valid_face = face_index
				break
		if first_valid_face >= 0:
			_set_active_material_index(_mesh.get_face_material(first_valid_face), false)
	return _filter_faces_to_active_material(
		selected if not selected.is_empty() else GDDrawUVOperations.all_faces(_mesh)
	)


func _filter_faces_to_active_material(face_indices: PackedInt32Array) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	if _mesh == null:
		return result
	for face_index: int in face_indices:
		if face_index < 0 or face_index >= _mesh.faces.size():
			continue
		if _mesh.get_face_material(face_index) == _active_material_index:
			result.append(face_index)
	return result


func _material_count() -> int:
	var count: int = maxi(_textures.size(), _material_names.size())
	if _mesh != null:
		for face_index: int in _mesh.faces.size():
			count = maxi(count, _mesh.get_face_material(face_index) + 1)
	return maxi(count, 1)


func _update_material_option() -> void:
	if _material_option == null:
		return
	var count: int = _material_count()
	_material_option.clear()
	for material_index: int in count:
		var material_name: String = "Material %d" % (material_index + 1)
		if material_index < _material_names.size() and not _material_names[material_index].is_empty():
			material_name = _material_names[material_index]
		_material_option.add_item("Tile %d: %s" % [material_index + 1, material_name])
	_active_material_index = clampi(_active_material_index, 0, count - 1)
	_material_option.select(_active_material_index)


func _set_active_material_index(material_index: int, clear_selection: bool) -> void:
	var clamped_index: int = clampi(material_index, 0, _material_count() - 1)
	if _active_material_index == clamped_index:
		if _material_option != null:
			_material_option.select(clamped_index)
		return
	_active_material_index = clamped_index
	if _material_option != null:
		_material_option.select(clamped_index)
	if clear_selection and _canvas != null:
		_canvas.clear_selection()
	_update_density_label()


func _on_material_option_selected(material_index: int) -> void:
	_set_active_material_index(material_index, true)
	active_material_changed.emit(_active_material_index)


func _texture_size() -> Vector2i:
	if _mesh != null:
		for face_index: int in _target_faces():
			var material_index: int = _mesh.get_face_material(face_index)
			var material_texture: Texture2D = _get_material_texture(material_index)
			if material_texture != null:
				return Vector2i(maxi(material_texture.get_width(), 1), maxi(material_texture.get_height(), 1))
	for material_texture: Texture2D in _textures:
		if material_texture != null:
			return Vector2i(maxi(material_texture.get_width(), 1), maxi(material_texture.get_height(), 1))
	return Vector2i(1024, 1024)


func _get_material_texture(material_index: int) -> Texture2D:
	if material_index < 0 or material_index >= _textures.size():
		return null
	return _textures[material_index]


func _material_face_groups(source: GDDrawUVMeshData, face_indices: PackedInt32Array) -> Array[PackedInt32Array]:
	return GDDrawUVOperations.group_faces_by_material(source, face_indices)


func _commit(new_mesh: GDDrawUVMeshData, action_name: String, message: String) -> void:
	if new_mesh == null:
		return
	_data_generation += 1
	mesh_commit_requested.emit(new_mesh, action_name)
	_status_label.text = message


func _on_mode_pressed(mode: int) -> void:
	_canvas.set_select_mode(mode)


func _on_canvas_select_mode_changed(mode: int) -> void:
	for key: Variant in _mode_buttons.keys():
		var button: Button = _mode_buttons[key] as Button
		button.set_pressed_no_signal(int(key) == mode)


func _on_canvas_selection_changed() -> void:
	if _canvas == null:
		return
	var selected_faces: PackedInt32Array = _canvas.get_selected_face_indices()
	if _mesh != null:
		for face_index: int in selected_faces:
			if face_index >= 0 and face_index < _mesh.faces.size():
				_set_active_material_index(_mesh.get_face_material(face_index), false)
				break
	face_selection_changed.emit(selected_faces)
	_update_density_label()


func _on_select_all() -> void:
	_canvas.select_all()


func _on_clear_selection() -> void:
	_canvas.clear_selection()


func _on_frame_all() -> void:
	_canvas.frame_all()


func _on_begin_move() -> void:
	_canvas.begin_transform(GDDrawUVEditorCanvas.TransformMode.MOVE)


func _on_begin_rotate() -> void:
	_canvas.begin_transform(GDDrawUVEditorCanvas.TransformMode.ROTATE)


func _on_begin_scale() -> void:
	_canvas.begin_transform(GDDrawUVEditorCanvas.TransformMode.SCALE)


func _on_unwrap() -> void:
	_start_uv_background_operation(
		"seams",
		"Unwrap From Seams",
		"Unwrapped selected faces from the marked seams and packed the resulting islands."
	)


func _on_pack() -> void:
	if _mesh == null or not _mesh.has_uv_map:
		return
	_start_uv_background_operation(
		"pack",
		"Pack UV Islands",
		"Packed selected UV islands without overlap."
	)


func _start_uv_background_operation(
	operation: String,
	action_name: String,
	success_message: String
) -> void:
	if _mesh == null:
		return
	if _background_operation_task_id >= 0:
		_status_label.text = "Another UV operation is already running."
		return
	var source: GDDrawUVMeshData = _mesh.duplicate_mesh_data_fast()
	var target_faces: PackedInt32Array = _target_faces().duplicate()
	if target_faces.is_empty():
		_status_label.text = "The active material has no faces to process."
		return
	var padding: float = float(_padding_spin.value)
	var source_generation: int = _data_generation
	var worker: Callable = Callable(self, "_run_uv_background_operation").bind(
		source,
		target_faces,
		operation,
		padding
	)
	var completion: Callable = Callable(self, "_finish_uv_background_operation").bind(
		source_generation,
		action_name,
		success_message
	)
	_start_background_operation(action_name, worker, completion)


func _run_uv_background_operation(
	job: GDDrawUVBackgroundJob,
	source: GDDrawUVMeshData,
	target_faces: PackedInt32Array,
	operation: String,
	padding: float
) -> Variant:
	var groups: Array[PackedInt32Array] = _material_face_groups(source, target_faces)
	if groups.is_empty():
		return source
	var result: GDDrawUVMeshData = source
	for group_index: int in groups.size():
		if job.is_cancelled():
			return null
		var group: PackedInt32Array = groups[group_index]
		var material_index: int = result.get_face_material(group[0])
		var progress_start: float = float(group_index) / float(groups.size())
		var progress_end: float = float(group_index + 1) / float(groups.size())
		var proxy: GDDrawUVBackgroundProgressProxy = GDDrawUVBackgroundProgressProxy.new(
			job,
			progress_start,
			progress_end,
			"Material %d" % (material_index + 1)
		)
		match operation:
			"seams":
				result = GDDrawUVOperations.unwrap_from_seams(result, group, padding, proxy)
			"pack":
				result = GDDrawUVOperations.pack_islands(result, group, padding, proxy)
		if result == null:
			return null
	return result


func _start_background_operation(
	title_text: String,
	worker: Callable,
	completion: Callable
) -> void:
	if _background_operation_task_id >= 0:
		_status_label.text = "Another UV operation is already running."
		return
	if not worker.is_valid() or not completion.is_valid():
		_status_label.text = "The UV operation could not be started."
		return

	_background_operation_title = title_text
	_background_operation_job = GDDrawUVBackgroundJob.new()
	_background_operation_result_holder = {}
	_background_operation_completion = completion
	var holder: Dictionary = _background_operation_result_holder
	var job: GDDrawUVBackgroundJob = _background_operation_job
	var action: Callable = func() -> void:
		holder["result"] = worker.call(job)
		if not job.is_cancelled():
			job.update_progress(1.0, "Finishing")

	_background_operation_task_id = WorkerThreadPool.add_task(
		action,
		false,
		"GDDraw UV %s" % title_text.to_lower()
	)
	_set_background_operation_buttons_disabled(true)
	_background_operation_label.text = "%s: Preparing" % title_text
	_background_operation_progress.value = 0.0
	_background_operation_cancel_button.disabled = false
	_background_operation_row.visible = true
	_background_operation_poll_timer.start()
	_status_label.text = "%s is running in the background." % title_text


func _set_background_operation_buttons_disabled(disabled: bool) -> void:
	for button: Button in _background_operation_buttons:
		button.disabled = disabled


func _on_background_operation_cancel_pressed() -> void:
	if _background_operation_task_id < 0 or _background_operation_job == null:
		return
	_background_operation_job.request_cancel()
	_background_operation_cancel_button.disabled = true
	_background_operation_label.text = "%s: Cancelling..." % _background_operation_title


func _poll_background_operation() -> void:
	if _background_operation_task_id < 0 or _background_operation_job == null:
		_background_operation_poll_timer.stop()
		return
	var state: Dictionary = _background_operation_job.get_state()
	var progress: float = clampf(float(state.get("progress", 0.0)), 0.0, 1.0)
	var stage: String = str(state.get("stage", "Working"))
	_background_operation_progress.value = progress * 100.0
	_background_operation_label.text = "%s: %s" % [_background_operation_title, stage]
	if not WorkerThreadPool.is_task_completed(_background_operation_task_id):
		return

	WorkerThreadPool.wait_for_task_completion(_background_operation_task_id)
	state = _background_operation_job.get_state()
	var result: Variant = _background_operation_result_holder.get("result")
	var cancelled: bool = bool(state.get("cancelled", false))
	var completion: Callable = _background_operation_completion
	_background_operation_poll_timer.stop()
	_background_operation_task_id = -1
	_background_operation_job = null
	_background_operation_result_holder = {}
	_background_operation_completion = Callable()
	_background_operation_title = ""
	_background_operation_row.visible = false
	_background_operation_cancel_button.disabled = false
	_set_background_operation_buttons_disabled(false)
	if completion.is_valid():
		completion.call(result, cancelled)


func _finish_uv_background_operation(
	result: Variant,
	cancelled: bool,
	source_generation: int,
	action_name: String,
	success_message: String
) -> void:
	if cancelled:
		_status_label.text = "%s cancelled. The mesh was not changed." % action_name
		return
	if source_generation != _data_generation:
		_status_label.text = "%s result discarded because the mesh changed while it was running." % action_name
		return
	var new_mesh: GDDrawUVMeshData = result as GDDrawUVMeshData
	if new_mesh == null:
		_status_label.text = "%s failed before producing UV data." % action_name
		return
	_commit(new_mesh, action_name, success_message)


func _selected_model_edges() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if _mesh == null:
		return result
	for ref: Vector2i in _canvas.get_selected_edge_refs():
		if ref.x < 0 or ref.x >= _mesh.faces.size():
			continue
		var face: PackedInt32Array = _mesh.faces[ref.x]
		if ref.y < 0 or ref.y >= face.size():
			continue
		var edge: Vector2i = GDDrawUVMeshData.canonical_edge(face[ref.y], face[(ref.y + 1) % face.size()])
		if not result.has(edge):
			result.append(edge)
	return result


func _on_mark_seam() -> void:
	var edges: Array[Vector2i] = _selected_model_edges()
	if edges.is_empty():
		_status_label.text = "Use UV Edge mode and select one or more edges first."
		return
	_commit(GDDrawUVOperations.mark_edges_as_seams(_mesh, edges, true), "Mark UV Seams", "Marked %d seam edges." % edges.size())


func _on_clear_seam() -> void:
	var edges: Array[Vector2i] = _selected_model_edges()
	if edges.is_empty():
		_status_label.text = "Use UV Edge mode and select one or more edges first."
		return
	_commit(GDDrawUVOperations.mark_edges_as_seams(_mesh, edges, false), "Clear UV Seams", "Cleared %d seam edges." % edges.size())


func _on_split() -> void:
	var refs: Array[Vector2i] = _canvas.get_selected_edge_refs()
	if refs.is_empty():
		_status_label.text = "Use UV Edge mode and select the edges to split."
		return
	_commit(GDDrawUVOperations.split_uv_edges(_mesh, refs), "Split UV Edges", "Split selected edges into separate UV islands. Move one side to see the separation.")


func _on_stitch() -> void:
	var refs: Array[Vector2i] = _canvas.get_selected_edge_refs()
	if refs.is_empty():
		_status_label.text = "Use UV Edge mode and select seam edges to stitch."
		return
	_commit(GDDrawUVOperations.stitch_uv_edges(_mesh, refs), "Stitch UV Edges", "Aligned both sides of the selected seams and cleared their seam flags.")


func _on_weld() -> void:
	var corners: Array[Vector2i] = _canvas.get_selected_corners()
	if corners.size() < 2:
		_status_label.text = "Select at least two UV vertices belonging to shared model vertices."
		return
	_commit(GDDrawUVOperations.weld_corners(_mesh, corners), "Weld UV Vertices", "Welded compatible selected UV vertices at their average positions.")


func _on_relax() -> void:
	if _mesh == null or not _mesh.has_uv_map:
		return
	var result: GDDrawUVMeshData = GDDrawUVOperations.relax_uvs(
		_mesh,
		_target_faces(),
		int(_relax_iterations.value),
		float(_relax_strength.value),
		_relax_boundary.button_pressed
	)
	_commit(result, "Relax UVs", "Relaxed selected UVs to reduce uneven spacing while preserving the chart bounds.")


func _on_set_density() -> void:
	if _mesh == null or not _mesh.has_uv_map:
		return
	var target_faces: PackedInt32Array = _target_faces()
	var result: GDDrawUVMeshData = _mesh
	for group: PackedInt32Array in _material_face_groups(_mesh, target_faces):
		var material_index: int = _mesh.get_face_material(group[0])
		var material_texture: Texture2D = _get_material_texture(material_index)
		var texture_size: Vector2i = Vector2i(1024, 1024)
		if material_texture != null:
			texture_size = Vector2i(maxi(material_texture.get_width(), 1), maxi(material_texture.get_height(), 1))
		result = GDDrawUVOperations.set_texel_density(
			result,
			group,
			float(_texel_density_spin.value),
			texture_size
		)
	_commit(result, "Set UV Texel Density", "Scaled selected islands per material to approximately %.1f px per local unit. Use Pack Islands afterward if charts leave their tiles." % float(_texel_density_spin.value))


func _on_canvas_mesh_commit(new_mesh: GDDrawUVMeshData, action_name: String) -> void:
	_commit(new_mesh, action_name, "%s applied." % action_name)


func _on_canvas_mesh_preview_requested(preview_mesh: GDDrawUVMeshData) -> void:
	if preview_mesh == null:
		return
	mesh_preview_requested.emit(preview_mesh)


func _on_canvas_mesh_preview_cancelled() -> void:
	mesh_preview_cancelled.emit()


func _on_canvas_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
	_update_density_label()


func _update_density_label() -> void:
	if _density_label == null:
		return
	if _mesh == null or not _mesh.has_uv_map:
		_density_label.text = "Current: —"
		_density_label.tooltip_text = "Create a UV map to measure texel density."
		return
	var faces: PackedInt32Array = _target_faces()
	var density: float = GDDrawUVOperations.get_texel_density(_mesh, faces, _texture_size())
	_density_label.text = "Current: %.2f px/unit" % density if density > 0.0 else "Current: —"
	_density_label.tooltip_text = "Measured using the first selected material texture (%d×%d)." % [_texture_size().x, _texture_size().y]


func _on_show_checker_toggled(enabled: bool) -> void:
	_canvas.show_checker = enabled
	_canvas.queue_redraw()


func _on_show_texture_toggled(enabled: bool) -> void:
	_canvas.show_texture = enabled
	_canvas.queue_redraw()


func _on_show_distortion_toggled(enabled: bool) -> void:
	_canvas.show_distortion = enabled
	_canvas.queue_redraw()


func _on_show_seams_toggled(enabled: bool) -> void:
	_canvas.show_seams = enabled
	_canvas.queue_redraw()


func _on_open_unfold_preview() -> void:
	if _unfold_preview_window == null:
		return
	_unfold_preview_window.set_data(_mesh, _textures)
	_unfold_preview_window.open_preview()


func _on_checker_3d_toggled(enabled: bool) -> void:
	checker_preview_toggled.emit(enabled)


func _on_close_requested() -> void:
	if close_guard.is_valid() and not bool(close_guard.call()):
		return
	_close_now()


func _close_now() -> void:
	if _canvas != null:
		_canvas.cancel_transform()
	if _background_operation_task_id >= 0 and _background_operation_job != null:
		_background_operation_job.request_cancel()
	if _checker_3d_button != null and _checker_3d_button.button_pressed:
		_checker_3d_button.set_pressed_no_signal(false)
		checker_preview_toggled.emit(false)
	if _unfold_preview_window != null:
		_unfold_preview_window.close_preview()
	hide()
