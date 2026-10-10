class_name head extends Node3D

@export var first_person_camera:Camera3D
@export var third_person_camera:Marker3D
@export var plr:player
@export var grapple_ray:RayCast3D
@export var grapplle_line:Line2D
@export var monster_grab_ray:RayCast3D

@export var crosshair:AnimatedSprite2D

@export var camera_shake_node:CameraShake3DNode

func shake(intensity:float=1):
	camera_shake_node._custom_shake(1 * intensity,1 * intensity)

func enable_monster():
	if plr.monster:
		first_person_camera.set_cull_mask_value(4,false)
		first_person_camera.set_cull_mask_value(10,false)


func _physics_process(delta: float) -> void:
	$CanvasLayer/TextureRect.self_modulate = lerp($CanvasLayer/TextureRect.self_modulate,Color.from_rgba8(255,0,0,0),delta)

func damage_indicator():
	$CanvasLayer/TextureRect.self_modulate += (Color.RED / 4)
