class_name MonsterSelectMenu extends CanvasLayer

signal chosen(index:int)

var monsters:Array[MonsterDef] = []
var duration := 30.0

var time_left := 0.0
var timer_label:Label
var name_label:Label
var desc_label:Label
var preview_holder:Node3D
var extras:VBoxContainer # future: cosmetics and equippable powers go in here

func _ready() -> void:
	layer = 20
	time_left = duration
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.06, 1.0)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)
	
	var title := Label.new()
	title.text = "CHOOSE YOUR MONSTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	root.add_child(title)
	
	timer_label = Label.new()
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 34)
	root.add_child(timer_label)
	
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 32)
	root.add_child(row)
	
	# Left: the list of monsters
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(340, 0)
	list.add_theme_constant_override("separation", 12)
	row.add_child(list)
	var group := ButtonGroup.new()
	for i in monsters.size():
		var b := Button.new()
		b.text = monsters[i].display_name
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 80)
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(_select.bind(i))
		list.add_child(b)
		if i == 0:
			b.button_pressed = true
	
	# Middle: rotating 3D preview in its own world
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	svc.add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.3, 3.8)
	cam.rotation_degrees.x = -8
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	vp.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2, 2, 3)
	vp.add_child(fill)
	preview_holder = Node3D.new()
	vp.add_child(preview_holder)
	
	# Right: details, plus a spot for future sections
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(380, 0)
	info.add_theme_constant_override("separation", 12)
	row.add_child(info)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 40)
	info.add_child(name_label)
	desc_label = Label.new()
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 22)
	info.add_child(desc_label)
	extras = VBoxContainer.new()
	info.add_child(extras)
	
	if monsters.is_empty():
		name_label.text = "Default Monster"
	else:
		_show(0)

func _show(i:int) -> void:
	var def := monsters[i]
	name_label.text = def.display_name
	desc_label.text = def.description
	for c in preview_holder.get_children():
		c.queue_free()
	if def.preview_scene:
		preview_holder.add_child(def.preview_scene.instantiate())

func _select(i:int) -> void:
	_show(i)
	chosen.emit(i)

func _process(delta:float) -> void:
	time_left = maxf(time_left - delta, 0.0)
	timer_label.text = "Spawning in %d" % ceili(time_left)
	preview_holder.rotate_y(delta * 0.6)

func close() -> void:
	queue_free()
