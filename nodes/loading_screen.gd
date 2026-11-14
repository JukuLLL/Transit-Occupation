extends Control

const BACKGROUND_PATH := "res://textures/UI/TransitLoadingScreen.png"
const MENU_PATH := "res://menus/menu.scn"
# Also loaded during the loading screen (lobby scene and map)
const PRELOAD_PATHS := ["uid://dhy3uk4ck23ud", "uid://xujj17tg66nh"]

const MIN_TIME := 2.5   # the bar never fills faster than this (seconds)
const BAR_SPEED := 0.6  # how fast the bar can move (fraction per second)
# Set to true to skip this screen when running from the editor (useful with many test windows)
const SKIP_IN_EDITOR := false

var bar:ProgressBar
var prompt:Label
var fade:ColorRect

var all_paths:Array = []
var menu_scene:PackedScene
var loaded:Array = []
var shown := 0.0
var elapsed := 0.0
var ready_to_play := false
var starting := false

func _ready() -> void:
	if SKIP_IN_EDITOR and OS.has_feature("editor"):
		get_tree().change_scene_to_file.call_deferred(MENU_PATH)
		return
	
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var black := ColorRect.new()
	black.color = Color.BLACK
	add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	if ResourceLoader.exists(BACKGROUND_PATH):
		var bg := TextureRect.new()
		bg.texture = load(BACKGROUND_PATH)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(bg)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		push_warning("Loading screen image not found: " + BACKGROUND_PATH)
	
	bar = ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.001
	bar.show_percentage = false
	var back_style := StyleBoxFlat.new()
	back_style.bg_color = Color(0, 0, 0, 0.6)
	bar.add_theme_stylebox_override("background", back_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.85, 0.2, 0.2)
	bar.add_theme_stylebox_override("fill", fill_style)
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 120
	bar.offset_right = -120
	bar.offset_top = -70
	bar.offset_bottom = -56
	
	prompt = Label.new()
	prompt.text = "Press SPACE to play"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 36)
	prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt.add_theme_constant_override("outline_size", 10)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.visible = false
	add_child(prompt)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	prompt.offset_top = -140
	prompt.offset_bottom = -90
	
	# Fade-to-black layer, on top of everything
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	all_paths = [MENU_PATH] + PRELOAD_PATHS
	for p in all_paths:
		ResourceLoader.load_threaded_request(p)

func _process(delta: float) -> void:
	if ready_to_play or starting or bar == null:
		return
	elapsed += delta
	
	var total := 0.0
	var all_done := true
	for p in all_paths:
		var prog := []
		var status := ResourceLoader.load_threaded_get_status(p, prog)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				all_done = false
				total += prog[0]
			ResourceLoader.THREAD_LOAD_LOADED:
				total += 1.0
			_:
				push_error("Loading failed: " + p)
				total += 1.0 # never hang on a failed file
	
	var real := total / all_paths.size()
	var target := minf(real, elapsed / MIN_TIME)
	shown = move_toward(shown, target, BAR_SPEED * delta)
	bar.value = shown
	
	if all_done and shown >= 0.999:
		_finish_loading()

func _finish_loading() -> void:
	for p in all_paths:
		var r = ResourceLoader.load_threaded_get(p)
		if r == null:
			continue
		loaded.append(r)
		if p == MENU_PATH:
			menu_scene = r as PackedScene
	# Keep the loaded resources in memory so later scene changes are instant
	get_tree().root.set_meta("preloaded_resources", loaded)
	
	ready_to_play = true
	prompt.visible = true
	var tw := create_tween().set_loops()
	tw.tween_property(prompt, "modulate:a", 0.35, 0.8)
	tw.tween_property(prompt, "modulate:a", 1.0, 0.8)

func _unhandled_input(event: InputEvent) -> void:
	if !ready_to_play or starting:
		return
	if event is InputEventKey and event.pressed and !event.echo and event.keycode == KEY_SPACE:
		_start_game()

func _start_game() -> void:
	starting = true
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.8)
	await tw.finished
	if menu_scene != null:
		get_tree().change_scene_to_packed(menu_scene)
	else:
		get_tree().change_scene_to_file(MENU_PATH)
