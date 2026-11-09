class_name AlgorithmChamber extends Area3D

@export var required := 6
@export var fade_delay := 1.0   # seconds to show 6/6 before fading
@export var fade_time := 1.5

# Shared by every chamber in the map
static var inserted := 0
static var pending := 0 # host only: insertions announced but not yet applied
static var done := false
static var shared_layer:CanvasLayer
static var shared_label:Label

var local_player:player

signal progress_changed(count:int, total:int)
signal completed

func _ready() -> void:
	add_to_group("algorithm_chamber")
	# The first chamber to load in a new match resets the shared state
	if get_tree().get_nodes_in_group("algorithm_chamber").size() == 1:
		inserted = 0
		pending = 0
		done = false
		shared_layer = null
		shared_label = null
	GDSync.expose_func(_insert)
	if !is_instance_valid(shared_layer):
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
		break # one unit per frame per chamber

# ---------- Every client ----------
func _insert(player_id:int) -> void:
	pending = maxi(pending - 1, 0)
	var p := get_tree().current_scene.find_child(str(player_id), true, false) as player
	if p != null:
		var item = p.carried_item
		p.carried_item = null
		if is_instance_valid(item):
			item.queue_free() # the unit disappears, it is not stored in the chamber
	if inserted >= required:
		return
	inserted += 1
	_update_ui()
	progress_changed.emit(inserted, required)
	if inserted >= required and !done:
		done = true
		completed.emit()
		_fade_out()

# ---------- HUD (one shared counter) ----------
func _build_ui() -> void:
	shared_layer = CanvasLayer.new()
	shared_layer.layer = 2
	add_child(shared_layer)
	shared_label = Label.new()
	shared_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shared_label.add_theme_font_size_override("font_size", 34)
	shared_label.add_theme_color_override("font_outline_color", Color.BLACK)
	shared_label.add_theme_constant_override("outline_size", 8)
	shared_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shared_layer.add_child(shared_label)
	shared_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	shared_label.offset_top = 70 # just under the round timer

func _update_ui() -> void:
	if !is_instance_valid(shared_label):
		return
	shared_label.text = "%d/%d" % [inserted, required]
	if inserted >= required:
		shared_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))

func _process(_delta:float) -> void:
	# Survivors only: the monster never sees the counter
	if !is_instance_valid(shared_layer) or shared_layer.get_parent() != self:
		return
	if !is_instance_valid(local_player):
		local_player = get_tree().current_scene.find_child(str(GDSync.get_client_id()), true, false) as player
	shared_layer.visible = !(is_instance_valid(local_player) and local_player.monster)

func _fade_out() -> void:
	if !is_instance_valid(shared_label):
		return
	var tw := shared_label.create_tween()
	tw.tween_interval(fade_delay)
	tw.tween_property(shared_label, "modulate:a", 0.0, fade_time).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(shared_label.hide)
