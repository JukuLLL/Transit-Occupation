@tool
class_name UBGizmoMath
extends RefCounted
## Screen and ray math shared by the move, scale and material-mode gizmos.


## Parameter t of the point on pivot + axis * t closest to the cursor ray.
static func ray_line_t(camera: Camera3D, pos: Vector2, pivot: Vector3, axis: Vector3) -> float:
	var o := camera.project_ray_origin(pos)
	var d := camera.project_ray_normal(pos)
	var w := pivot - o
	var b := axis.dot(d)
	var denom := 1.0 - b * b
	if absf(denom) < 1e-6:
		return NAN
	return (b * d.dot(w) - axis.dot(w)) / denom


## Unit screen direction of a world axis at the pivot, or zero if it points at the camera.
static func screen_dir(camera: Camera3D, pivot: Vector3, axis: Vector3) -> Vector2:
	var k := maxf(0.001, camera.global_position.distance_to(pivot) * 0.01)
	var probe := pivot + axis * k
	if camera.is_position_behind(probe):
		return Vector2.ZERO
	var v := camera.unproject_position(probe) - camera.unproject_position(pivot)
	return v.normalized() if v.length() > 1e-3 else Vector2.ZERO


## Arm length fraction below which an arm is hidden and cannot be grabbed.
const ARM_HIDE_FRAC := 0.12
const ARM_SOLID_FRAC := 0.35


## Screen vector of a gizmo arm along a world axis, foreshortened by perspective.
static func screen_arm(camera: Camera3D, pivot: Vector3, axis: Vector3, len_px: float) -> Vector2:
	var k := maxf(0.001, camera.global_position.distance_to(pivot) * 0.01)
	var probe := pivot + axis.normalized() * k
	if camera.is_position_behind(probe):
		return Vector2.ZERO
	var at := camera.unproject_position(pivot)
	var across := camera.unproject_position(pivot + camera.global_transform.basis.x * k).distance_to(at)
	if across < 1e-6:
		return Vector2.ZERO
	var v := (camera.unproject_position(probe) - at) * (len_px / across)
	return v if v.length() >= len_px * ARM_HIDE_FRAC else Vector2.ZERO


## Opacity for an arm from screen_arm, fading out nearly view-parallel ones.
static func arm_alpha(arm: Vector2, len_px: float) -> float:
	return clampf((arm.length() / len_px - ARM_HIDE_FRAC) / (ARM_SOLID_FRAC - ARM_HIDE_FRAC), 0.0, 1.0)
