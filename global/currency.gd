extends Node

signal credits_changed(new_amount: int)
signal gold_coins_changed(new_amount: int)

# Files in SYNC_DIR are the ones Steam Cloud will sync later.
# Files in LOCAL_DIR (Steam not running) are never synced.
const SYNC_DIR := "user://saves"
const LOCAL_DIR := "user://saves_local"
const LEGACY_PATH := "user://currency.cfg"

var _save_path := ""

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

func _steam_account_known() -> bool:
	return SteamManager.steam_ok and str(SteamManager.steam_id) != "0"

func _build_save_path() -> String:
	if _steam_account_known():
		DirAccess.make_dir_recursive_absolute(SYNC_DIR)
		return "%s/currency_%s.cfg" % [SYNC_DIR, str(SteamManager.steam_id)]
	DirAccess.make_dir_recursive_absolute(LOCAL_DIR)
	return LOCAL_DIR + "/currency_offline.cfg"

# Saves from older versions of this script, moved into the new folders once
func _find_old_file() -> String:
	var candidates:Array = []
	if _steam_account_known():
		candidates.append("user://currency_%s.cfg" % str(SteamManager.steam_id))
	else:
		candidates.append("user://currency_offline.cfg")
	candidates.append(LEGACY_PATH)
	for p in candidates:
		if FileAccess.file_exists(p):
			return p
	return ""

func add_credits(amount: int) -> void:
	credits += amount
	save_data()

func add_gold_coins(amount: int) -> void:
	gold_coins += amount
	save_data()
	
func add_currency(currency_id:String, amount:int) -> bool:
	if amount <= 0:
		return false
	match currency_id:
		"credits":
			add_credits(amount)
			return true
		"gold_coins":
			add_gold_coins(amount)
			return true
	push_warning("Unknown currency: " + currency_id)
	return false

func can_afford(currency_id:String, amount:int) -> bool:
	match currency_id:
		"credits":
			return credits >= amount
		"gold_coins":
			return gold_coins >= amount
	return false

func spend_currency(currency_id:String, amount:int) -> bool:
	if amount <= 0 or !can_afford(currency_id, amount):
		return false
	match currency_id:
		"credits":
			credits -= amount
		"gold_coins":
			gold_coins -= amount
	save_data()
	return true

func delete_data():
	credits = 0
	gold_coins = 0
	save_data()

func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("currency", "credits", credits)
	cfg.set_value("currency", "gold_coins", gold_coins)
	cfg.set_value("meta", "saved_at", Time.get_unix_time_from_system())
	cfg.save(_save_path)

func load_data() -> void:
	_save_path = _build_save_path()
	var cfg := ConfigFile.new()
	if cfg.load(_save_path) != OK:
		var old := _find_old_file()
		if old == "" or cfg.load(old) != OK:
			return
		credits = cfg.get_value("currency", "credits", 0)
		gold_coins = cfg.get_value("currency", "gold_coins", 0)
		save_data()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(old))
		return
	credits = cfg.get_value("currency", "credits", 0)
	gold_coins = cfg.get_value("currency", "gold_coins", 0)
