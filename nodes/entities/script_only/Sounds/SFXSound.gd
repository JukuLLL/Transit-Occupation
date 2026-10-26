class_name SFXSound extends SynchronizedAudioStreamPlayer3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	finished.connect(finish)
	pass # Replace with function body.


func finish():
	queue_free()
