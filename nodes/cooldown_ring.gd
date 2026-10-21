class_name CooldownRing extends Control

@export var radius := 30.0
@export var thickness := 6.0
@export var ring_color := Color.WHITE
@export var back_color := Color(1, 1, 1, 0.25)

var progress := 1.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()

func _draw() -> void:
	var center := size / 2
	draw_arc(center, radius, 0, TAU, 64, back_color, thickness, true)
	if progress > 0.0:
		draw_arc(center, radius, -PI / 2, -PI / 2 + TAU * progress, 64, ring_color, thickness, true)
