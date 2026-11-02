extends Control

var maps:Array=["uid://cket7yaadcvm3"]

var survivor_only_toggle:CheckButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.expose_node(self)
	GDSync.client_joined.connect(_join)
	GDSync.client_left.connect(_leave)
	survivor_only_toggle = CheckButton.new()
	survivor_only_toggle.text = "Survivor-Only Queue"
	survivor_only_toggle.add_theme_font_size_override("font_size", 28)
	survivor_only_toggle.tooltip_text = "Never be picked as the Monster (unless everyone chooses this)"
	add_child(survivor_only_toggle)
	survivor_only_toggle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	survivor_only_toggle.offset_left = 24
	survivor_only_toggle.offset_bottom = -24
	survivor_only_toggle.toggled.connect(_on_survivor_only_toggled)
	GDSync.player_set_data("SURVIVOR_ONLY", false) # default: queued for both roles
	await get_tree().create_timer(1).timeout
	$start.visible = GDSync.is_host()
	pass # Replace with function body.
	
func _on_survivor_only_toggled(on:bool) -> void:
	GDSync.player_set_data("SURVIVOR_ONLY", on)

var list = []
var plr_list = []

const MAX_PLAYERS := 7
const COUNTDOWN := 30.0
var last_shown := -1

func _process(_delta: float) -> void:
	if GDSync.is_host():
		var secs := ceili($Timer.time_left) if !$Timer.is_stopped() else -1
		if secs != last_shown:
			last_shown = secs
			GDSync.call_func_all(_set_time_text, secs)
			
func _check_full() -> void:
	await get_tree().process_frame # let the client list update first
	if !GDSync.is_host() or started:
		return
	var full := GDSync.lobby_get_all_clients().size() >= MAX_PLAYERS
	if full and $Timer.is_stopped():
		$Timer.start(COUNTDOWN)
	elif !full and !$Timer.is_stopped():
		$Timer.stop()

func _set_time_text(secs:int) -> void:
	$time.text = "" if secs < 0 else str(secs)


func _join(client_id:int):
	var id = $ItemList.add_item(str(GDSync.player_get_username(client_id)))
	list.append(id)
	plr_list.append(client_id)
	_check_full()
	
func _leave(client_id:int):
	var index = plr_list.find(client_id)
	list.erase(index)
	$ItemList.remove_item(index)
	plr_list.erase(client_id)
	_check_full()


func _on_timer_timeout() -> void:
	if GDSync.is_host():
		GDSync.call_func_all(change_level,maps.pick_random())
	pass # Replace with function body.
	
var started = false

var monster_id:int=0

func set_side():
	if !GDSync.is_host():
		return
	if !Network.forced.is_empty():
		return # testing: roles are forced from the menu
	
	var clients:Array = GDSync.lobby_get_all_clients()
	if clients.is_empty():
		return
	
	# Everyone who did not opt into Survivor-Only is eligible
	var eligible:Array = []
	for c:int in clients:
		if !bool(GDSync.player_get_data(c, "SURVIVOR_ONLY", false)):
			eligible.append(c)
	
	# Fallback: everyone is Survivor-Only, so pick anyone
	if eligible.is_empty():
		eligible = clients.duplicate()
	
	monster_id = eligible.pick_random()
	
	for c:int in clients:
		GDSync.call_func_on(c, set_side_data, c == monster_id)
				
func set_side_data(monster:bool):
	print(monster)
	print("is_monster")
	print("SET SIDE")
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
	if is_instance_valid(survivor_only_toggle):
		survivor_only_toggle.disabled = true
	$Timer.stop()
	GeneralScreen.fade(3)
	await get_tree().create_timer(3).timeout
	if GDSync.is_host():
		Network.change_level(map)


func _on_start_pressed() -> void:
	if GDSync.is_host():
		GDSync.call_func_all(change_level,maps.pick_random())
	pass # Replace with function body.


func _on_item_list_item_selected(_index: int) -> void:
	pass
