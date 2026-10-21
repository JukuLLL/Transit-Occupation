class_name TestPuzlle extends PuzzleBase

var hold_time:float=0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func _process(delta: float) -> void:
	$Label3D.text = str(hold_time)

func _on_interactable_interacting_held() -> void:
	if !finished:
		hold_time += 0.5
	if hold_time > 100:
		finish_puzzle()
	pass # Replace with function body.


func _on_interactable_interest_lost() -> void:
	if !finished:
		hold_time = 0
	pass # Replace with function body.
