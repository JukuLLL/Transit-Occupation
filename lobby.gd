extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.expose_func(change_level)
	GDSync.expose_func(set_side_data)
	GDSync.expose_func(set_side)
	GDSync.client_joined.connect(_join)
	GDSync.client_left.connect(_leave)
	await get_tree().create_timer(1).timeout
	$start.visible = GDSync.is_host()
	pass # Replace with function body.

var list = []
var plr_list = []


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
		GDSync.call_func_all(change_level)
	pass # Replace with function body.
	
var started = false

func set_side():
	if GDSync.is_host():
		var monster_id:int
		monster_id = GDSync.lobby_get_all_clients().pick_random()
		for client:int in GDSync.lobby_get_all_clients():
			print(client)
			if client == monster_id:
				GDSync.call_func_on(client,set_side_data,true)
			else:
				GDSync.call_func_on(client,set_side_data,false)
func set_side_data(monster:bool):
	print(monster)
	print("is_monster")
	if monster:
		GDSync.player_set_data("TEAM","MONSTER")
	else:
		GDSync.player_set_data("TEAM","PLAYER")
func change_level():
	if started: return
	set_side()
	started = true
	$Timer.stop()
	await get_tree().create_timer(3).timeout
	get_tree().change_scene_to_file("uid://dcdm1p1khuy4n")


func _on_start_pressed() -> void:
	if GDSync.is_host():
		GDSync.call_func_all(change_level)
	pass # Replace with function body.
