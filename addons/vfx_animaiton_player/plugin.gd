@tool
extends EditorPlugin

const VFX_PANEL_NAME = "VfxEditor"

var _vfx_animation_player_plugin

func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	_vfx_animation_player_plugin = load("uid://4porawtlhk1w").new()
	add_child(_vfx_animation_player_plugin)

func _exit_tree() -> void:
	if _vfx_animation_player_plugin:
		_vfx_animation_player_plugin.queue_free()
		_vfx_animation_player_plugin = null


func _handles(object: Object) -> bool:
	return object is AnimationPlayer


func _edit(object: Object) -> void:
	if not Engine.is_editor_hint() or _vfx_animation_player_plugin == null:
		return
	_vfx_animation_player_plugin.set_animation_player(object)


func _apply_changes() -> void:
	if _vfx_animation_player_plugin:
		_vfx_animation_player_plugin.notify_about_to_save()
