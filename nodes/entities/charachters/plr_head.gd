class_name head extends Node3D

@export_category("Charachter")
@export var first_person_camera:Camera3D
@export var third_person_camera:Marker3D
@export var plr:player
@export var grapple_ray:RayCast3D
@export var monster_grab_ray:RayCast3D
@export var interact_ray:RayCast3D

@export_category("UI")
@export var crosshair:AnimatedSprite2D
@export var health_bar:TextureProgressBar
@export var health_label:Label
@export var interact_label:Label
@export var dash_ring:CooldownRing


func update_health(value:int):
	value = clampi(value,0,INT16_MAX)
	health_bar.value = value
	health_label.text = "%d" % value
	
func update_lives(value:int):
	pass
	#I HAVE NO LIVES COUNTER
	
func update_dash(cooldown:float, max_cooldown:float = 1.0):
	if dash_ring == null:
		return
	dash_ring.progress = 1.0 - cooldown / max_cooldown
	
func allow_interact(U_KEY:String,visibility:bool=false):
	interact_label.text = "Press "+ U_KEY +" to use"
	if visibility:
		create_tween().tween_property(interact_label,"self_modulate:a",255,0.5)
	else:
		create_tween().tween_property(interact_label,"self_modulate:a",0,0.5)

func shake(intensity:float=1):
	Juicee.shake_camera_3d(first_person_camera,intensity,0.2)
	
func _ready() -> void:
	$VC/VoiceChat.set_input_device(AudioServer.input_device)
	GDSync.set_gdsync_owner($VC/VoiceChat,GDSync.get_gdsync_owner(plr))
	update_health(plr.health)
	health_label.position = Vector2(0, health_bar.size.y + 4)
	health_label.size.x = health_bar.size.x
	
func _input(event: InputEvent) -> void:
	if Input.is_action_pressed("VC"):
		$VC/VoiceChat.unmute_microphone()
	else:
		$VC/VoiceChat.mute_microphone()

func enable_monster():
	if plr.monster:
		first_person_camera.set_cull_mask_value(4,false)
		first_person_camera.set_cull_mask_value(10,false)


func _physics_process(delta: float) -> void:
	$CanvasLayer/TextureRect.self_modulate = lerp($CanvasLayer/TextureRect.self_modulate,Color.from_rgba8(255,0,0,0),delta)

func damage_indicator():
	$CanvasLayer/TextureRect.self_modulate += (Color.RED / 4)
