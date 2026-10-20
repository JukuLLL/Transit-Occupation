class_name grabble_point extends StaticBody3D

@export var distance:float=25

signal grabbled
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.expose_signal(grabbled)
	pass # Replace with function body.

func disable(on:bool=false):
	if on:
		process_mode =Node.PROCESS_MODE_INHERIT
	else:
		process_mode =Node.PROCESS_MODE_DISABLED

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if is_instance_valid(get_viewport().get_camera_3d()):
		var camera:Camera3D=get_viewport().get_camera_3d()
		if  camera.owner == null:
			return
		if  camera.owner.owner == null:
			return
		if camera.owner.owner.is_class("CharacterBody3D"):
			var plr:player=camera.owner.owner
			#if camera.is_position_in_frustum(global_position) and global_position.distance_to(plr.global_position) < distance * plr.grapple_distance:
				#plr.set_grapple_target(global_position)
			pass
