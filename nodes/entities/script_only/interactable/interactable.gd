@icon("res://addons/at-icons/node3d/hand.svg")
class_name interactable extends Area3D

@export var KEY:String="Left Click"

@export var hold:bool=false

@export var toggle:bool=false

signal interacting(player_node_path:NodePath)

signal interacting_toggle(toggle:bool,player_node_path:NodePath)

signal interacting_held(player_node_path:NodePath)

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
	set_collision_layer_value(1,false)
	set_collision_layer_value(2,true)
	set_collision_layer_value(30,true)
	collision_mask = collision_layer
	pass # Replace with function body.
	
func _physics_process(delta: float) -> void:
	if hold_frames > 1:
		hold_frames -= 1
		if local_plr_node:
			if synced:
				GDSync.emit_signal_remote_all(interacting_held,local_plr_node.get_path())
			else:
				interacting_held.emit(local_plr_node.get_path())
		if hold_frames < 1:
			lose_focus()
	
var local_plr_node:player

func interact(plr_node:player):
	local_plr_node = plr_node
	if hold:
		focused = true
		hold_frames = 2
	elif !focused:
		focused = true
		if toggle:
			if synced:
				GDSync.emit_signal_remote_all(interacting_toggle,!toggle_state,plr_node.get_path())
				toggle_state = !toggle_state
			else:
				interacting_toggle.emit(!toggle_state,plr_node.get_path())
				toggle_state = !toggle_state
		else:
			if synced:
				GDSync.emit_signal_remote_all(interacting,plr_node.get_path())
			else:
				interacting.emit(plr_node.get_path())
		
		
func lose_focus():
	if focused:
		focused = false
		interest_lost.emit()
