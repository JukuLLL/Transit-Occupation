extends Control

@export var settings_scene:PackedScene

@onready var credits_label: Label = $CreditsLabel
@onready var gold_coins_label: Label = $GoldCoinsLabel


func _ready() -> void:
	GDSync.connected.connect(connected)
	
	Currency.credits_changed.connect(_update_credits_label)
	Currency.gold_coins_changed.connect(_update_gold_coins_label)
	_update_credits_label(Currency.credits)
	_update_gold_coins_label(Currency.gold_coins)
	
	$AddCredits.pressed.connect(_on_add_credits_pressed)
	$AddGoldCoins.pressed.connect(_on_add_gold_coins_pressed)
	

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
