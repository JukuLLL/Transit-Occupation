extends Node

var music_player:AudioStreamPlayer

@export var music_list:Array[AudioStream]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.autoplay = true
	add_child(music_player)
	music_player.stream = music_list.pick_random()
	music_player.play()
	music_player.volume_db = -100
	music_player.finished.connect(_finished)
	create_tween().tween_property(music_player,"volume_db",-30,5)
	pass # Replace with function body.

var previous:AudioStream

func _finished():
	var refreshed=music_list
	refreshed.erase(previous)
	music_player.stream = refreshed.pick_random()
	
