class_name RoundManager extends Node

@export var players_node:plr_list # your player_list node in the map
@export var round_time := 780.0 # 13:00, shorten it in the Inspector for testing
@export var monster_wins_below := 3 # monster wins if fewer survivors than this escape
const RESULTS_TIME := 15.0
const START_GRACE := 3.0 # no "everyone is out" check while players are still spawning

var time_left := 0.0
var running := false # host only
var ending := false  # host only: guards the finish call
var round_ended := false
var grace := 0.0
var check_cd := 0.0
var last_sent := -1
var timer_label:Label

func _ready() -> void:
	Network.round_over = false
	time_left = round_time
	GDSync.expose_func(_set_time)
	GDSync.expose_func(_end_round)
	_build_timer_ui()
	_show_time(ceili(round_time))
	if players_node:
		players_node.game_started.connect(_on_game_started)
	else:
		_on_game_started()

func _on_game_started() -> void:
	if !GDSync.is_host():
		return
	await get_tree().create_timer(1.0).timeout # players spawn 1 second after game_started
	grace = START_GRACE
	running = true

# ---------- Host: authoritative timer and end conditions ----------
func _physics_process(delta:float) -> void:
	if !GDSync.is_host() or !running or ending:
		return
	time_left = maxf(time_left - delta, 0.0)
	var secs := ceili(time_left)
	if secs != last_sent:
		last_sent = secs
		GDSync.call_func_all(_set_time, secs)
	if time_left <= 0.0:
		_host_finish()
		return
	grace = maxf(grace - delta, 0.0)
	check_cd -= delta
	if grace <= 0.0 and check_cd <= 0.0:
		check_cd = 0.25
		if _all_survivors_out():
			_host_finish()

func _get_players() -> Array[player]:
	var out:Array[player] = []
	for n in get_tree().current_scene.find_children("*", "CharacterBody3D", true, false):
		if n is player:
			out.append(n)
	return out

# True when no survivor is still actively participating
func _all_survivors_out() -> bool:
	var survivors := 0
	for p in _get_players():
		if p.monster:
			continue
		survivors += 1
		if !(p.downed or p.trapped or p.dead or p.escaped):
			return false
	return survivors > 0

func _host_finish() -> void:
	if ending:
		return
	ending = true
	var escaped_ids:Array = []
	for p in _get_players():
		if !p.monster and p.escaped and !p.dead: # the monster is never counted
			escaped_ids.append(p.name.to_int())
	var monster_won := escaped_ids.size() < monster_wins_below
	GDSync.call_func_all(_end_round, escaped_ids, monster_won)

# ---------- Every client ----------
func _set_time(secs:int) -> void:
	if !round_ended:
		_show_time(secs)

func _end_round(escaped_ids:Array, monster_won:bool) -> void:
	if round_ended:
		return
	round_ended = true
	running = false
	Network.round_over = true
	
	# Freeze everyone, including dead players' spectator cameras
	for p in _get_players():
		p.velocity = Vector3.ZERO
	for cam in get_tree().current_scene.find_children("*", "FreeLookCamera", true, false):
		cam.process_mode = Node.PROCESS_MODE_DISABLED
	
	# Which role am I?
	var my_id := GDSync.get_client_id()
	var is_monster := my_id == Network.monster_id
	for p in _get_players():
		if p.name.to_int() == my_id:
			is_monster = p.monster
	
	var text:String
	var color:Color
	if is_monster:
		text = "Merciless Victory" if monster_won else "Failure"
		color = Color(0.3, 1.0, 0.3) if monster_won else Color(1.0, 0.25, 0.25)
	else:
		var escaped := escaped_ids.has(my_id) # a survivor only wins by escaping
		text = "Escaped" if escaped else "Lost"
		color = Color(0.3, 1.0, 0.3) if escaped else Color(1.0, 0.25, 0.25)
	
	_apply_blur()
	_show_results(text, color)
	
	await get_tree().create_timer(RESULTS_TIME).timeout
	Network.return_to_menu("")

# ---------- UI ----------
func _build_timer_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	timer_label = Label.new()
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 40)
	timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	timer_label.add_theme_constant_override("outline_size", 8)
	timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(timer_label)
	timer_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	timer_label.offset_top = 16

func _show_time(secs:int) -> void:
	secs = maxi(secs, 0)
	timer_label.text = "%02d:%02d" % [floori(secs / 60.0), secs % 60]
	var c := Color(1.0, 0.3, 0.3) if secs <= 60 else Color.WHITE
	timer_label.add_theme_color_override("font_color", c)

func _apply_blur() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur : hint_range(0.0, 6.0) = 0.0;
void fragment() {
	COLOR = textureLod(screen_tex, SCREEN_UV, blur);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	layer.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	create_tween().tween_property(mat, "shader_parameter/blur", 3.5, 0.6)

func _show_results(text:String, color:Color) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50 # above the blur, so the text stays sharp
	add_child(layer)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	label.position = Vector2(40, 40)
