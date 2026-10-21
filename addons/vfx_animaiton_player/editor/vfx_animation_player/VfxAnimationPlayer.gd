@tool
class_name VfxAnimationPlayerPlugin extends Node

var _animation_player_editor: Node
var _pinned_button: Button
var _animation_track_editor: Node
var _animation_player: AnimationPlayer = null
var _last_animation: Animation = null:
	set = _set_last_animation
var _last_seek: float = 0.0
var _vfx_node_map: Dictionary[int, Node] = {}


func set_animation_player(out_player: AnimationPlayer) -> void:
	if not Engine.is_editor_hint():
		return
	if _animation_player == out_player or (_pinned_button and _pinned_button.button_pressed):
		return
	if _animation_player:
		_animation_player.current_animation_changed.disconnect(_on_animation_player_current_animation_changed)
	_animation_player = out_player
	if _animation_player:
		_animation_player.current_animation_changed.connect(_on_animation_player_current_animation_changed)
		_on_animation_player_current_animation_changed(_animation_player.current_animation)


func notify_about_to_save() -> void:
	for vfx_node in _vfx_node_map.values():
		if _is_particles_node(vfx_node):
			vfx_node.emitting = false
			vfx_node.speed_scale = 1.0
	var curr_pos: float = _last_seek
	if _animation_player and _animation_player.current_animation != "":
		_on_timeline_changed(0.0, false, false)
	_on_post_save.call_deferred(curr_pos)
	

func _on_post_save(in_prev_seek: float) -> void:
	for vfx_node in _vfx_node_map.values():
		if _is_particles_node(vfx_node):
			vfx_node.speed_scale = 0.0
	if _animation_player and _animation_player.current_animation != "":
		_on_timeline_changed(in_prev_seek, false, false)


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	var editor_node: Node = get_tree().root.get_child(0)
	var editor_bottom_panel: TabContainer = editor_node.find_child("*EditorBottomPanel*", true, false)
	for child in editor_bottom_panel.get_children(true):
		if child is EditorDock:
			if child.icon_name == &"Animation":
				_animation_player_editor = child
				break
	if _animation_player_editor == null:
		push_error("Animation Player Editor not found!")
		return
	var container: Container =_animation_player_editor.get_child(0, true).get_child(0, true)
	_pinned_button = container.get_child(container.get_child_count(true) - 1)
	if _pinned_button == null:
		push_error("Pinned Button not found in Animation Player Editor!")
	_animation_player_editor.connect("animation_selected", _on_animation_player_current_animation_changed, CONNECT_DEFERRED)
	_animation_track_editor = editor_node.find_child("*AnimationTrackEditor*", true, false)
	if _animation_track_editor == null:
		push_error("Animation Track Editor not found!")
		return
	_animation_track_editor.connect("timeline_changed", _on_timeline_changed)
	_refresh_vfx_list()


func _process(_delta: float) -> void:
	if _animation_player != null and _animation_player.current_animation != "":
		_on_timeline_changed(_animation_player.current_animation_position, false, false)


func _on_timeline_changed(p_pos: float, p_timeline_only: bool, p_update_position_only: bool) -> void:
	if _last_seek == p_pos:
		return
	else:
		for track in _vfx_node_map:
			var vfx_node: Node = _vfx_node_map[track]
			if not _is_particles_node(vfx_node):
				continue
			vfx_node.restart(true)
			var last_start_time = -1.0
			var last_stop_time = 0.0
			if p_pos > 0.0:
				for k: int in _last_animation.track_get_key_count(track):
					if _last_animation.track_get_key_time(track, k) > p_pos:
						break
					if _last_animation.track_get_key_value(track, k):
						last_start_time = _last_animation.track_get_key_time(track, k)
					else:
						last_stop_time = _last_animation.track_get_key_time(track, k)
			vfx_node.emitting = last_start_time >= last_stop_time
			if last_start_time >= 0.0:
				var elapsed_time: float = p_pos - last_start_time
				var trailing_time: float = 0.0
				if last_stop_time > last_start_time:
					elapsed_time = last_stop_time - last_start_time
					trailing_time = p_pos - last_stop_time
				vfx_node.request_particles_process(elapsed_time, trailing_time)
		_last_seek = p_pos


func _on_animation_player_current_animation_changed(in_name: String) -> void:
	if is_instance_valid(_animation_player) and !in_name.is_empty(): # STOP button executes this method with an empty string
		_last_animation = _animation_player.get_animation(in_name) if _animation_player.has_animation(in_name) else null


func _set_last_animation(out_new_animation: Animation) -> void:
	if _last_animation == out_new_animation:
		return
	if _last_animation != null:
		_last_animation.changed.disconnect(_on_animation_changed)
	_last_animation = out_new_animation
	if out_new_animation != null:
		out_new_animation.changed.connect(_on_animation_changed)
	_refresh_vfx_list()
	_on_timeline_changed(0.0, false, false)


func _on_animation_changed() -> void:
	_refresh_vfx_list()


func _refresh_vfx_list() -> void:
	if _animation_player == null:
		return
	var root: Node = _animation_player.get_node_or_null(_animation_player.root_node)
	for track in _vfx_node_map:
		var vfx_node: Node = _vfx_node_map[track]
		if is_instance_valid(vfx_node):
			vfx_node.emitting = false
			vfx_node.speed_scale = 1.0
	_vfx_node_map.clear()
	if _last_animation == null or root == null:
		return
	for track in _last_animation.get_track_count():
		if _last_animation.track_get_type(track) != Animation.TYPE_VALUE:
			continue
		var track_path := String(_last_animation.track_get_path(track))
		if track_path.split(":")[1] != "emitting":
			continue
		var node_path: NodePath = track_path.split(":")[0]
		var vfx_node: Node = root.get_node_or_null(node_path)
		if _is_particles_node(vfx_node):
			_vfx_node_map[track] = vfx_node
			vfx_node.speed_scale = 0.0
			vfx_node.emitting = false
			vfx_node.restart()
	set_process(not _vfx_node_map.is_empty())
	var seek = _last_seek
	_last_seek = -1
	_on_timeline_changed(seek, false, false)


func _is_particles_node(in_node: Node) -> bool:
	return is_instance_valid(in_node) and (
		in_node is CPUParticles2D
		or in_node is CPUParticles3D
		or in_node is GPUParticles2D
		or in_node is GPUParticles3D
	)
