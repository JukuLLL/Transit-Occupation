class_name ReactionPuzzle extends PuzzleBase

const BUTTON_COUNT := 6
const HITS_NEEDED := 16
const ALL_MASK := (1 << BUTTON_COUNT) - 1

const WHITE := Color(1, 1, 1)
const OFF := Color(0.14, 0.14, 0.14)

@export var reaction_time := 1.5      # seconds you have to press the lit button
@export var light_delay := 0.4        # dark pause before the next button lights
@export var intro_pause := 0.8
@export var reset_on_fail := true
@export var fail_pause := 0.8
@export var spacing := 0.42

@export var board_yaw := 90.0                    # turns the board to face +X like your screen
@export var board_scale := 1.0
@export var board_offset := Vector3(0.045, 0.0, 0.0)

var board:Node3D
var mats:Array[StandardMaterial3D] = []
var lamp_mats:Array[StandardMaterial3D] = []
var run_id := 0
var accepting := false
var lit := -1
var pressed := -1
var hits := 0

func _ready() -> void:
	super() # keep: sets up claiming and the host-confirmed finish
	GDSync.expose_func(_show_state)
	_build_board()
	power_changed.connect(_on_power_changed)
	puzzle_finished.connect(_on_finished_local)
	_apply(0, 0)

func _i_am_worker() -> bool:
	return worker != 0 and worker == GDSync.get_client_id()

# ---------------------------------------------------------------- building
func _build_board() -> void:
	board = Node3D.new()
	board.rotation_degrees.y = board_yaw
	board.scale = Vector3.ONE * board_scale
	board.position = board_offset
	add_child(board)
	
	# 6 buttons in a 3 x 2 grid
	for i in BUTTON_COUNT:
		var c := i % 3
		var r := i / 3
		_make_button(i, Vector3((c - 1) * spacing, (0.5 - r) * spacing - 0.1, 0.03))
	
	# 16 small lamps show your progress
	for i in HITS_NEEDED:
		var lamp := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.035
		sph.height = 0.07
		lamp.mesh = sph
		var lm := _unshaded(OFF)
		lamp.material_override = lm
		lamp.position = Vector3((i - (HITS_NEEDED - 1) / 2.0) * 0.1, 0.65, 0.03)
		board.add_child(lamp)
		lamp_mats.append(lm)

func _unshaded(color:Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m

func _make_button(index:int, pos:Vector3) -> void:
	var b := interactable.new()
	b.synced = false # presses are handled on the presser's own machine
	b.position = pos
	board.add_child(b)
	b.interacting.connect(_on_button_pressed.bind(index))
	
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.15
	cyl.height = 0.06
	mesh.mesh = cyl
	mesh.rotation_degrees.x = 90
	var mat := _unshaded(OFF)
	mesh.material_override = mat
	b.add_child(mesh)
	mats.append(mat)
	
	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.17
	cs.height = 0.1
	col.shape = cs
	col.rotation_degrees.x = 90
	b.add_child(col)

# ---------------------------------------------------------------- session
func _on_power_changed(powered:bool) -> void:
	run_id += 1 # aborts the running session
	accepting = false
	lit = -1
	if finished:
		return
	hits = 0
	_apply(0, 0)
	if powered and _i_am_worker():
		_run_session(run_id)

func _wait(t:float, token:int) -> bool:
	await get_tree().create_timer(t).timeout
	return token == run_id and _i_am_worker() and !finished

func _run_session(token:int) -> void:
	hits = 0
	_show(0, 0)
	if !await _wait(intro_pause, token): return
	var last := -1
	while hits < HITS_NEEDED:
		# Wait a moment, then light a random button (never the same one twice in a row)
		if !await _wait(light_delay, token): return
		var next := randi() % BUTTON_COUNT
		while next == last:
			next = randi() % BUTTON_COUNT
		last = next
		lit = next
		pressed = -1
		_show(1 << lit, hits)
		accepting = true
		var start := Time.get_ticks_msec()
		
		# Wait for a press or the time limit
		while pressed == -1 and Time.get_ticks_msec() - start < int(reaction_time * 1000.0):
			await get_tree().process_frame
			if token != run_id or !_i_am_worker() or finished:
				return
		accepting = false
		
		if pressed == lit:
			hits += 1
			_show(0, hits)
		else:
			# Wrong button or too slow
			if reset_on_fail:
				hits = 0
			for i in 2:
				_show(ALL_MASK, hits)
				if !await _wait(0.15, token): return
				_show(0, hits)
				if !await _wait(0.1, token): return
			if !await _wait(fail_pause, token): return
	lit = -1
	finish_puzzle() # the host confirms, then every client finishes together

func _on_button_pressed(path:NodePath, index:int) -> void:
	if !accepting or finished or !is_worker(path):
		return
	if !Input.is_action_just_pressed("left_click"):
		return # sweeping over buttons with the mouse held does not count
	pressed = index

func _on_finished_local() -> void:
	run_id += 1
	accepting = false
	_apply(ALL_MASK, HITS_NEEDED) # the solved board stays lit

# ---------------------------------------------------------------- sync (runs on every client)
func _show(mask:int, h:int) -> void:
	GDSync.call_func_all(_show_state, mask, h)

func _show_state(mask:int, h:int) -> void:
	if finished:
		return
	_apply(mask, h)

func _apply(mask:int, h:int) -> void:
	for i in mats.size():
		mats[i].albedo_color = WHITE if ((mask >> i) & 1) == 1 else OFF
	for i in lamp_mats.size():
		lamp_mats[i].albedo_color = WHITE if i < h else OFF
