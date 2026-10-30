class_name PowerSocket extends interactable

@export var puzzle:PuzzleBase

func _ready() -> void:
	super()
	KEY = "Right Click"
	add_to_group("power_socket")
	# Always use the puzzle this socket belongs to, whatever the slot says
	var parent_puzzle := get_parent() as PuzzleBase
	if parent_puzzle != null:
		puzzle = parent_puzzle
	if puzzle:
		puzzle.power_changed.connect(_on_power_changed)

func _on_power_changed(powered:bool) -> void:
	# While powered, let the interact ray pass through to the puzzle behind it
	for shape in find_children("*", "CollisionShape3D"):
		shape.set_deferred("disabled", powered)

func interact(_plr:player) -> void:
	pass

func begin_hold(client_id:int) -> void:
	print("2: begin_hold, puzzle = ", puzzle.get_path() if puzzle else "none") #TESTING
	if puzzle:
		puzzle.request_power(client_id)

func end_hold(client_id:int) -> void:
	if puzzle:
		puzzle.release_power(client_id)
