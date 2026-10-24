class_name detector extends Area3D

@export var synced:bool=true

@export var detect_nmonster:bool=true
@export var detect_player:bool=true
@export var detect_area:bool=false
@export var is_main:bool=false

signal on_detect_enter

signal on_detect_leave

signal on_leave_all

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.expose_node(self)
	GDSync.expose_var(self,"health")
	body_entered.connect(enter)
	area_entered.connect(enter_area)
	body_exited.connect(leave)
	pass # Replace with function body.
	
func hit():
	pass
	
func get_areas() -> Array:
	return get_overlapping_areas()
	
func enter_area(area:Area3D):
	pass
	
	
func enter(body:Node3D):
	if body is player and GDSync.is_gdsync_owner(body):
		var plr:player=body
		if plr.monster and !detect_nmonster:
			return
		if !plr.monster and !detect_player:
			return
		if synced:
			GDSync.emit_signal_remote_all(on_detect_enter)
		else:
			on_detect_enter.emit()
			
func leave(body:Node3D):
	if body is player and GDSync.is_gdsync_owner(body):
		var plr:player=body
		if plr.monster and !detect_nmonster:
			pass
		elif !plr.monster and !detect_player:
			pass
		elif synced:
			GDSync.emit_signal_remote_all(on_detect_leave)
		else:
			on_detect_leave.emit()
	var players:Array[player]
	for bodies:Node3D in get_overlapping_bodies():
		if bodies is player:
			if bodies.monster and !detect_nmonster:
				pass
			elif !bodies.monster and !detect_player:
				pass
			else:
				players.append(bodies)
	if players.is_empty():
		if synced:
			GDSync.emit_signal_remote_all(on_detect_leave)
		else:
			on_detect_leave.emit()
			
		
