extends Node

var hosting = false

var side = "PLAYER"

var plr_name = ""

var game_started = false

var monster_id:int

var forced = ""

var round_over := false

var pending_message := ""

signal unfreeze

signal game_loaded

func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		await get_tree().process_frame
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func plr_node_finder(node_array:Array) -> Array:
	var plr_array:Array
	for body:Node3D in node_array:
		for client:int in GDSync.lobby_get_all_clients():
			if body.name.to_int() == client:
				plr_array.append(body)
	return plr_array
	
		
func name_is_player(id:int) -> bool:
	for plr_id in GDSync.lobby_get_all_clients():
		if id == plr_id:
			return true
	return false
	
func change_level(path:String):
	GDSync.change_scene(path)
		
		
func _ready() -> void:
	AudioServer.set_input_device_active(true)
	GDSync.expose_signal(unfreeze)
	GDSync.expose_signal(game_loaded)
	GDSync.change_scene_success.connect(level_changed)
	GDSync.lobby_joined.connect(joined)
	GDSync.lobby_received.connect(lobby_recived)
	GDSync.lobby_created.connect(lobby_created)
	GDSync.connected.connect(connected)
	GDSync.lobby_creation_failed.connect(lobby_creation_failed)
	GDSync.lobby_join_failed.connect(lobby_join_failed)
	pass # Replace with function body.
	
			
func lobby_join_failed(lobby_name:String, error:int):
	var msg := "Could not join the lobby."
	match error:
		ENUMS.LOBBY_JOIN_ERROR.LOBBY_IS_FULL:
			msg = "The lobby is full (max 7 players)."
		ENUMS.LOBBY_JOIN_ERROR.LOBBY_DOES_NOT_EXIST:
			msg = "That lobby doesn't exist."
	return_to_menu(msg)

func return_to_menu(message:String):
	round_over = false
	game_started = false
	pending_message = message
	GDSync.stop_multiplayer()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://menus/menu.scn")
	
func lobby_recived(lobbies:Dictionary):
	print(lobbies)
	pass
	
func connected():
	print("connected")

func joined(lobby_name:String):
	print("joined "+lobby_name)
	
func multiplayer_start(local:bool=false) -> bool:
	if local:
		GDSync.start_local_multiplayer()
	else:
		GDSync.start_multiplayer()
	await GDSync.connected
	GDSync.player_set_username(plr_name)
	return true
	
func level_changed():
	GDSync.emit_signal_remote_all(game_loaded)
	

func join_lobby(local:bool=false):
	if await multiplayer_start(local):
		GDSync.get_public_lobbies()
		get_tree().change_scene_to_file("uid://dhy3uk4ck23ud")
		Network.hosting = true
		GDSync.lobby_join("ABCD")

func create_lobby(local:bool=false):
	if await multiplayer_start(local):
		get_tree().change_scene_to_file("uid://dhy3uk4ck23ud")
		Network.hosting = false
		GDSync.lobby_create("ABCD", "", true, 7)
		GDSync.lobby_join("ABCD")
		GDSync.set_host(GDSync.get_client_id())
		if local:
			if forced == "MONSTER":
				GDSync.player_set_data("TEAM","MONSTER")
				Network.monster_id = GDSync.get_client_id()
			else:
				GDSync.player_set_data("TEAM","PLAYER")
				Network.monster_id = 0

	

func lobby_created(lobby_name:String):
	GDSync.lobby_join(lobby_name)
	#GDSync.set_host(GDSync.get_client_id())
	if false == true:
		if forced == "MONSTER":
			GDSync.player_set_data("TEAM","MONSTER")
			Network.monster_id = GDSync.get_client_id()
		else:
			GDSync.player_set_data("TEAM","PLAYER")
			Network.monster_id = 0
	print(lobby_name)
	
func lobby_creation_failed(lobby_name : String, error : int):
	match(error):
		ENUMS.LOBBY_CREATION_ERROR.LOBBY_ALREADY_EXISTS:
			push_error("A lobby with the name "+lobby_name+" already exists.")
		ENUMS.LOBBY_CREATION_ERROR.NAME_TOO_SHORT:
			push_error(lobby_name+" is too short.")
		ENUMS.LOBBY_CREATION_ERROR.NAME_TOO_LONG:
			push_error(lobby_name+" is too long.")
		ENUMS.LOBBY_CREATION_ERROR.PASSWORD_TOO_LONG:
			push_error("The password for "+lobby_name+" is too long.")
		ENUMS.LOBBY_CREATION_ERROR.TAGS_TOO_LARGE:
			push_error("The tags have exceeded the 2048 byte limit.")
		ENUMS.LOBBY_CREATION_ERROR.DATA_TOO_LARGE:
			push_error("The data have exceeded the 2048 byte limit.")
		ENUMS.LOBBY_CREATION_ERROR.ON_COOLDOWN:
			push_error("Please wait a few seconds before creating another lobby.")
