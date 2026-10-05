class_name Collision_ab
extends Resource

@export_flags_3d_physics var physics_layer:int

@export var aabb:AABB


@export var shape:Shape3D

func set_abb_pos(pos:Vector3):
	aabb.position = pos


func is_point_colliding(pos:Vector3,Collider_aabb:Collision_ab) -> bool:
	aabb.size = shape.get("size")
	Collider_aabb.aabb.size = Collider_aabb.shape.get("size")
	if Collider_aabb.aabb.intersects(aabb):
			if Collider_aabb.physics_layer == physics_layer:
				return true
	return false
