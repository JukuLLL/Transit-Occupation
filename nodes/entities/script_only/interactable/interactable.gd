@icon("res://addons/at-icons/node3d/hand.svg")
class_name interactable extends Area3D

@export var KEY:String="Left Click"

@export var hold:bool=false

@export var toggle:bool=false

signal interacting

signal interacting_toggle(toggle:bool)

signal interacting_held

signal interest_lost

var hold_frames = 0

var focused = false

var toggle_state=false

@export var synced:bool=true

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.expose_signal(interacting)
	GDSync.expose_signal(interacting_held)
	GDSync.expose_signal(interest_lost)
	GDSync.expose_signal(interacting_toggle)
	interacting.connect(func(): print("interact_one"))
	interacting_held.connect(func(): print("interact_held"))
	interest_lost.connect(func(): print("interact_lost"))
	pass # Replace with function body.
	
func _physics_process(delta: float) -> void:
	if hold_frames > 1:
		hold_frames -= 1
		if synced:
			GDSync.emit_signal_remote_all(interacting_held)
		else:
			interacting_held.emit()
		if hold_frames < 1:
			lose_focus()
	


func interact():
	if hold:
		focused = true
		hold_frames = 2
	elif !focused:
		focused = true
		if toggle:
			if synced:
				GDSync.emit_signal_remote_all(interacting_toggle,!toggle_state)
				toggle_state = !toggle_state
			else:
				interacting_toggle.emit(!toggle_state)
				toggle_state = !toggle_state
		else:
			if synced:
				GDSync.emit_signal_remote_all(interacting)
			else:
				interacting.emit()
		
		
func lose_focus():
	if focused:
		focused = false
		interest_lost.emit()
