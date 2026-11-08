class_name VisionPuzzle extends PuzzleBase

@export var timer: Timer
@export var lose: Timer
@export var held_for:float = 5
@export var spots: Node3D
@export var vision: Decal
@export var progress: Label3D
@export var range_x:float = 0.5
@export var range_y:float = 0.5

var times:float = 0
var lerper:float = 0.0
var current_pos := Vector3.ZERO
var lerp_start := Vector3.ZERO
var start_vision_pos := Vector3.ZERO
var last_held := 0
var sync_cd := 0.0

func _ready() -> void:
	super() # exposes the node and runs the base setup
	start_vision_pos = vision.position
	power_changed.connect(_on_power_changed)
	GDSync.expose_func(_show_state)

func _process(_delta: float) -> void:
	progress.text = str(times)

func _i_am_worker() -> bool:
	return worker != 0 and worker == GDSync.get_client_id()

# ---- runs only on the machine of the player holding this side ----
func _on_interactable_interacting_held(player_node_path: NodePath) -> void:
	print("held, worker=", worker, " me=", GDSync.get_client_id())
	if finished or !is_worker(player_node_path):
		return
	last_held = Time.get_ticks_msec()
	if timer.is_stopped():
		timer.start()
		lose.start()
		_retarget()
	lerper = clampf(lerper + 0.01, 0.0, 1.0)
	vision.position = lerp(lerp_start, current_pos, lerper)
	sync_cd -= get_physics_process_delta_time()
	if sync_cd <= 0.0: # share the decal position about 10 times a second
		sync_cd = 0.1
		GDSync.call_func_all(_show_state, vision.position, times)

func _retarget() -> void:
	lerp_start = vision.position
	current_pos = start_vision_pos + Vector3(0, randf_range(-range_y, range_y), randf_range(-range_x, range_x))
	lerper = 0.0

func _on_timer_timeout() -> void:
	if finished or !_i_am_worker():
		timer.stop()
		return
	# Looking away from the decal stops the hold signals, so reset
	if Time.get_ticks_msec() - last_held > 300:
		_reset_progress()
		return
	times += 1
	GDSync.call_func_all(_show_state, vision.position, times)
	if times >= held_for:
		timer.stop()
		lose.stop()
		finish_puzzle()

func _on_lose_timeout() -> void:
	if finished or !_i_am_worker():
		return
	times = 0
	_retarget()
	GDSync.call_func_all(_show_state, vision.position, times)

func _on_interactable_interest_lost() -> void:
	if !finished and _i_am_worker():
		_reset_progress()

func _reset_progress() -> void:
	timer.stop()
	lose.stop()
	times = 0
	lerper = 0.0
	GDSync.call_func_all(_show_state, vision.position, 0.0)

# ---- runs on every client ----
func _show_state(pos:Vector3, t:float) -> void:
	times = t
	if !_i_am_worker():
		create_tween().tween_property(vision, "position", pos, 0.1)

func _on_power_changed(powered:bool) -> void:
	if !powered and !finished:
		timer.stop()
		lose.stop()
		times = 0
		lerper = 0.0
		vision.position = start_vision_pos
