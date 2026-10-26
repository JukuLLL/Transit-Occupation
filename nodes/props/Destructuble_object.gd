@icon("res://addons/at-icons/node3d/edge.svg")
class_name Destructuble_object extends StaticBody3D

@export var trigger:breakable

@export var break_sound:AudioStream
@export var destroy_sound:AudioStream

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	trigger.on_break.connect(_destroy)
	trigger.on_damage.connect(_hit)


func _hit():
	if break_sound:
		play_sound(break_sound)

func _destroy():
	if destroy_sound:
		play_sound(destroy_sound)
	queue_free()

func play_sound(sound:AudioStream):
	var audio:SFXSound=SFXSound.new()
	add_sibling(audio)
	audio.stream = sound
	audio.play()
