@icon("res://addons/at-icons/node3d/heart_broken.svg")
class_name Damager extends Area3D

@export var use_force:bool=false
@export var only_force:bool=false
@export var affect_physics:bool=false
@export var force_mult:float=1
@export var cause_of_damage:String="General".to_upper()
@export var damage_amount:int=5
@export var one_tick:bool=false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.expose_node(self)
	if one_tick:
		await get_tree().physics_frame
		await get_tree().physics_frame
		self.queue_free()
	pass # Replace with function body.

func set_damager_cause(to:String):
	cause_of_damage = to.to_upper()

func _damage():
	var force:Vector3
	for body:Node3D in get_overlapping_bodies():
		for client:int in GDSync.lobby_get_all_clients():
			if client == body.name.to_int():
				var plr:player=body
				if use_force:
					force = global_position.direction_to(plr.global_position)
					force.y -= 0.5
					force *= force_mult
				print("attack")
				GDSync.call_func_on(plr.name.to_int(),plr.hit_by_damager,damage_amount,cause_of_damage,force)
		if body.is_class("RigidBody3D"):
			if affect_physics:
				GDSync.call_func_on(GDSync.get_host(),apply_force,body.get_path())
	for area:Area3D in get_overlapping_areas():
		if area is breakable:
			var brekable_area:breakable=area
			area.hit_by_damager()
			
func apply_force(body_path:NodePath):
	var force:Vector3
	var body:RigidBody3D=get_node(body_path)
	body.freeze = false
	if use_force:
		force = global_position.direction_to(body.global_position)
		force.y -= 0.1
		force *= force_mult
		force *= 0.5
	body.apply_central_impulse(force)
	pass
			
				
		
