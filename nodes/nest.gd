class_name Nest extends Area3D

@export var life_interval := 30.0
@export var rescue_time := 7.0
@export var rescue_distance := 4.0

var occupant:player
var time_left := 0.0 # display countdown on every client, the host decides when a life is lost
var label:Label3D

func _ready() -> void:
	add_to_group("nest")
	GDSync.expose_func(sync_trap)
	GDSync.expose_func(sync_lose_life)
	GDSync.expose_func(sync_rescue)
	GDSync.expose_func(host_request_rescue)
	
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.01
	label.outline_size = 8
	label.position = Vector3(0, 2.2, 0)
	label.visible = false
	add_child(label)

func spot_position() -> Vector3:
	return global_position + Vector3.UP * 1.0

func exit_position() -> Vector3:
	return global_position + global_transform.basis.z * 2.5 + Vector3.UP * 0.5

func can_be_rescued_by(p:player) -> bool:
	return is_instance_valid(occupant) and occupant != p and occupant.trapped \
		and !occupant.dead and !p.monster \
		and global_position.distance_to(p.global_position) <= rescue_distance

func _physics_process(delta:float) -> void:
	if occupant != null and !is_instance_valid(occupant):
		occupant = null # the player left the game
	
	if occupant != null:
		time_left = maxf(time_left - delta, 0.0)
		if GDSync.is_host() and time_left <= 0.0:
			time_left = life_interval
			GDSync.call_func_all(sync_lose_life)
	elif GDSync.is_host():
		# A carried, downed player inside the nest gets trapped
		for body in get_overlapping_bodies():
			var plr := body as player
			if plr != null and plr.downed and plr.picked_up and !plr.trapped and !plr.dead:
				GDSync.call_func_all(sync_trap, plr.get_path())
				break

func _process(_delta:float) -> void:
	if !is_instance_valid(occupant):
		label.visible = false
		return
	var pname := str(GDSync.player_get_username(occupant.name.to_int()))
	if pname == "":
		pname = "Player"
	label.visible = true
	label.text = "%s\nLives: %d\n%ds" % [pname, occupant.lives, ceili(time_left)]

# Runs on every client
func sync_trap(plr_path:NodePath) -> void:
	print("sync_trap: ", plr_path)
	var plr := get_node_or_null(plr_path) as player
	if plr == null or occupant != null:
		return
	occupant = plr
	time_left = life_interval
	plr.set_trapped(self)
	plr.lose_life() # first life is lost on entering
	if plr.dead:
		occupant = null

func sync_lose_life() -> void:
	if !is_instance_valid(occupant):
		return
	time_left = life_interval
	occupant.lose_life()
	if occupant.dead:
		occupant = null

# Called by the rescuer once the hold completes
func request_rescue() -> void:
	if GDSync.is_host():
		host_request_rescue()
	else:
		GDSync.call_func_on(GDSync.get_host(), host_request_rescue)

func host_request_rescue() -> void:
	if is_instance_valid(occupant) and occupant.trapped and !occupant.dead:
		GDSync.call_func_all(sync_rescue)

func sync_rescue() -> void:
	if !is_instance_valid(occupant):
		return
	var plr := occupant
	occupant = null
	time_left = 0.0
	plr.set_rescued(exit_position())
