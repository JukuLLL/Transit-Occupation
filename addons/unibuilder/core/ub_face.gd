@tool
class_name UBFace
extends Resource
## One n-gon face: an ordered loop of indices into UBMeshData.positions.


@export var vertices := PackedInt32Array()
@export var material_index := 0
## Smoothing group: 0 is hard; faces sharing a nonzero group shade smoothly.
@export var smoothing_group := 0
@export var uv_offset := Vector2.ZERO
@export var uv_rotation := 0.0
@export var uv_scale := Vector2.ONE
## When on, the texture stays put in world space while the face moves.
@export var uv_world_space := false


## Fixed projection direction for auto UVs, in local space. Zero uses the face normal.
@export var uv_axis := Vector3.ZERO


## When on, the face uses its per-corner `uv_coords` instead of auto UVs.
@export var uv_manual := false
@export var uv_coords := PackedVector2Array()
@export var color := Color.WHITE


## Per-corner colors from vertex paint, used instead of `color`.
@export var color_corners := PackedColorArray()


## Returns a copy that owns its vertex loop and per-corner arrays.
func duplicate_face() -> UBFace:
	var d := duplicate() as UBFace
	d.vertices = vertices.duplicate()
	d.uv_coords = uv_coords.duplicate()
	d.color_corners = color_corners.duplicate()
	return d
