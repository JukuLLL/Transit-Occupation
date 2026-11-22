@tool
class_name GrabHandle
extends Node3D

enum HandleType { AIR, RUSH }

@export var handle_type:HandleType = HandleType.AIR

@export_group("General")
@export var interaction_range := 9.0   # how close you must be to grab it
@export var cooldown := 20.0           # seconds the handle is unusable after you let go
@export var max_speed := 30.0          # speed limit while attached

@export_group("Air Grapple (swing)")
@export var swing_radius := 6.0
@export var swing_acceleration := 14.0
@export var swing_speed := 16.0
@export var release_angle := 50.0
@export var reel_speed := 14.0
@export var min_radius := 1.5
@export var pull_speed := 22.0
@export var pull_accel := 60.0

@export_group("Rush Grapple (zipline)")
@export var end_point:Node3D           # a Marker3D marking the end of the path
@export var zipline_speed := 18.0
@export var zipline_accel := 40.0
@export var hang_offset := Vector3(0, -0.9, 0)

const COLOR_AIR := Color(0.2, 0.9, 1.0)
const COLOR_RUSH := Color(1.0, 0.55, 0.15)
const COLOR_COOLDOWN := Color(0.45, 0.45, 0.45)

var cooldown_left := 0.0
var _mat:StandardMaterial3D
var _line_mi:MeshInstance3D
var _line_mesh:ImmediateMesh
var _line_mat:StandardMaterial3D

func _ready() -> void:
	add_to_group("grab_handle")
	_build_visual()
	_build_line()
	if !Engine.is_editor_hint() and handle_type == HandleType.RUSH and end_point == null:
		push_warning("GrabHandle %s is a Rush handle but has no End Point." % name)

func _process(delta:float) -> void:
	if !Engine.is_editor_hint():
		cooldown_left = maxf(cooldown_left - delta, 0.0)
	_update_look()
	if Engine.is_editor_hint():
		_update_line() # follows the End Point marker while you move it

func is_ready() -> bool:
	return cooldown_left <= 0.0

func start_cooldown() -> void:
	cooldown_left = cooldown

func path_end() -> Vector3:
	if end_point != null:
		return end_point.global_position
	return global_position

# A simple glowing ball, only if you haven't added your own mesh as a child
func _build_visual() -> void:
	var mi := get_node_or_null("HandleBall") as MeshInstance3D
	if mi != null:
		_mat = (mi.mesh as SphereMesh).material as StandardMaterial3D
		return
	for c in get_children():
		if c is MeshInstance3D:
			return
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	_mat = StandardMaterial3D.new()
	_mat.emission_enabled = true
	sphere.material = _mat
	mi = MeshInstance3D.new()
	mi.name = "HandleBall"
	mi.mesh = sphere
	add_child(mi)

# A thin line showing the zipline path (hidden for Air handles)
func _build_line() -> void:
	_line_mi = get_node_or_null("HandleLine") as MeshInstance3D
	if _line_mi != null:
		_line_mesh = _line_mi.mesh as ImmediateMesh
		_line_mat = _line_mi.material_override as StandardMaterial3D
	else:
		_line_mesh = ImmediateMesh.new()
		_line_mat = StandardMaterial3D.new()
		_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_line_mi = MeshInstance3D.new()
		_line_mi.name = "HandleLine"
		_line_mi.mesh = _line_mesh
		_line_mi.material_override = _line_mat
		add_child(_line_mi)
	_update_line()

func _update_line() -> void:
	if _line_mesh == null:
		return
	_line_mesh.clear_surfaces()
	if handle_type != HandleType.RUSH or end_point == null:
		_line_mi.visible = false
		return
	_line_mi.visible = true
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_line_mesh.surface_add_vertex(Vector3.ZERO)
	_line_mesh.surface_add_vertex(to_local(end_point.global_position))
	_line_mesh.surface_end()

# Colored when usable, gray on cooldown
func _update_look() -> void:
	var ready_now := is_ready()
	var base := COLOR_AIR if handle_type == HandleType.AIR else COLOR_RUSH
	var col := base if ready_now else COLOR_COOLDOWN
	if _mat != null:
		_mat.albedo_color = col
		_mat.emission = col
		_mat.emission_energy_multiplier = 2.0 if ready_now else 0.0
	if _line_mat != null:
		_line_mat.albedo_color = col
