@icon("res://addons/at-icons/node3d/list_ordered.svg")
class_name plr_list extends Node3D

@export var base_player:PackedScene
@export var base_monster:PackedScene # fallback when no monsters are defined
@export var monsters:Array[MonsterDef]
@export var head_start := 15.0 # seconds the survivors play before the monster spawns
@export var view_timer:Timer
@export var view_timer_label:Label
@export var showcase:showcaser

var started = false
var selection_started := false
var monsters_spawned := false
var choices:Dictionary = {} # host only: client id -> monster index
var pending_monsters:Array = []
var select_menu:MonsterSelectMenu

signal game_started

var joined = []

func add_to_host_joined(client:int):
	joined.append(client)

func _ready() -> void:
	GDSync.client_left.connect(leave)
	GDSync.expose_func(_start_game)
	GDSync.expose_func(add_to_host_joined)
	GDSync.expose_func(_begin_selection)
	GDSync.expose_func(_submit_choice)
	GDSync.expose_func(_spawn_monsters)
	GDSync.expose_signal(game_started,ENUMS.EXPOSE_PERMISSION.HOST)
	await get_tree().physics_frame
	if !GDSync.is_host():
		GDSync.call_func_on(GDSync.get_host(),add_to_host_joined,GDSync.get_client_id())
	else:
		add_to_host_joined(GDSync.get_host())

func _physics_process(_delta: float) -> void:
	if GDSync.is_host() and joined.size() >= GDSync.lobby_get_player_count():
		if is_instance_valid(view_timer):
			if view_timer.is_stopped() and !started and !selection_started:
				selection_started = true
				view_timer.start()
				GDSync.call_func_all(showcase.showcase_start)
				# cutscene + the 1 s spawn delay + the survivors' head start
				GDSync.call_func_all(_begin_selection, view_timer.wait_time + 1.0 + head_start)
			view_timer_label.text = str(roundi(view_timer.time_left))

# ---------- Monster selection ----------
func _is_monster(client_id:int) -> bool:
	return GDSync.player_get_data(client_id,"TEAM") == "MONSTER"

# Runs on every client, but only the monster's client opens the menu
func _begin_selection(total:float) -> void:
	if !_is_monster(GDSync.get_client_id()):
		return
	select_menu = MonsterSelectMenu.new()
	select_menu.monsters = monsters
	select_menu.duration = total
	select_menu.chosen.connect(_on_monster_chosen)
	add_child(select_menu)

func _on_monster_chosen(index:int) -> void:
	if GDSync.is_host():
		_submit_choice(GDSync.get_client_id(), index)
	else:
		GDSync.call_func_on(GDSync.get_host(), _submit_choice, GDSync.get_client_id(), index)

# Host only stores the choice
func _submit_choice(client_id:int, index:int) -> void:
	if !GDSync.is_host() or monsters.is_empty():
		return
	choices[client_id] = clampi(index, 0, monsters.size() - 1)

func _monster_scene(index:int) -> PackedScene:
	if monsters.is_empty():
		return base_monster
	var def:MonsterDef = monsters[clampi(index, 0, monsters.size() - 1)]
	return def.scene if def.scene != null else base_monster

# ---------- Match start ----------
func _start_game():
	if Network.game_started:
		return
	Network.game_started = true
	GeneralScreen.fade(1.25)
	game_started.emit()
	await get_tree().create_timer(1).timeout
	
	# Survivors spawn now, monsters wait for the head start to finish
	pending_monsters.clear()
	for client_id:int in GDSync.lobby_get_all_clients():
		if _is_monster(client_id):
			pending_monsters.append(client_id)
		else:
			join(client_id)
	
	# The host decides when time is up, so everyone spawns the monster together
	if GDSync.is_host() and !pending_monsters.is_empty():
		await get_tree().create_timer(head_start).timeout
		GDSync.call_func_all(_spawn_monsters, choices)

func _spawn_monsters(final_choices:Dictionary) -> void:
	if monsters_spawned:
		return
	monsters_spawned = true
	if is_instance_valid(select_menu):
		select_menu.close()
	var present:Array = GDSync.lobby_get_all_clients()
	for client_id:int in pending_monsters:
		if present.has(client_id):
			join(client_id, int(final_choices.get(client_id, 0)))

func leave(client_id:int):
	for child:player in get_children():
		if child.name.to_int() == client_id:
			child.queue_free()

func join(client_id:int, monster_index:int = 0) -> void:
	var is_monster := _is_monster(client_id)
	var scene:PackedScene = _monster_scene(monster_index) if is_monster else base_player
	var plr:player = scene.instantiate()
	print("create_plr " + str(client_id))
	add_child(plr)
	plr.name = str(client_id)
	plr.monster = is_monster
	var group := "monster_spawn" if is_monster else "plr_spawn"
	if get_tree().get_nodes_in_group(group).is_empty():
		pass
	else:
		plr.global_transform = get_tree().get_nodes_in_group(group).pick_random().global_transform
	GDSync.set_gdsync_owner(plr,client_id)

func _on_timer_timeout() -> void:
	if GDSync.is_host() and !started:
		started = true
		GDSync.call_func_all(_start_game)
