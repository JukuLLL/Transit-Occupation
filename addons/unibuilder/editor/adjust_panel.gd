@tool
class_name UBAdjustPanel
extends PanelContainer
## Adjust-last-operation panel: one control per param of the op just run.


signal param_changed(key: String, value: float)
signal apply_requested
signal cancel_requested


## A preset was picked from the dropdown.
signal preset_selected(name: String)
signal preset_save_requested(name: String)
signal preset_delete_requested(name: String)

const SCENE := "res://addons/unibuilder/editor/adjust_panel.tscn"


var _title: Label
var _rows: VBoxContainer
var _preset_row: HBoxContainer
var _preset_menu: OptionButton
var _preset_delete: Button
var _preset_dialog: ConfirmationDialog
var _preset_name: LineEdit
var _preset_current := ""


var _controls := {}

var _row_of := {}

var _specs: Array = []
var _values := {}


## Builds the panel from its scene.
static func create() -> UBAdjustPanel:
	var panel := (load(SCENE) as PackedScene).instantiate() as UBAdjustPanel
	panel._dress()
	return panel


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		_title = %Title
		_rows = %Rows
		_preset_row = %PresetRow
		_preset_menu = %PresetMenu
		_preset_delete = %PresetDelete
		_preset_dialog = %PresetDialog
		_preset_name = %PresetName
		_preset_menu.item_selected.connect(_on_preset_picked)
		(%PresetSave as Button).pressed.connect(_prompt_preset_name)
		_preset_delete.pressed.connect(func() -> void:
			if not _preset_current.is_empty():
				preset_delete_requested.emit(_preset_current))
		_preset_name.text_submitted.connect(func(_t: String) -> void:
			_preset_dialog.hide()
			confirm_preset_name())
		_preset_dialog.confirmed.connect(confirm_preset_name)
		(%Apply as Button).pressed.connect(func() -> void: apply_requested.emit())
		(%Cancel as Button).pressed.connect(func() -> void: cancel_requested.emit())


func _dress() -> void:
	var scale := EditorInterface.get_editor_scale()
	UBPanelStyle.float_card(self)
	custom_minimum_size.x *= scale
	_preset_name.custom_minimum_size.x *= scale
	UBPanelStyle.scale_layout(self)
	UBPanelStyle.style_header(%Header, %HeaderIcon, _title, "tools")


func _on_preset_picked(idx: int) -> void:
	if idx <= 0:
		return
	_preset_current = _preset_menu.get_item_text(idx)
	_preset_delete.disabled = false
	preset_selected.emit(_preset_current)


func _prompt_preset_name() -> void:
	_preset_name.text = _preset_current
	_preset_dialog.popup_centered()
	_preset_name.grab_focus()
	_preset_name.select_all()


## Confirms the Save dialog with its current name.
func confirm_preset_name() -> void:
	if _preset_name == null:
		return
	var name := _preset_name.text.strip_edges()
	if name.is_empty():
		return
	preset_save_requested.emit(name)


## Sets the preset names shown for this session and the current one.
func set_presets(names: Array, current: String) -> void:
	_preset_current = current
	_preset_menu.clear()
	_preset_menu.add_item("Preset...")
	_preset_menu.set_item_disabled(0, names.is_empty())
	var pick := 0
	for i in names.size():
		_preset_menu.add_item(str(names[i]))
		if str(names[i]) == current:
			pick = i + 1
	_preset_menu.select(pick)
	_preset_delete.disabled = current.is_empty()
	_preset_row.visible = true


func show_action(label: String, params: Array, values: Dictionary) -> void:
	_title.text = label
	_preset_row.visible = false
	_preset_current = ""
	_controls.clear()
	_row_of.clear()
	_specs = params
	_values = values.duplicate()
	for child in _rows.get_children():
		child.queue_free()
	for spec in params:
		var key: String = spec.key
		var control: Control
		if spec.type == "bool":
			var check := CheckBox.new()
			check.button_pressed = bool(values.get(key, false))
			check.toggled.connect(func(v: bool) -> void:
				_changed(key, 1.0 if v else 0.0))
			control = check
		elif spec.type == "enum":
			var opt := OptionButton.new()
			for option in spec.options:
				opt.add_item(option)
			opt.select(clampi(int(values.get(key, 0)), 0, spec.options.size() - 1))
			opt.item_selected.connect(func(idx: int) -> void: _changed(key, float(idx)))
			control = opt
		else:
			var spin := SpinBox.new()
			spin.min_value = spec.min
			spin.max_value = spec.max
			if spec.type == "int":
				spin.step = spec.step
				spin.rounded = true
				spin.value = values.get(spec.key, spec.min)
			else:
				free_float_field(spin, spec.step)
				spin.value = display_value(float(values.get(spec.key, spec.min)))
			spin.value_changed.connect(func(v: float) -> void: _changed(key, v))
			control = spin
		_controls[key] = control
		_row_of[key] = UBPanelStyle.row(_rows, spec.label, control)
	_apply_visibility()


func _changed(key: String, value: float) -> void:
	_values[key] = value
	_apply_visibility()
	param_changed.emit(key, value)


## Whether a param's row is shown given the current values.
func is_param_visible(key: String) -> bool:
	var row = _row_of.get(key)
	return row != null and is_instance_valid(row) and row.visible


func _apply_visibility() -> void:
	for spec in _specs:
		var row = _row_of.get(spec.key)
		if row != null and is_instance_valid(row):
			row.visible = param_visible(spec, _values)


## Evaluates a param schema entry's `requires` rule against the values.
static func param_visible(spec: Dictionary, values: Dictionary) -> bool:
	if not spec.has("requires"):
		return true
	var rule = spec.requires
	if rule is Array:
		for alt in rule:
			if _rule_holds(alt, values):
				return true
		return rule.is_empty()
	return _rule_holds(rule, values)


static func _rule_holds(rule: Dictionary, values: Dictionary) -> bool:
	for key in rule:
		var v: float = float(values.get(key, 0.0))
		var cond = rule[key]
		if cond is bool:
			if is_zero_approx(v) == cond:
				return false
		elif cond is Array:
			if not cond.has(int(v)) and not cond.has(v):
				return false
		elif cond is Dictionary:
			if cond.has("min") and v < float(cond.min):
				return false
			if cond.has("max") and v > float(cond.max):
				return false
		elif not is_equal_approx(v, float(cond)):
			return false
	return true


## Pushes live values into the widgets already on screen.
func sync_values(values: Dictionary) -> void:
	for key in values:
		_values[key] = values[key]
	_apply_visibility()
	for key: String in _controls:
		if not values.has(key):
			continue
		var control: Control = _controls[key]
		if not is_instance_valid(control):
			continue
		if control is CheckBox:
			var on := bool(values[key])
			if control.button_pressed != on:
				control.set_pressed_no_signal(on)
		elif control is OptionButton:

			var idx := int(values[key])
			if control.selected != idx:
				control.select(idx)
		elif control is SpinBox:

			if control.get_line_edit().has_focus():
				continue
			var v := float(values[key])
			if control.step == FREE_STEP:
				v = display_value(v)
			if not is_equal_approx(control.value, v):
				control.set_value_no_signal(v)


## Makes a float SpinBox hold exactly the value it is given, unquantised.
static func free_float_field(spin: SpinBox, arrow_step: float) -> void:
	spin.step = FREE_STEP
	spin.custom_arrow_step = arrow_step
	var state := {}
	spin.gui_input.connect(func(event: InputEvent) -> void:
		_free_field_input(spin, arrow_step, state, event))


const FREE_STEP := 1e-9
## Pixels of travel before a press becomes a drag (SpinBox's own threshold).
const DRAG_START_PX := 2.0


static func _free_field_input(spin: SpinBox, arrow: float, state: Dictionary,
		event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				state.clear()
				state["at"] = mb.position
			else:
				var dragged: bool = state.get("dragging", false)
				state.clear()
				if dragged:
					spin.step = FREE_STEP
					spin.value = clampf(snappedf(spin.value, arrow), spin.min_value, spin.max_value)
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP
				or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) \
				and spin.get_line_edit().is_editing():
			var notches := mb.factor if mb.factor > 0.0 else 1.0
			var dir := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			spin.value = clampf(snappedf(spin.value + dir * arrow * notches, arrow),
				spin.min_value, spin.max_value)
			spin.accept_event()
	elif event is InputEventMouseMotion and state.has("at") \
			and not state.get("dragging", false) \
			and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT \
			and (event as InputEventMouseMotion).position.distance_to(state["at"]) > DRAG_START_PX:
		state["dragging"] = true
		spin.step = arrow


## The shortest decimal (up to 10 places) that reads back as the same float32.
static func display_value(v: float) -> float:
	if not is_finite(v):
		return v
	var single := PackedFloat32Array([v])[0]
	for decimals in 11:
		var shortest := String.num(v, decimals).to_float()
		if PackedFloat32Array([shortest])[0] == single:
			return shortest
	return v
