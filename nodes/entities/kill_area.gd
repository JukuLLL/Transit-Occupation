extends Area3D

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("plr"):
		GeneralScreen.fade(0.5)
		await get_tree().create_timer(0.5).timeout
		body.position = Vector3.ZERO
	pass # Replace with function body.
