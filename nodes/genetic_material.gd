class_name GeneticMaterial extends RigidBody3D

@export var carry_offset := Vector3(0, 0.8, -1.8) # relative to the carrier, forward is -Z
@export var follow_speed := 20.0
@export var send_rate := 15.0
@export var max_grab_distance := 5.0

var consumed := false # set by the chamber so one cube can only be inserted once
var carrier_id := 0
var dropping := false
var send_cd := 0.0
var last_pos := Vector3.INF
var last_basis := Basis()
var net_pos := Vector3.ZERO
var net_basis := Basis()
var has_net := false

func _ready() -> void:
	process_physics_priority = 100 # run after the players have moved this tick
	add_to_group("genetic_material")
	for c in [_host_grab, _host_drop, _set_carrier, _net_state]:
		GDSync.expose_func(c)
	if !GDSync.is_host():
		# Only the host simulates; everyone else follows the host's state
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
	for p in get_tree().get_nodes_in_group("plr"):
		add_collision_exception_with(p)
		
func _ignore_all_players() -> void:
	for n in get_tree().current_scene.find_children("*", "CharacterBody3D", true, false):
		if n is player:
			add_collision_exception_with(n)
			
func _carry_target(p:player) -> Transform3D:
	var pos := p.global_position + p.global_transform.basis * carry_offset
	return Transform3D(Basis.from_euler(Vector3(0.0, p.global_rotation.y, 0.0)), pos)

func _i_am_carrier() -> bool:
	return carrier_id != 0 and carrier_id == GDSync.get_client_id()

func _find_player(id:int) -> player:
	if id == 0:
		return null
	return get_tree().current_scene.find_child(str(id), true, false) as player

func _to_host(c:Callable, id:int) -> void:
	if GDSync.is_host():
		c.call(id)
	else:
		GDSync.call_func_on(GDSync.get_host(), c, id)

# ---- called from the player ----
func request_grab() -> void:
	_to_host(_host_grab, GDSync.get_client_id())

func request_drop() -> void:
	_to_host(_host_drop, GDSync.get_client_id())

# ---- host decisions ----
func _host_grab(id:int) -> void:
	if !GDSync.is_host() or carrier_id != 0:
		return
	var p := _find_player(id)
	if p == null or p.monster or p.downed or p.trapped or p.dead or p.escaped:
		return
	if p.global_position.distance_to(global_position) > max_grab_distance:
		return
	GDSync.call_func_all(_set_carrier, id)

func _host_drop(id:int) -> void:
	if !GDSync.is_host() or carrier_id != id:
		return
	GDSync.call_func_all(_set_carrier, 0)

# ---- every client ----
func _set_carrier(id:int) -> void:
	var old := _find_player(carrier_id)
	if old != null:
		old.carried_item = null
	carrier_id = id
	dropping = false
	var p := _find_player(id)
	if p != null:
		p.carried_item = self
		add_collision_exception_with(p) # the cube never collides with its carrier
	if GDSync.is_host():
		if p != null:
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			freeze = true
		else:
			freeze = false
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			sleeping = false

func _net_state(pos:Vector3, basis_in:Basis) -> void:
	if GDSync.is_host():
		return
	net_pos = pos
	net_basis = basis_in
	has_net = true

func _physics_process(delta:float) -> void:
	if Engine.get_physics_frames() % 60 == 0:
		_ignore_all_players()
		
	# The carrier places the cube locally, so it never lags behind their own movement
	if _i_am_carrier():
		var me := _find_player(carrier_id)
		if me != null:
			global_transform = _carry_target(me)
		if GDSync.is_host():
			_host_step(delta)
		return
	if GDSync.is_host():
		_host_step(delta)
	elif has_net:
		var t := clampf(delta * 25.0, 0.0, 1.0)
		global_position = global_position.lerp(net_pos, t)
		global_basis = global_basis.slerp(net_basis, t)

func _host_step(delta:float) -> void:
	if carrier_id != 0:
		var p := _find_player(carrier_id)
		if p == null or p.downed or p.trapped or p.dead or Network.round_over:
			if !dropping:
				dropping = true
				GDSync.call_func_all(_set_carrier, 0)
		else:
			var tf := _carry_target(p)
			if GDSync.get_client_id() == carrier_id:
				global_transform = tf # the host is the carrier: no smoothing
			else:
				global_position = global_position.lerp(tf.origin, clampf(follow_speed * delta, 0.0, 1.0))
				global_basis = tf.basis
	
	send_cd -= delta
	if send_cd <= 0.0:
		send_cd = 1.0 / send_rate
		if global_position.distance_to(last_pos) > 0.002 or !global_basis.is_equal_approx(last_basis):
			last_pos = global_position
			last_basis = global_basis
			GDSync.call_func_all(_net_state, global_position, global_basis)
