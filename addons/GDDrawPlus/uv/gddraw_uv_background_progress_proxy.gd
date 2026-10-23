@tool
# Derived from Gator Model Studio (c) 2026 Blackwater Gator Studios, MIT License.
# See LICENSE-GatorModelStudio.txt. Modified for GDDraw: renamed classes, mesh-rebuild code removed,
# host hooks added to the editor window.
class_name GDDrawUVBackgroundProgressProxy
extends GDDrawUVBackgroundJob


var parent_job: GDDrawUVBackgroundJob
var progress_start: float = 0.0
var progress_end: float = 1.0
var stage_prefix: String = ""


func _init(
	new_parent_job: GDDrawUVBackgroundJob = null,
	new_progress_start: float = 0.0,
	new_progress_end: float = 1.0,
	new_stage_prefix: String = ""
) -> void:
	parent_job = new_parent_job
	progress_start = clampf(new_progress_start, 0.0, 1.0)
	progress_end = clampf(new_progress_end, progress_start, 1.0)
	stage_prefix = new_stage_prefix


func request_cancel() -> void:
	if parent_job != null:
		parent_job.request_cancel()


func is_cancelled() -> bool:
	return parent_job != null and parent_job.is_cancelled()


func update_progress(value: float, stage: String) -> void:
	if parent_job == null:
		return
	var mapped_value: float = lerpf(progress_start, progress_end, clampf(value, 0.0, 1.0))
	var mapped_stage: String = stage
	if not stage_prefix.is_empty():
		mapped_stage = "%s: %s" % [stage_prefix, stage]
	parent_job.update_progress(mapped_value, mapped_stage)


func get_state() -> Dictionary:
	if parent_job != null:
		return parent_job.get_state()
	return {"cancelled": false, "progress": 0.0, "stage": "Preparing"}
