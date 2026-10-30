class_name VisionPuzzle extends PuzzleBase

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super() # runs PuzzleBase._ready (exposes the node and "finished")
	start_vision_pos = vision.position
	power_changed.connect(_on_power_changed)

func _on_power_changed(powered:bool) -> void:
	if !powered and !finished:
		timer.stop()
		lose.stop()
		times = 0
		lerper = 0.0

@export var timer: Timer
@export var lose: Timer
@export var held_for:float=5
@export var spots: Node3D
@export var vision: Decal
@export var progress: Label3D
@export var range_x:float=0.5
@export var range_y:float=0.5
var times:float=0

var current_pos:Vector3

var lerp_Start:Vector3

var start_vision_pos:Vector3

func get_pos_in_list() -> Vector3:
	var marker:Vector3=start_vision_pos + Vector3(0,randf_range(-range_y,range_y),randf_range(-range_x,range_x))
	return marker

	pass # Replace with function body.

func _on_timer_timeout() -> void:
	if worker == 0:
		timer.stop()
		times = 0
		lerper = 0.0
		return
	if !finished:
		times += 1
	if times >= held_for:
		finish_puzzle()


func _on_interactable_interest_lost() -> void:
	if !finished:
		timer.stop()
		times = 0
		lerper = 0.0
	pass # Replace with function body.

func _process(delta: float) -> void:
	progress.text = str(times)
	
var lerper:float=0.0

func _on_interactable_interacting_held(player_node_path: NodePath) -> void:
	print("4: held, is_worker = ", is_worker(player_node_path)) #TESTING
	if !is_worker(player_node_path):
		return
	print("connect")
	if !finished:
		if timer.is_stopped():
			timer.start()
			lose.start()
		if lerp_Start == null or vision.position.is_equal_approx(current_pos):
			lerp_Start = vision.position
			current_pos = get_pos_in_list()
			lerper = 0.0
			
		lerper = clampf(lerper,0,1)
		vision.position = lerp(lerp_Start,current_pos,lerper)
		lerper += 0.01
	pass # Replace with function body.


func _on_lose_timeout() -> void:
	if !finished:
		lerper = 0.0
		lerp_Start = vision.position
		current_pos = get_pos_in_list()
		times = 0
	pass # Replace with function body.
