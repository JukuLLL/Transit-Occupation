extends Node

var particles:Dictionary

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var dir := DirAccess.open("res://nodes/Particles/Scenes/")
	if dir == null: printerr("Could not open folder"); return
	dir.list_dir_begin()
	for file: String in dir.get_files():
		var scene := load(dir.get_current_dir() + "/" + file)
		particles.assign({scene.resource_name.to_upper():scene})
	print(particles)
	pass # Replace with function body.

func load_particle(particle_name:String) -> PackedScene:
	particle_name = particle_name.to_upper()
	var particle_key:String
	for key:String in particles.keys():
		if key.to_upper() == particle_name:
			particle_key = key
			continue
	var scene:PackedScene=particles.get(particle_key)
	return scene
	
