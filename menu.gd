extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


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
