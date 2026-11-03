class_name MonsterKit extends Node

@export var disable_sprint := true

var plr:player
var client_id := 0
var is_local := false
var ready_done := false

func _ready() -> void:
	GDSync.expose_node(self)
	plr = get_parent() as player
	await get_tree().physics_frame # the player's name is assigned right after add_child
	client_id = plr.name.to_int()
	is_local = client_id == GDSync.get_client_id()
	_expose()
	if is_local:
		_setup_local()
	ready_done = true

# ---- hooks a monster overrides ----
func _expose() -> void: pass
func _setup_local() -> void: pass
func tick(_delta:float) -> void: pass         # owner only, every physics frame
func before_slide(_delta:float) -> void: pass # owner only, right before move_and_slide
func after_slide(_delta:float) -> void: pass  # owner only, right after move_and_slide
func speed_multiplier() -> float: return 1.0

# ---- helpers ----
func survivors() -> Array[player]:
	var out:Array[player] = []
	for n in plr.get_parent().get_children():
		var p := n as player
		if p != null and p != plr and !p.monster:
			out.append(p)
	return out

func can_target(p:player, allow_downed := false) -> bool:
	if p.monster or p.dead or p.trapped or p.escaped or p.picked_up:
		return false
	return allow_downed or !p.downed

func _line_clear(from:Vector3, to:Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var ex:Array[RID] = [plr.get_rid()]
	for p in survivors():
		ex.append(p.get_rid())
	q.exclude = ex
	return plr.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _call_on(id:int, c:Callable, args:Array = []) -> void:
	if id == GDSync.get_client_id():
		c.callv(args)
		return
	match args.size():
		0: GDSync.call_func_on(id, c)
		1: GDSync.call_func_on(id, c, args[0])
		2: GDSync.call_func_on(id, c, args[0], args[1])
		3: GDSync.call_func_on(id, c, args[0], args[1], args[2])
		4: GDSync.call_func_on(id, c, args[0], args[1], args[2], args[3])

func _call_all(c:Callable, args:Array = []) -> void:
	match args.size():
		0: GDSync.call_func_all(c)
		1: GDSync.call_func_all(c, args[0])
		2: GDSync.call_func_all(c, args[0], args[1])
		3: GDSync.call_func_all(c, args[0], args[1], args[2])

func _call_host(c:Callable, args:Array = []) -> void:
	_call_on(GDSync.get_host(), c, args)
