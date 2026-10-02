extends Node

var hosting = false

var side = "PLAYER"

var game_started = false

var peer:ENetMultiplayerPeer

var players:Dictionary = {}

var plr_data = {}

func _ready() -> void:
	pass # Replace with function body.
	
func lobby_recived(lobbies:Dictionary):
	print(lobbies)
	pass
	
func connected():
	print("connected")

func joined(lobby_name:String):
	print("joined "+lobby_name)
	
	

func join_lobby(local:bool=false):
	peer = ENetMultiplayerPeer.new()
	peer.create_client("localhost",25565)
	multiplayer.multiplayer_peer = peer
	Network.hosting = false
	NetworkUtils.create_plr_data()
	NetworkUtils._add_player_data.rpc_id(1,Network.plr_data)
	get_tree().change_scene_to_file("uid://dcdm1p1khuy4n")


func create_lobby(local:bool=false):
	peer = ENetMultiplayerPeer.new()
	peer.create_server(25565,7)
	multiplayer.multiplayer_peer = peer
	Network.hosting = true
	NetworkUtils.create_plr_data()
	NetworkUtils._add_player_data(Network.plr_data)
	get_tree().change_scene_to_file("uid://dcdm1p1khuy4n")
