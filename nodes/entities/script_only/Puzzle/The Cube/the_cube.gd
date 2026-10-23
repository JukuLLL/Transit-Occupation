@icon("res://addons/at-icons/node3d/circuit_board.svg")
class_name TheCube extends Node3D

@export var Output_item:PackedScene

@export var Output_location:Marker3D

@export var Item_create:NodeInstantiator

var all_puzzles:Array[PuzzleBase]

@export var puzzle_count:int=4

var finished_puzzle_count:int=0

signal cube_finished

signal cube_puzzle_finished


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.expose_node(self)
	await get_tree().physics_frame
	get_all_puzzles()
	pass # Replace with function body.
	
func get_all_puzzles():
	for object:Node in get_children():
		if object is PuzzleBase:
			var puzzle:PuzzleBase=object
			puzzle.puzzle_finished.connect(finish_puzzle)
			all_puzzles.append(puzzle)

func finish_cube():
	print("DONE")
	GDSync.emit_signal_remote_all(cube_finished)
	
func finish_puzzle():
	finished_puzzle_count += 1
	GDSync.sync_var(self,"finished_puzzle_count")
	GDSync.emit_signal_remote_all(cube_puzzle_finished)
	if finished_puzzle_count >= puzzle_count:
		GDSync.call_func_all(finish_cube)
	
