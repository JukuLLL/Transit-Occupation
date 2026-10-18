extends Sprite3D

var allow = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	visible = false
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if is_instance_valid(get_viewport().get_camera_3d()):
		if get_viewport().get_camera_3d().is_position_in_frustum(global_position):
			await get_tree().physics_frame
			await get_tree().physics_frame
			await get_tree().physics_frame
			visible = false
		
	pass


func _on_timer_timeout() -> void:
	if !$Node/VisibleOnScreenNotifier3D.is_on_screen() and is_instance_valid(get_viewport().get_camera_3d()):
		if !get_viewport().get_camera_3d().is_position_in_frustum(global_position) and get_viewport().get_camera_3d().is_position_behind(global_position):
			visible = true
			global_position = get_viewport().get_camera_3d().global_position
			global_position -= Vector3(0,0,5) * get_viewport().get_camera_3d().global_basis
	pass # Replace with function body.
