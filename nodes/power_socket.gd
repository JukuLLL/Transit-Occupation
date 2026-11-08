class_name PowerSocket extends interactable

@export var puzzle:PuzzleBase

func _ready() -> void:
	super()
	KEY = "Right Click"
	add_to_group("power_socket")
	var parent_puzzle := get_parent() as PuzzleBase
	if parent_puzzle != null:
		puzzle = parent_puzzle

func interact(_plr:player) -> void:
	pass

func begin_hold(client_id:int) -> void:
	if puzzle:
		puzzle.request_power(client_id)

func end_hold(client_id:int) -> void:
	if puzzle:
		puzzle.release_power(client_id)
