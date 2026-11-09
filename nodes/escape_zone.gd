class_name EscapeZone extends Area3D

@export var starts_active := false

func _ready() -> void:
	add_to_group("escape_zone")
	set_active(starts_active)

# Runs on every client
func set_active(on:bool) -> void:
	visible = on
	monitoring = on
	monitorable = on
	for s in find_children("*", "CollisionShape3D", true, false):
		s.set_deferred("disabled", !on)
