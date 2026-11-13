extends Node

signal credits_changed(new_amount: int)
signal gold_coins_changed(new_amount: int)

const LEGACY_PATH := "user://currency.cfg"

var _save_path := LEGACY_PATH

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

func _build_save_path() -> String:
	if SteamManager.steam_ok and str(SteamManager.steam_id) != "0":
		return "user://currency_%s.cfg" % str(SteamManager.steam_id)
	return "user://currency_offline.cfg"

func add_credits(amount: int) -> void:
	credits += amount
	save_data()

func add_gold_coins(amount: int) -> void:
	gold_coins += amount
	save_data()

func delete_data():
	var cfg := ConfigFile.new()
	cfg.load(_save_path)
	cfg.clear()
	cfg.save(_save_path)

func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("currency", "credits", credits)
	cfg.set_value("currency", "gold_coins", gold_coins)
	cfg.save(_save_path)

func load_data() -> void:
	_save_path = _build_save_path()
	var cfg := ConfigFile.new()
	if cfg.load(_save_path) != OK:
		# No save for this account yet: bring over the old shared save once
		var legacy := ConfigFile.new()
		if legacy.load(LEGACY_PATH) != OK:
			return
		credits = legacy.get_value("currency", "credits", 0)
		gold_coins = legacy.get_value("currency", "gold_coins", 0)
		save_data()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_PATH))
		return
	credits = cfg.get_value("currency", "credits", 0)
	gold_coins = cfg.get_value("currency", "gold_coins", 0)
