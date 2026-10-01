extends Node3D

@export var base_player:PackedScene

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GDSync.client_joined.connect(join)
	pass # Replace with function body.



func join(client_id:int) -> void:
	var plr:player=base_player.instantiate()
	print("create_plr " + str(client_id))
	add_child(plr)
	plr.name = str(client_id)
	GDSync.set_gdsync_owner(plr,client_id)
	pass
