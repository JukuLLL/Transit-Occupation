@icon("res://addons/at-icons/node3d/heart_broken.svg")
class_name Damager extends Area3D

@export var use_force:bool=false
@export var force_mult:float=1
@export var cause_of_damage:String="General".to_upper()
@export var damage_amount:int=5

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func set_damager_cause(to:String):
	cause_of_damage = to.to_upper()

func _damage():
	var force:Vector3
	for body:Node3D in get_overlapping_bodies():
		if body is player and GDSync.is_gdsync_owner(body):
			var plr:player=body
			if use_force:
				force = global_position.direction_to(plr.global_position)
				force.y -= 0.5
				force *= force_mult
			print("attack")
			GDSync.call_func_all(plr.hit_by_damager,damage_amount,cause_of_damage,force)
			
				
		
