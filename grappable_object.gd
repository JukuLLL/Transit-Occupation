class_name flingable_object extends RigidBody3D

var target_fling_pos:Vector3

var pull_pos:Vector3

@export var sound_physics:physics_sounds

var being_pulled = false

var pull_kill_timer:Timer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var timer:Timer=Timer.new()
	timer.wait_time = 10
	add_child(timer)
	pull_kill_timer = timer
	pull_kill_timer.timeout.connect(kill)
	await get_tree().create_timer(0.5).timeout
	GDSync.set_gdsync_owner(self,Network.monster_id)
	pass # Replace with function body.

var cooldown = false

func kill():
	being_pulled = false
	pass

func _pull_and_throw(from:Vector3,to:Vector3,force:float,close_distance:float,plr:player):
	if being_pulled:
		return
	plr.add_collision_exception_with(self)
	pull_kill_timer.stop()
	pull_kill_timer.start()
	being_pulled = true
	var pulling = true
	if sound_physics:
		sound_physics.sound_cooldown = 50
	while pulling:
		apply_impulse(global_position.direction_to(from) * force,Vector3.UP)
		await get_tree().physics_frame
		if global_position.distance_to(from) < close_distance:
			pulling = false
			continue
		if !being_pulled :
			pulling = false
			break
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if sound_physics:
		sound_physics.sound_cooldown = 2
	apply_central_impulse(global_position.direction_to(to) * (force * 4))
	cooldown = true
	await get_tree().create_timer(5).timeout
	cooldown = false
	being_pulled = false
	plr.remove_collision_exception_with(self)
	hit_targets.clear()
	
	
var hit_targets = []

func _on_velocity_hit_body_entered(body: Node3D) -> void:
	if body.is_class("CharacterBody3D") and abs(linear_velocity).length() > 7 and !hit_targets.has(body):
		var plr:player=body
		if !plr.monster:
			hit_targets.append(plr)
			print("hit")
	pass # Replace with function body.
