@icon("res://addons/at-icons/node3d/brick_wall.svg")
class_name breakable extends Area3D

@export var health:int=5

@export var synced:bool=true

@export var velocity_to_damage:float=5

@export var breakable_by_monster:bool=true
@export var breakable_by_player:bool=true
@export var breakable_by_damager:bool=true

signal on_break

signal on_damage

var broken = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.expose_signal(on_break)
	GDSync.expose_signal(on_damage)
	GDSync.expose_var(self,"health")
	body_entered.connect(enter)
	pass # Replace with function body.
	
func hit_by_damager():
	if !breakable_by_damager: return
	hit()

func hit():
	if synced:
		health -= 1
		GDSync.sync_var(self,"health",true)
	else:
		health -= 1
	if health <= 0:
		broken = true
		Juicee.shake_camera(get_viewport().get_camera_3d(),3,0.2,10)
		if synced:
			GDSync.emit_signal_remote_all(on_break)
		else:
			on_break.emit()
	else:
		if synced:
			GDSync.emit_signal_remote_all(on_damage)
		else:
			on_damage.emit()
	
func enter(body:Node3D):
	if broken:return
	if body is player and GDSync.is_gdsync_owner(body):
		var plr:player=body
		if plr.monster and !breakable_by_monster:
			return
		if !plr.monster and !breakable_by_player:
			return
		if abs(plr.get_real_velocity().length()) > velocity_to_damage:
			hit()
			
