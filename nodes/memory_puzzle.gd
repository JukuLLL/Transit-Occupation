class_name MemoryPuzzle extends PuzzleBase

const BUTTON_COUNT := 17
const TARGET_COUNT := 6
const ROUNDS_NEEDED := 2
const ALL_MASK := (1 << BUTTON_COUNT) - 1

const WHITE := Color(1, 1, 1)
const OFF := Color(0.14, 0.14, 0.14)

@export var spacing := 0.30
@export var demo_count := 8
@export var demo_time := 0.5
@export var demo_gap := 0.3
@export var target_time := 0.45
@export var target_gap := 0.3
@export var intro_pause := 0.6
@export var transition_pause := 0.5
@export var fail_restart_delay := 0.8
@export var success_delay := 0.6

@export var board_yaw := 90.0                    # turns the board to face +X like your screen
@export var board_scale := 1.0
@export var board_offset := Vector3(0.045, 0.0, 0.0)

var board:Node3D
var mats:Array[StandardMaterial3D] = []
var lamp_mats:Array[StandardMaterial3D] = []
var run_id := 0
var accepting := false
var outcome := 0 # 0 waiting, 1 failed, 2 round completed
var target_mask := 0
var selected_mask := 0
var rounds_done := 0

func _ready() -> void:
	super() # keep: sets up claiming and the host-confirmed finish
	GDSync.expose_func(_show_lights)
	GDSync.expose_func(_show_rounds)
	_build_board()
	power_changed.connect(_on_power_changed)
	puzzle_finished.connect(_on_finished_local)
	_apply(0)

func _i_am_worker() -> bool:
	return worker != 0 and worker == GDSync.get_client_id()

# ---------------------------------------------------------------- building
func _build_board() -> void:
	board = Node3D.new()
	board.rotation_degrees.y = board_yaw
	board.scale = Vector3.ONE * board_scale
	board.position = board_offset
	add_child(board)
	
	var rows := [3, 4, 3, 4, 3] # 17 buttons
	var idx := 0
	for r in rows.size():
		var n:int = rows[r]
		for c in n:
			_make_button(idx, Vector3((c - (n - 1) / 2.0) * spacing, ((rows.size() - 1) / 2.0 - r) * spacing, 0.03))
			idx += 1
	
	# Two small lamps above the grid show completed rounds
	for i in ROUNDS_NEEDED:
		var lamp := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.05
		sph.height = 0.1
		lamp.mesh = sph
		var lm := _unshaded(OFF)
		lamp.material_override = lm
		lamp.position = Vector3((i - (ROUNDS_NEEDED - 1) / 2.0) * 0.2, 0.84, 0.03)
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
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.12
	cyl.height = 0.06
	mesh.mesh = cyl
	mesh.rotation_degrees.x = 90
	var mat := _unshaded(OFF)
	mesh.material_override = mat
	b.add_child(mesh)
	mats.append(mat)
	
	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.14
	cs.height = 0.1
	col.shape = cs
	col.rotation_degrees.x = 90
	b.add_child(col)

# ---------------------------------------------------------------- session
func _on_power_changed(powered:bool) -> void:
	run_id += 1 # aborts any round that is running
	accepting = false
	selected_mask = 0
	if finished:
		return
	_apply(0)
	if powered and _i_am_worker():
		_run_session(run_id)

func _run_session(token:int) -> void:
	while rounds_done < ROUNDS_NEEDED:
		if !await _play_round(token):
			return
	finish_puzzle() # the host confirms, then every client finishes together

func _wait(t:float, token:int) -> bool:
	await get_tree().create_timer(t).timeout
	return token == run_id and _i_am_worker() and !finished

# One round. A wrong press restarts it with a brand new pattern.
func _play_round(token:int) -> bool:
	while true:
		selected_mask = 0
		accepting = false
		target_mask = _random_mask(TARGET_COUNT)
		if !await _wait(intro_pause, token): return false
		
		# Earlier patterns, never equal to the target: ignore these.
		# Each pattern replaces the previous one directly, with no dark pause between them.
		var last := 0
		for i in demo_count:
			last = _demo_mask(target_mask, last)
			_lights(last)
			if !await _wait(demo_time, token): return false
		
		# Short dark pause before the real pattern (no all-buttons flash)
		_lights(0)
		if !await _wait(transition_pause, token): return false
		
		# The final pattern, shown three times quickly, identical each time
		for i in 3:
			_lights(target_mask)
			if !await _wait(target_time, token): return false
			_lights(0)
			if !await _wait(target_gap, token): return false
		
		# Player repeats it
		outcome = 0
		accepting = true
		while outcome == 0:
			await get_tree().process_frame
			if token != run_id or !_i_am_worker():
				return false
		
		if outcome == 1:
			if !await _play_fail(token): return false
			continue
		
		if !await _play_success(token): return false
		rounds_done += 1
		GDSync.call_func_all(_show_rounds, rounds_done)
		return true
	return false

func _on_button_pressed(path:NodePath, index:int) -> void:
	if !accepting or finished or !is_worker(path):
		return
	if !Input.is_action_just_pressed("left_click"):
		return # sweeping over buttons with the mouse held does not count
	var bit := 1 << index
	if selected_mask & bit:
		return # no undo
	if target_mask & bit:
		selected_mask |= bit
		_lights(selected_mask) # correct buttons stay lit
		if selected_mask == target_mask:
			accepting = false
			outcome = 2
	else:
		accepting = false # one wrong button fails immediately
		outcome = 1

func _play_fail(token:int) -> bool:
	for i in 3:
		_lights(ALL_MASK) # the correct pattern is never shown
		if !await _wait(0.15, token): return false
		_lights(0)
		if !await _wait(0.1, token): return false
	return await _wait(fail_restart_delay, token)

func _play_success(token:int) -> bool:
	for i in 2:
		_lights(ALL_MASK)
		if !await _wait(0.2, token): return false
		_lights(0)
		if !await _wait(0.15, token): return false
	return await _wait(success_delay, token)

func _on_finished_local() -> void:
	run_id += 1
	accepting = false
	_show_rounds(ROUNDS_NEEDED)
	_apply(ALL_MASK) # the solved board stays lit

# ---------------------------------------------------------------- patterns
func _random_mask(count:int) -> int:
	var idxs:Array = range(BUTTON_COUNT)
	idxs.shuffle()
	var m := 0
	for i in count:
		m |= 1 << int(idxs[i])
	return m

func _demo_mask(avoid_a:int, avoid_b:int) -> int:
	var sizes := [4, 5, 6, 7, 8]
	var m := 0
	while m == 0 or m == avoid_a or m == avoid_b:
		m = _random_mask(sizes.pick_random())
	return m

# ---------------------------------------------------------------- sync (runs on every client)
func _lights(mask:int) -> void:
	GDSync.call_func_all(_show_lights, mask)

func _show_lights(mask:int) -> void:
	_apply(mask)

func _apply(mask:int) -> void:
	for i in mats.size():
		mats[i].albedo_color = WHITE if ((mask >> i) & 1) == 1 else OFF

func _show_rounds(n:int) -> void:
	rounds_done = n
	for i in lamp_mats.size():
		lamp_mats[i].albedo_color = WHITE if i < n else OFF
