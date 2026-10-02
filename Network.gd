extends Node

var hosting = false

func _ready() -> void:
	GDSync.lobby_joined.connect(joined)
	GDSync.lobby_received.connect(lobby_recived)
	GDSync.lobby_created.connect(lobby_create)
	GDSync.connected.connect(connected)
	GDSync.lobby_creation_failed.connect(lobby_creation_failed)
	GDSync.start_local_multiplayer()
	pass # Replace with function body.
	
func lobby_recived(lobbies:Dictionary):
	print(lobbies)
	pass
	
func connected():
	print("connected")

func joined(lobby_name:String):
	print("joined "+lobby_name)
	

func join_lobby():
	GDSync.get_public_lobbies()
	get_tree().change_scene_to_file("uid://dcdm1p1khuy4n")
	Network.hosting = true
	GDSync.lobby_join("ABCD")

func create_lobby():
	get_tree().change_scene_to_file("uid://dcdm1p1khuy4n")
	Network.hosting = false
	GDSync.lobby_create("ABCD")
	GDSync.lobby_join("ABCD")

func lobby_create(lobby_name:String):
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
