@icon("res://addons/at-icons/node3d/list_ordered.svg")
class_name plr_list extends Node3D

@export var base_player:PackedScene
@export var base_monster:PackedScene
@export var view_timer:Timer
@export var view_timer_label:Label
@export var showcase:showcaser
var started = false

signal game_started

var joined = []

func add_to_host_joined(client:int):
	joined.append(client)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	GDSync.client_left.connect(leave)
	GDSync.expose_func(_start_game)
	GDSync.expose_func(add_to_host_joined)
	GDSync.expose_signal(game_started,ENUMS.EXPOSE_PERMISSION.HOST)
	await get_tree().physics_frame
	if !GDSync.is_host():
		GDSync.call_func_on(GDSync.get_host(),add_to_host_joined,GDSync.get_client_id())
	else:
		add_to_host_joined(GDSync.get_host())
		
	#GDSync.client_joined.connect(join)
	pass # Replace with function body.
	

func _physics_process(delta: float) -> void:
	if GDSync.is_host():
		print(GDSync.lobby_get_player_count())
		print(joined.size())
	if GDSync.is_host() and joined.size() >= GDSync.lobby_get_player_count():
		if is_instance_valid(view_timer):
			if view_timer:
				if view_timer.is_stopped() and !started:
					view_timer.start()
					GDSync.call_func_all(showcase.showcase_start)
				view_timer_label.text = str(roundi(view_timer.time_left))
				

func _start_game():
	Network.game_started = true
	GeneralScreen.fade(1.25)
	game_started.emit()
	await get_tree().create_timer(1).timeout
	for client_id:int in GDSync.lobby_get_all_clients():
		join(client_id)


func leave(client_id:int):
	for child:player in get_children():
		if child.name.to_int() == client_id:
			child.queue_free()

	pass
	

func join(client_id:int) -> void:
	if GDSync.player_get_data(client_id,"TEAM") == "MONSTER":
		var plr:player=base_monster.instantiate()
		print("create_plr " + str(client_id))
		add_child(plr)
		plr.name = str(client_id)
		plr.monster = true
		plr.global_transform = get_tree().get_nodes_in_group("monster_spawn").pick_random().global_transform
		GDSync.set_gdsync_owner(plr,client_id)
		pass
	else:
		var plr:player=base_player.instantiate()
		print("create_plr " + str(client_id))
		add_child(plr)
		plr.name = str(client_id)
		plr.monster = false
		plr.global_transform = get_tree().get_nodes_in_group("plr_spawn").pick_random().global_transform
		GDSync.set_gdsync_owner(plr,client_id)
		pass


func _on_timer_timeout() -> void:
	if GDSync.is_host() and !started:
		started = true
		GDSync.call_func_all(_start_game)
	pass # Replace with function body.
