@icon("res://addons/at-icons/node3d/circuit_board.svg")
class_name TheCube extends Node3D

@export var Output_item:PackedScene

@export var Output_location:Marker3D

@export var Item_create:NodeInstantiator

var all_puzzles:Array[PuzzleBase]

@export var puzzle_count:int=4

var finished_puzzle_count:int=0

var cube_done := false

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
			var puzzle:PuzzleBase = object
			puzzle.puzzle_finished.connect(finish_puzzle)
			all_puzzles.append(puzzle)
	puzzle_count = all_puzzles.size() # always matches the real number of sides

func finish_puzzle():
	finished_puzzle_count += 1
	cube_puzzle_finished.emit()
	if finished_puzzle_count >= puzzle_count and !cube_done:
		cube_done = true
		finish_cube()

func finish_cube():
	print("DONE")
	cube_finished.emit()
	_spawn_reward()

func _spawn_reward() -> void:
	if Output_item == null or Output_location == null:
		push_warning("TheCube: Output Item or Output Location is not set")
		return
	var item := Output_item.instantiate() as Node3D
	item.name = "GeneticMaterial"
	add_child(item)
	item.global_position = Output_location.global_position
