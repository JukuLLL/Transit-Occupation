extends Node

signal steam_ready

var steam_ok := false
var steam_id := 0
var steam_name := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var result: Dictionary = Steam.steamInitEx()
	print("Steam init: ", result)
	
	# status 0 means success
	if int(result.get("status", 1)) != 0:
		push_warning("Steam did not start: " + str(result.get("verbal", "unknown reason")))
		return
	
	steam_ok = true
	steam_id = Steam.getSteamID()
	steam_name = Steam.getPersonaName()
	print("Steam OK: ", steam_name, " (", steam_id, ")")
	steam_ready.emit()

func _process(_delta: float) -> void:
	if steam_ok:
		Steam.run_callbacks()
