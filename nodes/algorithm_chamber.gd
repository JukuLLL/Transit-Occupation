class_name AlgorithmChamber extends Area3D

@export var required := 6
@export var fade_delay := 1.0   # seconds to show 6/6 before fading
@export var fade_time := 1.5

var inserted := 0
var pending := 0 # host only: insertions announced but not yet applied
var label:Label
var layer:CanvasLayer
var local_player:player

signal progress_changed(count:int, total:int)
signal completed

func _ready() -> void:
	add_to_group("algorithm_chamber")
	GDSync.expose_func(_insert)
	_build_ui()
	_update_ui()

# ---------- Host: detects someone walking up while carrying ----------
func _physics_process(_delta:float) -> void:
	if !GDSync.is_host() or Network.round_over:
		return
	if inserted + pending >= required:
		return
	for body in get_overlapping_bodies():
		var p := body as player
		if p == null or p.monster:
			continue
		var item = p.carried_item
		if !is_instance_valid(item) or item.consumed:
			continue
		item.consumed = true
		pending += 1
		GDSync.call_func_all(_insert, p.name.to_int())
		break # one unit per frame

# ---------- Every client ----------
func _insert(player_id:int) -> void:
	pending = maxi(pending - 1, 0)
	var p := get_tree().current_scene.find_child(str(player_id), true, false) as player
	if p != null:
		var item = p.carried_item
		p.carried_item = null
		if is_instance_valid(item):
			item.queue_free() # the unit disappears, it is not stored in the chamber
	inserted = mini(inserted + 1, required)
	_update_ui()
	progress_changed.emit(inserted, required)
	if inserted >= required:
		completed.emit()
		_fade_out()

# ---------- HUD ----------
func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = 70 # just under the round timer

func _update_ui() -> void:
	label.text = "%d/%d" % [inserted, required]
	if inserted >= required:
		label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))

func _process(_delta:float) -> void:
	# Survivors only: the monster never sees the counter
	if !is_instance_valid(local_player):
		local_player = get_tree().current_scene.find_child(str(GDSync.get_client_id()), true, false) as player
	layer.visible = !(is_instance_valid(local_player) and local_player.monster)

func _fade_out() -> void:
	var tw := create_tween()
	tw.tween_interval(fade_delay)
	tw.tween_property(label, "modulate:a", 0.0, fade_time).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(label.hide)
