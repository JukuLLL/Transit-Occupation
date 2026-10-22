class_name TestPuzlle extends PuzzleBase

var hold_time:float=0

var allow_press:bool=false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func _process(delta: float) -> void:
	$Label3D.text = str(hold_time)

func _on_interactable_interacting_held() -> void:
	if !finished and allow_press:
		hold_time += 0.5
	if hold_time > 100:
		finish_puzzle()
	pass # Replace with function body.


func _on_interactable_interest_lost() -> void:
	if !finished:
		hold_time = 0
		allow_press = false
	pass # Replace with function body.


func _on_point_grabbled() -> void:
	allow_press = true
	await get_tree().create_timer(2).timeout
	if !hold_time > 0:
		allow_press = false
	pass # Replace with function body.
