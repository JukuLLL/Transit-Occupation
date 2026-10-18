extends Sprite3D

var allow = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	visible = false
	await get_tree().create_timer(randi_range(60,250)).timeout
	allow = true
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if !allow: return
	if is_instance_valid(get_viewport().get_camera_3d()):
		if get_viewport().get_camera_3d().is_position_in_frustum(global_position):
			await get_tree().physics_frame
			await get_tree().physics_frame
			visible = false
		else:
			visible = true
		
	pass


func _on_timer_timeout() -> void:
	if !allow: return
	if is_instance_valid(get_viewport().get_camera_3d()):
		global_position = get_viewport().get_camera_3d().global_position + Vector3(randi_range(-50,50),randi_range(-50,50),randi_range(-50,50))
	pass # Replace with function body.
