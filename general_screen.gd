extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.expose_func(chaos)
	pass # Replace with function body.

var fading = false

func fade(wait_time:float=0.5):
	if fading: return
	fading = true
	$AnimationPlayer.play("fade")
	await get_tree().create_timer(wait_time).timeout
	$AnimationPlayer.play("fade_2")
	fading = false
	
func chaos(on:bool):
	$status/chaos.visible = on
	
