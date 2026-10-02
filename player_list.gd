extends Node3D

@export var base_player:PackedScene
@export var base_monster:PackedScene
var started = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.client_left.connect(leave)
	GDSync.expose_func(_start_game)
	#GDSync.client_joined.connect(join)
	pass # Replace with function body.
	

func _input(event: InputEvent) -> void:
	if GDSync.is_host() and !started:
		if Input.is_action_just_pressed("ui_accept"):
			started = true
			GDSync.call_func_all(_start_game)
				
func _start_game():
	for client_id:int in GDSync.lobby_get_all_clients():
		join(client_id)


func leave(client_id:int):
	var plr:player=find_child(str(client_id))
	plr.queue_free()
	pass

func join(client_id:int) -> void:
	if GDSync.player_get_data(client_id,"TEAM") == "MONSTER":
		var plr:player=base_monster.instantiate()
		print("create_plr " + str(client_id))
		add_child(plr)
		plr.name = str(client_id)
		GDSync.set_gdsync_owner(plr,client_id)
		pass
	else:
		var plr:player=base_player.instantiate()
		print("create_plr " + str(client_id))
		add_child(plr)
		plr.name = str(client_id)
		GDSync.set_gdsync_owner(plr,client_id)
		pass
