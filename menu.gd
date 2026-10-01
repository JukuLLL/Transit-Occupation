extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.connected.connect(connected)
	GDSync.start_multiplayer()
	pass # Replace with function body.

func connected():
	print("connected")

func _on_play_pressed() -> void:
	Network.hosting = false
	get_tree().change_scene_to_file("uid://dcdm1p1khuy4n")
	pass # Replace with function body.


func _on_create_pressed() -> void:
	Network.hosting = true
	get_tree().change_scene_to_file("uid://dcdm1p1khuy4n")
	pass # Replace with function body.
