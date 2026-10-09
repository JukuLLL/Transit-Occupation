extends Control

var maps:Array=["uid://cket7yaadcvm3"]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.expose_func(change_level)
	GDSync.expose_func(set_side_data)
	GDSync.expose_func(set_side)
	GDSync.expose_func(set_monster_id)
	GDSync.client_joined.connect(_join)
	GDSync.client_left.connect(_leave)
	await get_tree().create_timer(1).timeout
	$start.visible = GDSync.is_host()
	pass # Replace with function body.

var list = []
var plr_list = []

func _process(delta: float) -> void:
	$time.text = str(roundi($Timer.time_left))


func _join(client_id:int):
	var id = $ItemList.add_item(str(GDSync.player_get_username(client_id)))
	list.append(id)
	plr_list.append(client_id)
	pass
	
func _leave(client_id:int):
	var index = plr_list.find(client_id)
	list.erase(index)
	$ItemList.remove_item(index)
	plr_list.erase(client_id)
	pass


func _on_timer_timeout() -> void:
	if GDSync.is_host():
		GDSync.call_func_all(change_level,maps.pick_random())
	pass # Replace with function body.
	
var started = false

var monster_id:int=0

func set_side():
	if GDSync.is_host():
		if monster_id == 0:
			monster_id = GDSync.lobby_get_all_clients().pick_random()
		for client:int in GDSync.lobby_get_all_clients():
			print(client)
			if client == monster_id and Network.forced != "PLAYER":
				GDSync.call_func_on(client,set_side_data,true)
			else:
				GDSync.call_func_on(client,set_side_data,false)
	else:
		if Network.forced == "MONSTER":
			set_side_data(true)
		else:
			set_side_data(false)
func set_side_data(monster:bool):
	print(monster)
	print("is_monster")
	if monster:
		GDSync.player_set_data("TEAM","MONSTER")
		GDSync.call_func_all(set_monster_id,GDSync.get_client_id())
	else:
		GDSync.player_set_data("TEAM","PLAYER")
		
func set_monster_id(client:int):
	Network.monster_id = client
		
func change_level(map:String):
	if started: return
	set_side()
	started = true
	$Timer.stop()
	GeneralScreen.fade(3)
	await get_tree().create_timer(3).timeout
	get_tree().change_scene_to_file(map)


func _on_start_pressed() -> void:
	if GDSync.is_host():
		GDSync.call_func_all(change_level,maps.pick_random())
	pass # Replace with function body.


func _on_item_list_item_selected(index: int) -> void:
	if GDSync.is_host():
		monster_id = plr_list.get(index)
	pass # Replace with function body.
