class_name showcaser extends Node3D

@export var camera:Camera3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.expose_node(self)
	pass # Replace with function body.
	
func showcase_start():
	camera.make_current()
	$AnimationPlayer.play("showcase")

func _physics_process(delta: float) -> void:
	if Network.game_started:
		$Camera3D/Label.visible = false
		$Camera3D.current = false
		$Camera3D.set_process(false)
		

func fade_screen():
	GeneralScreen.fade(1)
