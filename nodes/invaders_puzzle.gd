class_name InvadersPuzzle extends PuzzleBase

const FIELD_HALF_W := 1.1
const SHIP_Y := -1.0
const SHIP_SPEED := 0.9
const SHIP_RADIUS := 0.08
const PLAYER_BULLET_SPEED := 1.8
const ENEMY_BULLET_SPEED := 0.55
const TOP_Y := 1.25
const SEND_RATE := 15.0

const WHITE := Color(1, 1, 1)
const DIM := Color(0.45, 0.45, 0.45) # ship color while it is hit

# [count, y, radius, spacing]: 3 big at the back, 5 medium, 6 small in front
const ROWS := [
	[3, 0.95, 0.16, 0.55],
	[5, 0.65, 0.12, 0.40],
	[6, 0.35, 0.09, 0.30],
]

@export var shoot_cooldown := 1.5
@export var enemy_fire_min := 1.0
@export var enemy_fire_max := 15.0
@export var sway_amount := 0.25
@export var sway_speed := 0.9
@export var fail_delay := 1.0

@export var board_yaw := 90.0                          # turns the game to face +X like your screen
@export var board_scale := 0.62                        # 2.9 tall game x 0.62 = about 1.8, fits 1.883
@export var board_offset := Vector3(0.045, 0.12, 0.0)  # just in front of the screen, recentered

var board:Node3D
var field:Node3D
var ship_mesh:MeshInstance3D
var shoot_mat:StandardMaterial3D
var e_mesh:Array[MeshInstance3D] = []
var e_base:Array[Vector2] = []
var e_r:Array[float] = []
var e_timer:Array[float] = []
var e_alive:Array[bool] = []
var pb_pool:Array = []
var eb_pool:Array = []

# game state (the worker simulates it, everyone else receives it)
var ship_x := 0.0
var fx := 0.0
var cd := 0.0
var pb := PackedVector2Array()
var eb := PackedVector2Array()
var flash := false
var done := false

# worker only
var running := false
var t := 0.0
var fail_left := 0.0
var left_t := -10000
var right_t := -10000
var send_cd := 0.0

func _ready() -> void:
	super() 
	GDSync.expose_func(_show_state)
	_build_board()
	power_changed.connect(_on_power_changed)
	puzzle_finished.connect(_on_finished_local)
	_reset_local()

func _i_am_worker() -> bool:
	return worker != 0 and worker == GDSync.get_client_id()

func _build_board() -> void:
	board = Node3D.new()
	board.rotation_degrees.y = board_yaw
	board.scale = Vector3.ONE * board_scale
	board.position = board_offset
	add_child(board)
	
	field = Node3D.new()
	field.position = Vector3(0, 0, 0.03)
	board.add_child(field)
	
	ship_mesh = _blob(0.1, WHITE)
	field.add_child(ship_mesh)
	
	for row in ROWS:
		var n:int = row[0]
		for i in n:
			var m := _blob(row[2], WHITE)
			field.add_child(m)
			e_mesh.append(m)
			e_base.append(Vector2((i - (n - 1) / 2.0) * row[3], row[1]))
			e_r.append(row[2])
			e_timer.append(0.0)
			e_alive.append(true)
	
	_make_button(-0.55, "<", 1)
	_make_button(0.0, "", 0) # fire button, no text
	_make_button(0.55, ">", 2)

func _blob(radius:float, color:Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	m.mesh = s
	m.scale = Vector3(1, 1, 0.3)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	m.material_override = mat
	return m

func _make_button(x:float, text:String, kind:int) -> void:
	var b := interactable.new()
	b.synced = false 
	b.hold = kind != 0 
	b.position = Vector3(x, -1.45, 0.03)
	board.add_child(b)
	if kind == 0:
		b.interacting.connect(_on_shoot)
	else:
		b.interacting_held.connect(_on_move.bind(-1 if kind == 1 else 1))
	
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.17
	cyl.bottom_radius = 0.17
	cyl.height = 0.08
	mesh.mesh = cyl
	mesh.rotation_degrees.x = 90
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = WHITE
	mesh.material_override = mat
	b.add_child(mesh)
	if kind == 0:
		shoot_mat = mat
	
	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.19
	cs.height = 0.12
	col.shape = cs
	col.rotation_degrees.x = 90
	b.add_child(col)
	
	if text != "":
		var l := Label3D.new()
		l.text = text
		l.font_size = 48
		l.pixel_size = 0.004
		l.modulate = Color(0, 0, 0) # dark text so it reads on the white button
		l.position = Vector3(0, 0, 0.05)
		l.no_depth_test = true
		b.add_child(l)

func _on_move(path:NodePath, dir:int) -> void:
	if !running or !is_worker(path):
		return
	if dir < 0:
		left_t = Time.get_ticks_msec()
	else:
		right_t = Time.get_ticks_msec()

func _on_shoot(path:NodePath) -> void:
	if !running or finished or fail_left > 0.0 or cd > 0.0 or !is_worker(path):
		return
	if !Input.is_action_just_pressed("left_click"):
		return 
	cd = shoot_cooldown
	pb.append(Vector2(ship_x, SHIP_Y + 0.12))

func _on_power_changed(powered:bool) -> void:
	running = false
	if finished:
		return
	_reset_local() 
	if powered and _i_am_worker():
		running = true

func _reset_local() -> void:
	t = 0.0
	ship_x = 0.0
	fx = 0.0
	cd = 0.0
	fail_left = 0.0
	flash = false
	pb = PackedVector2Array()
	eb = PackedVector2Array()
	for i in e_alive.size():
		e_alive[i] = true
		e_timer[i] = randf_range(enemy_fire_min, enemy_fire_max)
	_render()

func _on_finished_local() -> void:
	running = false
	done = true
	for i in e_alive.size():
		e_alive[i] = false
	pb = PackedVector2Array()
	eb = PackedVector2Array()
	_render()

func _physics_process(delta:float) -> void:
	if !running or finished or !_i_am_worker():
		return
	
	if fail_left > 0.0:
		fail_left -= delta
		if fail_left <= 0.0:
			_reset_local() 
		_broadcast(delta)
		_render()
		return
	
	t += delta
	fx = sin(t * sway_speed) * sway_amount
	
	var now := Time.get_ticks_msec()
	var dir := 0
	if now - left_t < 120: dir -= 1
	if now - right_t < 120: dir += 1
	ship_x = clampf(ship_x + dir * SHIP_SPEED * delta, -FIELD_HALF_W, FIELD_HALF_W)
	cd = maxf(cd - delta, 0.0)
	

	for i in e_alive.size():
		if !e_alive[i]:
			continue
		e_timer[i] -= delta
		if e_timer[i] <= 0.0:
			e_timer[i] = randf_range(enemy_fire_min, enemy_fire_max)
			eb.append(e_base[i] + Vector2(fx, -0.08))
	
	var new_pb := PackedVector2Array()
	for p in pb:
		p.y += PLAYER_BULLET_SPEED * delta
		var hit := false
		for i in e_alive.size():
			if e_alive[i] and p.distance_to(e_base[i] + Vector2(fx, 0)) < e_r[i] + 0.04:
				e_alive[i] = false
				hit = true
				break
		if !hit and p.y < TOP_Y:
			new_pb.append(p)
	pb = new_pb
	
	var new_eb := PackedVector2Array()
	var got_hit := false
	for p in eb:
		p.y -= ENEMY_BULLET_SPEED * delta
		if absf(p.x - ship_x) < SHIP_RADIUS + 0.03 and absf(p.y - SHIP_Y) < SHIP_RADIUS + 0.03:
			got_hit = true
		elif p.y > SHIP_Y - 0.3:
			new_eb.append(p)
	eb = new_eb
	
	if got_hit:
		fail_left = fail_delay
	
	var alive := false
	for a in e_alive:
		if a:
			alive = true
			break
	if !alive:
		running = false
		_broadcast(delta, true)
		finish_puzzle() 
		return
	
	_broadcast(delta)
	_render()

func _broadcast(delta:float, force := false) -> void:
	send_cd -= delta
	if send_cd > 0.0 and !force:
		return
	send_cd = 1.0 / SEND_RATE
	var mask := 0
	for i in e_alive.size():
		if e_alive[i]:
			mask |= 1 << i
	GDSync.call_func_all(_show_state, ship_x, fx, mask, pb, eb, cd, fail_left > 0.0)

func _show_state(sx:float, f:float, mask:int, pbs:PackedVector2Array, ebs:PackedVector2Array, c:float, fl:bool) -> void:
	if _i_am_worker() or done:
		return 
	ship_x = sx
	fx = f
	pb = pbs
	eb = ebs
	cd = c
	flash = fl
	for i in e_alive.size():
		e_alive[i] = ((mask >> i) & 1) == 1
	_render()

func _render() -> void:
	if field == null:
		return
	var flashing := fail_left > 0.0 or flash
	(ship_mesh.material_override as StandardMaterial3D).albedo_color = DIM if flashing else WHITE
	ship_mesh.position = Vector3(ship_x, SHIP_Y, 0)
	for i in e_mesh.size():
		e_mesh[i].visible = e_alive[i]
		e_mesh[i].position = Vector3(e_base[i].x + fx, e_base[i].y, 0)
	_fit_pool(pb_pool, pb.size(), 0.035)
	_fit_pool(eb_pool, eb.size(), 0.04)
	for i in pb.size():
		pb_pool[i].position = Vector3(pb[i].x, pb[i].y, 0)
	for i in eb.size():
		eb_pool[i].position = Vector3(eb[i].x, eb[i].y, 0)
	if shoot_mat != null:
		shoot_mat.albedo_color = WHITE if (cd <= 0.0 and !done) else DIM

func _fit_pool(pool:Array, count:int, radius:float) -> void:
	while pool.size() < count:
		var m := _blob(radius, WHITE)
		field.add_child(m)
		pool.append(m)
	for i in pool.size():
		pool[i].visible = i < count
