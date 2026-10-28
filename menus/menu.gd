extends Control

@export var settings_scene:PackedScene

@onready var credits_label: Label = $CreditsLabel
@onready var gold_coins_label: Label = $GoldCoinsLabel


func _ready() -> void:
	fade_in()
	GDSync.connected.connect(connected)
	
	Currency.credits_changed.connect(_update_credits_label)
	Currency.gold_coins_changed.connect(_update_gold_coins_label)
	_update_credits_label(Currency.credits)
	_update_gold_coins_label(Currency.gold_coins)
	
	$AddCredits.pressed.connect(_on_add_credits_pressed)
	$AddGoldCoins.pressed.connect(_on_add_gold_coins_pressed)
	
	if Network.pending_message != "":
		show_message(Network.pending_message)
		Network.pending_message = ""
	

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
	if index == 2:
		Network.forced = ""
	else:
		Network.forced = $OptionButton.get_item_text(index)
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


func _on_settings_pressed() -> void:
	add_child(settings_scene.instantiate())
	pass # Replace with function body.

func _update_credits_label(amount: int) -> void:
	credits_label.text = "Credits: %d" % amount
	
func _update_gold_coins_label(amount: int) -> void:
	gold_coins_label.text = "Gold Coins: %d" % amount
	
func _on_add_credits_pressed() -> void:
	Currency.add_credits(100)
	
func _on_add_gold_coins_pressed() -> void:
	Currency.add_gold_coins(10)


func _on_clear_pressed() -> void:
	Currency.delete_data()
	pass # Replace with function body.
	
func fade_in(duration := 2.3, hold := 1.3) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var tween := create_tween()
	tween.tween_interval(hold)
	tween.tween_property(rect, "modulate:a", 0.0, duration)
	tween.tween_callback(layer.queue_free)
	
func show_message(text:String, duration := 4.0) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 101 # above the fade-in overlay
	add_child(layer)
	
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = 40
	
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(layer.queue_free)
