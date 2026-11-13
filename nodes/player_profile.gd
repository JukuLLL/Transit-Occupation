extends Node
# Autoload name: PlayerProfile

signal name_changed(new_name: String)

const MAX_NAME_LENGTH := 20

var display_name := "Player"

func _ready() -> void:
	_refresh()
	SteamManager.steam_ready.connect(_refresh)

func _refresh() -> void:
	var new_name := "Player"
	if SteamManager.steam_ok and SteamManager.steam_name != "":
		new_name = SteamManager.steam_name.substr(0, MAX_NAME_LENGTH)
	if new_name != display_name:
		display_name = new_name
		name_changed.emit(display_name)
