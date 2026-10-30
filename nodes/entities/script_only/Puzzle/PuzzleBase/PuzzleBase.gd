@icon("res://addons/at-icons/node3d/voxels.svg")
class_name PuzzleBase extends Node3D

@export_category("General Puzzle Settings")

@export var synced:bool=true
@export var enabled:bool=true

@export var puzzle_name:String="ABC"

@export_category("Puzzle Parts")

@export var interactables:Array[interactable]
@export var breakables:Array[breakable]
@export var damagers:Array[Damager]
@export var timed_damagers:Array[TimedDamager]


var finished:bool=false

signal puzzle_finished

signal puzzle_started

func _ready() -> void:
	GDSync.expose_node(self)
	GDSync.expose_var(self,"finished")
	GDSync.client_left.connect(_on_client_left)

func finish_puzzle():
	if finished: return
	finished = true
	if synced:
		GDSync.sync_var(self,"finished")
		GDSync.emit_signal_remote_all(puzzle_finished)
	else:
		puzzle_finished.emit()
		
func start_puzzle():
	if synced:
		GDSync.emit_signal_remote_all(puzzle_started)
	else:
		puzzle_started.emit()
		
var worker:int = 0 # client id of the player powering this side, 0 = nobody

signal power_changed(powered:bool)

func request_power(client_id:int) -> void:
	if finished: return
	_to_host(_host_request_power, client_id)

func release_power(client_id:int) -> void:
	_to_host(_host_release_power, client_id)

func _to_host(callable:Callable, client_id:int) -> void:
	if GDSync.is_host():
		callable.call(client_id)
	else:
		GDSync.call_func_on(GDSync.get_host(), callable, client_id)

func _host_request_power(client_id:int) -> void:
	if worker == 0 or worker == client_id:
		GDSync.call_func_all(_set_worker, client_id)

func _host_release_power(client_id:int) -> void:
	if worker == client_id:
		GDSync.call_func_all(_set_worker, 0)

func _set_worker(client_id:int) -> void:
	print("3: worker is now ", client_id)
	var was_powered := worker != 0
	worker = client_id
	if was_powered != (worker != 0):
		power_changed.emit(worker != 0)

func is_worker(plr_path:NodePath) -> bool:
	var plr := get_node_or_null(plr_path) as player
	if plr == null or worker == 0 or plr.name.to_int() != worker:
		return false
	# On the holder's own machine, also require that they are still holding the socket
	if GDSync.is_gdsync_owner(plr):
		return is_instance_valid(plr.held_socket) and plr.held_socket.puzzle == self
	return true

func _on_client_left(client_id:int) -> void:
	# If the player powering a side leaves, free it
	if GDSync.is_host() and client_id == worker:
		GDSync.call_func_all(_set_worker, 0)
