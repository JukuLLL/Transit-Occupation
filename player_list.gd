extends Node3D

@export var base_player:PackedScene
@export var base_monster:PackedScene
var started = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	#GDSync.client_joined.connect(join)
	pass # Replace with function body.
	

func _input(event: InputEvent) -> void:
	if multiplayer.is_server() and !started:
		if Input.is_action_just_pressed("ui_accept"):
			started = true
			_start_game.rpc()
				
@rpc("any_peer","call_local","reliable")
func _start_game():
	Network.game_started = true
	for client_id:int in multiplayer.get_peers():
		join(client_id)


func leave(client_id:int):
	var plr:player=find_child(str(client_id))
	if plr != null:
		plr.queue_free()
	pass

func join(client_id:int) -> void:
	NetworkUtils._get_from_player_data(client_id)
	if NetworkUtils.info == "MONSTER":
		var plr:player=base_monster.instantiate()
		print("create_plr " + str(client_id))
		add_child(plr)
		plr.name = str(client_id)
		plr.monster = true
		plr.set_multiplayer_authority(client_id)
		pass
	else:
		var plr:player=base_player.instantiate()
		print("create_plr " + str(client_id))
		add_child(plr)
		plr.name = str(client_id)
		plr.monster = false
		plr.set_multiplayer_authority(client_id)
		pass
