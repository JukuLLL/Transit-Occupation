@icon("res://addons/at-icons/node3d/voxels.svg")
class_name PuzzleBase extends Node3D

@export_category("General Puzzle Settings")

@export var synced:bool=true

@export var puzzle_name:String="ABC"

@export_category("Puzzle Parts")

@export var interactables:Array[interactable]
@export var breakables:Array[breakable]
@export var damagers:Array[Damager]
@export var timed_damagers:Array[TimedDamager]


var finished:bool=false

signal puzzle_finished

signal puzzle_started

func _ready() -> void:
	GDSync.expose_node(self)
	GDSync.expose_var(self,"finished")

func finish_puzzle():
	if finished: return
	finished = true
	if synced:
		GDSync.sync_var(self,"finished")
		GDSync.emit_signal_remote_all(puzzle_finished)
	else:
		puzzle_finished.emit()
		
func start_puzzle():
	if synced:
		GDSync.emit_signal_remote_all(puzzle_started)
	else:
		puzzle_started.emit()
