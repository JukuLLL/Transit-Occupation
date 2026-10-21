extends Node

signal credits_changed(new_amount: int)
signal gold_coins_changed(new_amount: int)

const SAVE_PATH := "user://currency.cfg"

var credits: int = 0:
	set(value):
		credits = max(value, 0)
		credits_changed.emit(credits)

var gold_coins: int = 0:
	set(value):
		gold_coins = max(value, 0)
		gold_coins_changed.emit(gold_coins)

func _ready() -> void:
	load_data()

func add_credits(amount: int) -> void:
	credits += amount
	save_data()

func add_gold_coins(amount: int) -> void:
	gold_coins += amount
	save_data()
	
func delete_data():
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.clear()
	cfg.save(SAVE_PATH)

func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("currency", "credits", credits)
	cfg.set_value("currency", "gold_coins", gold_coins)
	cfg.save(SAVE_PATH)

func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	credits = cfg.get_value("currency", "credits", 0)
	gold_coins = cfg.get_value("currency", "gold_coins", 0)
