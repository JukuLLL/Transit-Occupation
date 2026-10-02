extends Node3D

@export var camera:Camera3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	camera.make_current()
	pass # Replace with function body.

func _physics_process(delta: float) -> void:
	rotation_degrees.y += 0.5
	if Network.game_started:
		queue_free()
