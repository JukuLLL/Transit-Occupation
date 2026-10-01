extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.connected.connect(connected)
	GDSync.start_local_multiplayer()
	pass # Replace with function body.

func connected():
	print("connected")

func _on_play_pressed() -> void:
	Network.join_lobby()
	pass # Replace with function body.


func _on_create_pressed() -> void:
	Network.create_lobby()
	pass # Replace with function body.
