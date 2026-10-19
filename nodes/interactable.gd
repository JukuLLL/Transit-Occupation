class_name interactable extends Area3D

@export var KEY:String="Left Click"

@export var hold:bool=false

signal interacting

signal interacting_held

signal interest_lost

var hold_frames = 0

var focused = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	interacting.connect(func(): print("interact_one"))
	interacting_held.connect(func(): print("interact_held"))
	interest_lost.connect(func(): print("interact_lost"))
	pass # Replace with function body.
	
func _physics_process(delta: float) -> void:
	if hold_frames > 1:
		hold_frames -= 1
		interacting_held.emit()
		if hold_frames < 1:
			lose_focus()
	


func interact():
	if hold:
		focused = true
		hold_frames = 2
	elif !focused:
		focused = true
		interacting.emit()
		
func lose_focus():
	if focused:
		focused = false
		interest_lost.emit()
