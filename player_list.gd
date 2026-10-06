extends Node3D

@export var base_player:PackedScene
@export var base_monster:PackedScene
var started = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.client_left.connect(leave)
	GDSync.expose_func(_start_game)
	await get_tree().physics_frame
	#GDSync.client_joined.connect(join)
	pass # Replace with function body.
	

func _physics_process(delta: float) -> void:
	if GDSync.is_host():
		if is_instance_valid($"../map_viewer/Camera3D/Timer"):
			if $"../map_viewer/Camera3D/Timer":
				if $"../map_viewer/Camera3D/Timer".is_stopped() and !started:
					$"../map_viewer/Camera3D/Timer".start()
				$"../map_viewer/Camera3D/Label".text = str(roundi($"../map_viewer/Camera3D/Timer".time_left))
				

func _start_game():
	Network.game_started = true
	GeneralScreen.fade(1.25)
	await get_tree().create_timer(1).timeout
	for client_id:int in GDSync.lobby_get_all_clients():
		join(client_id)


func leave(client_id:int):
	var plr:player=find_child(str(client_id))
	if plr != null:
		plr.queue_free()
	pass

func join(client_id:int) -> void:
	if GDSync.player_get_data(client_id,"TEAM") == "MONSTER":
		var plr:player=base_monster.instantiate()
		print("create_plr " + str(client_id))
		add_child(plr)
		plr.name = str(client_id)
		plr.monster = true
		GDSync.set_gdsync_owner(plr,client_id)
		pass
	else:
		var plr:player=base_player.instantiate()
		print("create_plr " + str(client_id))
		add_child(plr)
		plr.name = str(client_id)
		plr.monster = false
		GDSync.set_gdsync_owner(plr,client_id)
		pass


func _on_timer_timeout() -> void:
	if GDSync.is_host() and !started:
		started = true
		GDSync.call_func_all(_start_game)
	pass # Replace with function body.
