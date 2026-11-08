class_name PowerSocket extends interactable

@export var puzzle:PuzzleBase
@export var spin_speed := 3.0       # radians per second while powered
@export var spin_ramp := 6.0        # how quickly it speeds up and slows down

var spin_now := 0.0
var spin_node:Node3D

func _ready() -> void:
	super()
	KEY = "Right Click"
	add_to_group("power_socket")
	var parent_puzzle := get_parent() as PuzzleBase
	if parent_puzzle != null:
		puzzle = parent_puzzle
	spin_node = find_child("MeshInstance3D", false, false) as Node3D

func _process(delta:float) -> void:
	if puzzle == null or spin_node == null:
		return
	var target := spin_speed if puzzle.worker != 0 else 0.0
	spin_now = move_toward(spin_now, target, spin_ramp * delta)
	if spin_now > 0.001:
		spin_node.rotate_y(spin_now * delta)

func interact(_plr:player) -> void:
	pass

func begin_hold(client_id:int) -> void:
	if puzzle:
		puzzle.request_power(client_id)

func end_hold(client_id:int) -> void:
	if puzzle:
		puzzle.release_power(client_id)
