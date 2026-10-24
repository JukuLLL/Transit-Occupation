@icon("res://addons/at-icons/node3d/explosion.svg")
class_name BaseParticle extends SynchronizedGPUParticles3D

@export var free_on_finish:bool=true

@export var autoplay:bool=true
@export var autoplay_synced:bool=true



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	finished.connect(finshed)
	if autoplay:
		if autoplay_synced:
			emit_synced()
		else:
			emit()
	pass # Replace with function body.
	
func emit(synced:bool=true):
	if synced:
		emit_synced()
	else:
		emit()


func finshed():
	queue_free()
