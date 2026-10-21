class_name SignalVisualizer extends Node

var _active_lines: Dictionary = {}

const LINE3D_CLASS = "Line3D"

var visible = false

func _ready() -> void:
	Console.add_command("make_signals_visible",_make_signals_visible)
	
func _make_signals_visible():
	await get_tree().process_frame
	if !visible:
		visible = true
		update_visualizations()
		await get_tree().physics_frame
		await get_tree().physics_frame
		_update_line_positions()
	else:
		visible = false
		for key in _active_lines.keys():
			if is_instance_valid(_active_lines[key]):
				_active_lines[key].queue_free()
				_active_lines.erase(key)
		
func update_visualizations() -> void:
	var current_connections: Array = []
	_scan_node_connections(get_tree().root, current_connections)
	
	for key in _active_lines.keys():
		if not key in current_connections:
			if is_instance_valid(_active_lines[key]):
				_active_lines[key].queue_free()
			_active_lines.erase(key)

func _scan_node_connections(node: Node, current_connections: Array) -> void:
	if node == null: return

	var signal_list = node.get_signal_list()
	for sig in signal_list:
		var connections = node.get_signal_connection_list(sig["name"])
		
		for connection in connections:
			var sender = connection["signal"].get_object() as Node3D
			var target_callable = connection["callable"]
			var receiver = await target_callable.get_object() as Node3D
			
			if sender and receiver and sender is Node3D and receiver is Node3D:
				var connection_key = [sender, receiver]
				current_connections.append(connection_key)
				
				if not _active_lines.has(connection_key):
					_create_3d_line(sender, receiver, connection_key)
					
	for child in node.get_children():
		_scan_node_connections(child, current_connections)
func _create_3d_line(sender: Node3D, receiver: Node3D, key: Array) -> void:
	var path_node = Path3D.new()
	var curve = Curve3D.new()
	path_node.curve = curve
	if ClassDB.class_exists(LINE3D_CLASS):
		var line3d_instance = ClassDB.instantiate(LINE3D_CLASS)
		line3d_instance.set("width", 0.1)
		line3d_instance.set("cap_mode", 3)
		var material = StandardMaterial3D.new()
		var random_color = Color(randf_range(10,255),randf_range(10,255),randf_range(10,255))
		material.albedo_color = random_color
		material.emission_enabled = true
		material.emission = random_color * 0.1
		line3d_instance.material_override = material
		path_node.add_child(line3d_instance)
		return


	get_tree().root.add_child(path_node)
	_active_lines[key] = path_node
	
	_set_line_points(path_node, sender.global_position, receiver.global_position)


func _update_line_positions() -> void:
	for key in _active_lines.keys():
		var sender = key[0]
		var receiver = key[1]
		var path_node = _active_lines[key]
		
		if is_instance_valid(sender) and is_instance_valid(receiver) and is_instance_valid(path_node):
			if sender.global_position == receiver.global_position: return
			_set_line_points(path_node, sender.global_position, receiver.global_position)

func _set_line_points(path_node: Path3D, start_pos: Vector3, end_pos: Vector3) -> void:
	var curve = path_node.curve
	curve.clear_points()
	
	curve.add_point(start_pos)
	
	var mid_point = (start_pos + end_pos) / 2.0
	mid_point.y += start_pos.distance_to(end_pos) * 0.15
	curve.add_point(mid_point)
	
	curve.add_point(end_pos)
