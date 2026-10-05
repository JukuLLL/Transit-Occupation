extends Node3D

@export var first_person_camera:Camera3D
@export var third_person_camera:Camera3D
@export var plr:player
@export var grapple_ray:RayCast3D
@export var grapplle_line:Line2D
@export var monster_grab_ray:RayCast3D

@export var crosshair:AnimatedSprite2D


func enable_monster():
	if plr.monster:
		$monster_vision_modifier/TextureRect.visible = true
	else:
		$monster_vision_modifier/TextureRect.queue_free()
