extends StaticBody3D

@export var distance:float=15
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if is_instance_valid(get_viewport().get_camera_3d()) and get_viewport().get_camera_3d().owner != null and get_viewport().get_camera_3d().owner.is_class("CharacterBody3D"):
		var camera:Camera3D=get_viewport().get_camera_3d()
		var plr:player=camera.owner
		if camera.is_position_in_frustum(global_position) and global_position.distance_to(plr.global_position) < distance:
			plr.set_grapple_target(global_position)
		pass
