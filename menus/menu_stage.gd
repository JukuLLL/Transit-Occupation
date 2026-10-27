extends Node3D

@export var character:Node3D
@export var camera:Camera3D
@export var spin_speed := 0.4
@export var sway_amount := 0.08

var base_cam_pos:Vector3
var time := 0.0

func _ready() -> void:
	base_cam_pos = camera.position

func _process(delta:float) -> void:
	time += delta
	character.rotate_y(spin_speed * delta)
	# Gentle camera drift so the scene feels alive
	camera.position = base_cam_pos + Vector3(sin(time * 0.5), sin(time * 0.7) * 0.5, 0) * sway_amount
