class_name DeathNotice extends CanvasLayer

const SOUND_PATH := "res://nodes/entities/script_only/Sounds/deadnotification.wav"
const SHOW_TIME := 4.0

static var stack_count := 0 # lets two deaths in a row sit one above the other

var message := ""

func _ready() -> void:
	layer = 30 # above the HUD, below the end-of-round results
	
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.75) # slightly transparent gray
	style.border_color = Color(0.75, 0.75, 0.75)
	style.border_width_top = 1 # thin border on the top and bottom edges
	style.border_width_bottom = 1
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	
	var label := Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 26)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	
	# Full width bar, slightly above the center of the screen
	var screen := get_viewport().get_visible_rect().size
	panel.custom_minimum_size.x = screen.x
	await get_tree().process_frame # wait one frame so the panel knows its height
	var offset_y := stack_count * (panel.size.y + 8.0)
	stack_count += 1
	panel.position = Vector2(0.0, screen.y * 0.3 + offset_y)
	
	# Sound plays at the same moment the box appears
	var stream = load(SOUND_PATH)
	if stream != null:
		var sfx := AudioStreamPlayer.new()
		sfx.stream = stream
		add_child(sfx)
		sfx.play()
	
	# Fade in, hold, fade out
	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.2)
	tw.tween_interval(SHOW_TIME)
	tw.tween_property(panel, "modulate:a", 0.0, 0.5)
	await tw.finished
	stack_count = maxi(stack_count - 1, 0)
	queue_free()
