extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.
	
func create_plr_data():
	var plr_data = {"ID"=Network.peer.get_unique_id(),"TEAM"=Network.side}
	Network.plr_data = plr_data

func _physics_process(delta: float) -> void:
	_sync_players.rpc()

@rpc("authority","call_remote","reliable")
func _sync_players(players:Dictionary):
	Network.players = players

@rpc("any_peer","call_remote","reliable")
func _get_plr_data():
	var id:int=multiplayer.get_remote_sender_id()
	var plr_data:Dictionary= Network.players.find_key(id)
	_recive_data.rpc_id(id,plr_data)
	
@rpc("any_peer","call_remote","reliable")
func _set_plr_data(what:String,to:Variant):
	var id:int=multiplayer.get_remote_sender_id()
	Network.players.set(what,to)

@rpc("any_peer","call_remote","reliable")
func _recive_data(data:Dictionary):
	Network.plr_data = data

@rpc("any_peer","call_remote","reliable")
func _add_player_data(data:Dictionary):
	if !Network.players.has(data):
		Network.players.assign(data)
		
@rpc("any_peer","call_remote","reliable")
func _recive_data_info(plr_info:Dictionary):
	info = plr_info
	
var info:Variant
		
@rpc("any_peer","call_remote","reliable")	
func _get_from_player_data(id:int):
	var plr_data:Dictionary = Network.plr_data
	_recive_data_info.rpc_id(multiplayer.get_remote_sender_id(),plr_data)
	
