@icon("res://addons/at-icons/node3d/edge.svg")
class_name Destructuble_object extends StaticBody3D

@export var trigger:breakable

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	trigger.on_break.connect(_destroy)
	pass # Replace with function body.


func _destroy():
	queue_free()
