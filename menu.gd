extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#for child:Node in get_children():
		#if child.get("disabled") != null:
			#child.disabled = true
	GDSync.connected.connect(connected)
	pass # Replace with function body.

func connected():
	print("connected")
	#for child:Node in get_children():
		#if child.get("disabled") != null:
			#child.disabled = false

func _on_play_pressed() -> void:
	Network.join_lobby()
	pass # Replace with function body.


func _on_create_pressed() -> void:
	Network.create_lobby()
	pass # Replace with function body.


func _on_option_button_item_selected(index: int) -> void:
	Network.side = $OptionButton.get_item_text(index)
	pass # Replace with function body.


func _on_create_testing_pressed() -> void:
	Network.create_lobby(true)
	pass # Replace with function body.


func _on_join_testing_pressed() -> void:
	Network.join_lobby(true)
	pass # Replace with function body.


func _on_namer_text_changed(new_text: String) -> void:
	Network.plr_name = new_text
	pass # Replace with function body.
