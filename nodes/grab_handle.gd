class_name GrabHandle
extends Node3D

enum HandleType { AIR, RUSH }

@export var handle_type:HandleType = HandleType.AIR

@export_group("General")
@export var interaction_range := 9.0   # how close you must be to grab it
@export var cooldown := 0.4            # seconds before you can grab again after letting go
@export var max_speed := 30.0          # speed limit while attached

@export_group("Air Grapple (swing)")
@export var swing_radius := 6.0        # distance kept from the handle
@export var swing_acceleration := 14.0 # extra push when you steer along the swing (pumping)
@export var air_control_strength := 12.0 # sideways steering strength
@export var reel_speed := 14.0         # how fast the rope shortens toward swing_radius
@export var min_radius := 1.5

@export_group("Rush Grapple (zipline)")
@export var end_point:Node3D           # a Marker3D marking the end of the path
@export var zipline_speed := 18.0
@export var zipline_accel := 40.0
@export var hang_offset := Vector3(0, -0.9, 0) # where your body hangs relative to the line

func _ready() -> void:
	add_to_group("grab_handle")
	_build_visual()
	if handle_type == HandleType.RUSH:
		if end_point == null:
			push_warning("GrabHandle %s is a Rush handle but has no End Point." % name)
		else:
			_build_line()

func path_end() -> Vector3:
	if end_point != null:
		return end_point.global_position
	return global_position

# A simple glowing ball, only if you haven't added your own mesh as a child
func _build_visual() -> void:
	for c in get_children():
		if c is MeshInstance3D:
			return
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	var col := Color(0.2, 0.9, 1.0) if handle_type == HandleType.AIR else Color(1.0, 0.55, 0.15)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	sphere.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	add_child(mi)

# A thin line showing the zipline path
func _build_line() -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(to_local(end_point.global_position))
	im.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.55, 0.15)
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat
	add_child(mi)
