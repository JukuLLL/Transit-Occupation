class_name PlayMenu extends Control

signal closed

const POLL_TIME := 3.0

var panel:PanelContainer
var buttons:Dictionary = {} # id -> Button
var status_label:Label
var busy := false

# Add future modes here (for example Friends Only) plus a branch in _on_option()
func _get_options() -> Array[Dictionary]:
	return [
		{"id": "host", "text": "Host Game"},
		{"id": "quick", "text": "Quick Play  •  …"},
	]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP # blocks the main menu buttons behind it
	
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.92)
	style.border_color = Color(0.85, 0.2, 0.2)
	style.border_width_top = 4
	style.set_corner_radius_all(6)
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 32
	style.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	
	var title := Label.new()
	title.text = "PLAY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	box.add_child(title)
	
	for opt in _get_options():
		var b := Button.new()
		b.text = opt["text"]
		b.custom_minimum_size = Vector2(460, 90)
		b.add_theme_font_size_override("font_size", 30)
		b.pressed.connect(_on_option.bind(opt["id"]))
		box.add_child(b)
		buttons[opt["id"]] = b
	
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.custom_minimum_size = Vector2(0, 28)
	status_label.add_theme_color_override("font_color", Color(1, 0.6, 0.6))
	box.add_child(status_label)
	
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 50)
	back.pressed.connect(close)
	box.add_child(back)
	
	# Live lobby counter: poll while this menu is open
	Network.lobby_count_changed.connect(_on_count)
	var timer := Timer.new()
	timer.wait_time = POLL_TIME
	timer.timeout.connect(func(): if !busy: Network.refresh_lobby_count())
	add_child(timer)
	timer.start()
	Network.refresh_lobby_count() # also opens the connection
	
	# Fade and slide in
	modulate.a = 0.0
	panel.position.y += 30
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.25)
	tw.tween_property(panel, "position:y", panel.position.y - 30, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_count(count:int) -> void:
	if buttons.has("quick"):
		buttons["quick"].text = "Quick Play  •  %d %s" % [count, "lobby" if count == 1 else "lobbies"]

func _set_busy(value:bool, message:String = "") -> void:
	busy = value
	for b in buttons.values():
		b.disabled = value
	status_label.text = message

func _on_option(id:String) -> void:
	if busy:
		return
	match id:
		"host":
			_set_busy(true, "Creating lobby...")
			Network.create_lobby(false, Network.LobbyMode.PUBLIC)
		"quick":
			_set_busy(true, "Searching for a lobby...")
			var ok:bool = await Network.quick_play()
			if !ok:
				_set_busy(false, "No open lobbies found. Try again or host your own.")

func close() -> void:
	if busy:
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	await tw.finished
	closed.emit()
	queue_free()
