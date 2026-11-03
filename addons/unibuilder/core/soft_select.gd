@tool
class_name UBSoftSelect
extends RefCounted
## Proportional editing weights: a distance falloff around the selection.


## Falloff curves.
enum Falloff { SMOOTH, SPHERE, ROOT, INVERSE_SQUARE, SHARP, LINEAR, CONSTANT }

## UI labels, indexed by Falloff.
const FALLOFF_NAMES: PackedStringArray = [
	"Smooth", "Sphere", "Root", "Inverse Square", "Sharp", "Linear", "Constant",
]


## Weight for a normalized distance t (0 at the selection, 1 at the radius).
static func falloff_weight(t: float, falloff: int) -> float:
	var x := clampf(1.0 - t, 0.0, 1.0)
	match falloff:
		Falloff.SPHERE:
			return sqrt(x * (2.0 - x))
		Falloff.ROOT:
			return sqrt(x)
		Falloff.INVERSE_SQUARE:
			return x * (2.0 - x)
		Falloff.SHARP:
			return x * x
		Falloff.LINEAR:
			return x
		Falloff.CONSTANT:
			return 1.0
		_:
			return x * x * (3.0 - 2.0 * x)


## Per-vertex drag weights for a proportional drag.
static func weights(positions: PackedVector3Array, selected: Dictionary,
		radius: float, xf: Transform3D = Transform3D.IDENTITY,
		falloff: int = Falloff.SMOOTH) -> Dictionary:
	var out := {}
	for vi in selected:
		if vi >= 0 and vi < positions.size():
			out[vi] = 1.0
	if radius <= 0.0 or out.is_empty():
		return out
	var anchors := PackedVector3Array()
	for vi in out:
		anchors.append(xf * positions[vi])
	for vi in positions.size():
		if out.has(vi):
			continue
		var wp: Vector3 = xf * positions[vi]
		var best := radius
		for a in anchors:
			var d := wp.distance_to(a)
			if d < best:
				best = d
		if best < radius:
			var w := falloff_weight(best / radius, falloff)
			if w > 0.0:
				out[vi] = w
	return out
