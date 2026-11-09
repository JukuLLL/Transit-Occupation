class_name ResearchStation extends Node3D

signal objective_started
signal objective_completed

@export var pipe:Node3D
@export var travel := 3.0                 # how far the pipe starts above its final position (m)
# Progress per second, indexed by number of pullers (0 to 4): 125 s, 50 s, 28 s, 17 s
@export var rates:Array[float] = [0.0, 0.008, 0.02, 0.036, 0.06]
@export var accel := 0.05                 # how quickly the rate rises
@export var decel := 0.4                  # how quickly it falls when pulling stops
@export var objective_text := "Pull down the pipe."
@export var text_fade_in := 1.2

var poles:Array[PuzzleBase] = []
var final_pos := Vector3.ZERO
var started := false
var active := false
var done := false
var finishing := false # host only
var progress := 0.0
var net_progress := 0.0
var rate_now := 0.0
var send_cd := 0.0
var last_sent := -1.0
var layer:CanvasLayer
var label:Label
var local_player:player

func _ready() -> void:
	GDSync.expose_func(_net_progress_set)
	GDSync.expose_func(_complete)
	for n in pipe.find_children("*", "", true, false):
		if n is PuzzleBase:
			poles.append(n)
	for p in poles:
		p.finished = true # locked until the objective starts
	final_pos = pipe.position # place the pipe in its connected position in the editor
	_apply_pipe()
	_build_ui()
	# Wait a frame so the chambers exist, then listen for 6/6
	await get_tree().process_frame
	for c in get_tree().get_nodes_in_group("algorithm_chamber"):
		c.completed.connect(_on_chamber_done.bind(c))

# ---------- Objective start ----------
func _on_chamber_done(c) -> void:
	if started:
		return
	started = true
	# Wait until the 6/6 counter has completely faded
	await get_tree().create_timer(c.fade_delay + c.fade_time + 0.4).timeout
	for p in poles:
		p.finished = false
	active = true
	label.text = objective_text
	label.add_theme_color_override("font_color", Color.WHITE)
	label.modulate.a = 0.0
	label.show()
	create_tween().tween_property(label, "modulate:a", 1.0, text_fade_in).set_trans(Tween.TRANS_SINE)
	objective_started.emit()

# ---------- Movement ----------
func _physics_process(delta:float) -> void:
	if !done:
		if GDSync.is_host():
			_host_step(delta)
		else:
			progress = lerpf(progress, net_progress, 1.0 - exp(-12.0 * delta))
	_apply_pipe()

func _host_step(delta:float) -> void:
	if !active or Network.round_over:
		return
	var count := 0
	for p in poles:
		if p.worker != 0:
			count += 1
	var target:float = rates[mini(count, rates.size() - 1)]
	var a := accel if target > rate_now else decel
	rate_now = move_toward(rate_now, target, a * delta)
	progress = minf(progress + rate_now * delta, 1.0)
	
	send_cd -= delta
	if send_cd <= 0.0 and progress != last_sent:
		send_cd = 0.1
		last_sent = progress
		GDSync.call_func_all(_net_progress_set, progress)
	if progress >= 1.0 and !finishing:
		finishing = true
		GDSync.call_func_all(_complete)

func _apply_pipe() -> void:
	pipe.position = final_pos + Vector3.UP * travel * (1.0 - progress)

func _net_progress_set(value:float) -> void:
	if GDSync.is_host():
		return
	net_progress = value

# ---------- Completion (every client) ----------
func _complete() -> void:
	if done:
		return
	done = true
	active = false
	progress = 1.0
	net_progress = 1.0
	for p in poles:
		p.finished = true # ends the pulling interaction
	_apply_pipe()
	label.text = "Pipe connected."
	label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(label, "modulate:a", 0.0, 1.5).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(label.hide)
	objective_completed.emit()

# ---------- Objective text ----------
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
	label.hide()
	layer.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = 70 # same spot as the 6/6 counter

func _process(_delta:float) -> void:
	# Survivors only
	if !is_instance_valid(local_player):
		local_player = get_tree().current_scene.find_child(str(GDSync.get_client_id()), true, false) as player
	layer.visible = !(is_instance_valid(local_player) and local_player.monster)
