@tool
# Derived from Gator Model Studio (c) 2026 Blackwater Gator Studios, MIT License.
# See LICENSE-GatorModelStudio.txt. Modified for GDDraw: renamed classes, mesh-rebuild code removed,
# host hooks added to the editor window.
class_name GDDrawUVBackgroundJob
extends RefCounted


var _mutex: Mutex = Mutex.new()
var _cancel_requested: bool = false
var _progress: float = 0.0
var _stage: String = "Preparing"


func request_cancel() -> void:
	_mutex.lock()
	_cancel_requested = true
	_mutex.unlock()


func is_cancelled() -> bool:
	_mutex.lock()
	var value: bool = _cancel_requested
	_mutex.unlock()
	return value


func update_progress(value: float, stage: String) -> void:
	_mutex.lock()
	_progress = clampf(value, 0.0, 1.0)
	_stage = stage
	_mutex.unlock()


func get_state() -> Dictionary:
	_mutex.lock()
	var state: Dictionary = {
		"cancelled": _cancel_requested,
		"progress": _progress,
		"stage": _stage,
	}
	_mutex.unlock()
	return state
