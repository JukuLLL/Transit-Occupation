class_name TeammateHud extends CanvasLayer

const MAX_SLOTS := 5
const MAX_HEALTH := 100.0
const RING_SIZE := 64.0

var me:player
var column:VBoxContainer
var rows:Dictionary = {} # client id -> row


# A ring that drains as health drops, with the health number in the middle
class HealthRing extends Control:
	var value := 1.0:
		set(v):
			value = clampf(v, 0.0, 1.0)
			queue_redraw()
	var label:Label
	
	func _ready() -> void:
		label = Label.new()
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		add_child(label)
	
	func _draw() -> void:
		var center := size / 2
		var radius := minf(size.x, size.y) / 2 - 5
		# Dim background ring
		draw_arc(center, radius, 0, TAU, 64, Color(1, 1, 1, 0.25), 6, true)
		# Health arc, red when low and green when full
		if value > 0.0:
			var color := Color.from_hsv(value * 0.33, 0.8, 1.0)
			draw_arc(center, radius, -PI / 2, -PI / 2 + TAU * value, 64, color, 6, true)


func _ready() -> void:
	layer = 2
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	column.offset_left = 24
	column.grow_vertical = Control.GROW_DIRECTION_BOTH


func _process(_delta:float) -> void:
	if !is_instance_valid(me) or me.get_parent() == null:
		return
	if !is_inside_tree(): return
	
	# Every other survivor in the match, in a stable order
	var mates:Array = []
	for n in me.get_parent().get_children():
		if n is player and n != me and !n.monster:
			mates.append(n)
	mates.sort_custom(func(a, b): return a.name.to_int() < b.name.to_int())
	mates = mates.slice(0, MAX_SLOTS)
	
	# Remove rows for players who left
	var ids:Array = mates.map(func(m): return m.name.to_int())
	for id in rows.keys():
		if id not in ids:
			rows[id].queue_free()
			rows.erase(id)
	
	# Add and update rows
	for i in mates.size():
		var mate:player = mates[i]
		var id := mate.name.to_int()
		if !rows.has(id):
			rows[id] = _make_row(id)
		var row:VBoxContainer = rows[id]
		column.move_child(row, i)
		
		var hp := maxi(mate.health, 0)
		var ring:HealthRing = row.get_child(1)
		ring.value = hp / MAX_HEALTH
		ring.label.text = str(hp)
		row.modulate = Color(1, 1, 1, 0.4) if hp <= 0 else Color.WHITE # dim dead teammates


func _make_row(id:int) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Name on top
	var name_label := Label.new()
	var username := str(GDSync.player_get_username(id))
	name_label.text = username if username != "" else "Player"
	name_label.custom_minimum_size = Vector2(100, 0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 6)
	row.add_child(name_label)
	
	# Ring below the name
	var ring := HealthRing.new()
	ring.custom_minimum_size = Vector2(RING_SIZE, RING_SIZE)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ring)
	
	column.add_child(row)
	return row
