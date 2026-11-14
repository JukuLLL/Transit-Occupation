extends Node
# Autoload name: PlayerProfile

signal name_changed(new_name: String)

const MAX_NAME_LENGTH := 20

var display_name := "Player"

func _ready() -> void:
	_refresh()
	SteamManager.steam_ready.connect(_refresh)

# Testing only: launch argument "--name=Tester1" overrides the Steam name
func _get_test_name() -> String:
	var all_args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a in all_args:
		if a.begins_with("--name="):
			return a.substr(7).strip_edges()
	return ""

func _refresh() -> void:
	var new_name := "Player"
	var test_name := _get_test_name()
	if test_name != "":
		new_name = test_name.substr(0, MAX_NAME_LENGTH)
	elif SteamManager.steam_ok and SteamManager.steam_name != "":
		new_name = SteamManager.steam_name
		if OS.has_feature("editor"):
			# Editor testing only: make each window's name unique
			new_name += "_" + str(OS.get_process_id() % 1000)
		new_name = new_name.substr(0, MAX_NAME_LENGTH)
	if new_name != display_name:
		display_name = new_name
		name_changed.emit(display_name)
