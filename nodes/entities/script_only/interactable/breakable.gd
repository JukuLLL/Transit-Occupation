@icon("res://addons/at-icons/node3d/brick_wall.svg")
class_name breakable extends Area3D

@export var health:int=5

@export var synced:bool=true

@export var velocity_to_damage:float=5

signal on_break

signal on_damage

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.expose_signal(on_break)
	GDSync.expose_signal(on_damage)
	GDSync.expose_var(self,"health")
	body_entered.connect(enter)
	pass # Replace with function body.
	
	
func enter(body:Node3D):
	if body is player and GDSync.is_gdsync_owner(body):
		var plr:player=body
		if abs(plr.get_real_velocity().length()) > velocity_to_damage:
			if health <= 0:
				if synced:
					GDSync.emit_signal_remote_all(on_break)
				else:
					on_break.emit()
			else:
				if synced:
					GDSync.emit_signal_remote_all(on_damage)
					health -= 1
					GDSync.sync_var(self,"health",true)
				else:
					on_damage.emit()
					health -= 1
			
