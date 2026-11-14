class_name TraversalNode extends Area3D

enum S { ACTIVE, COOLDOWN, SABOTAGED }

@export var cooldown_time := 30.0
@export var use_range := 14.0 # host validation range (plus slack for lag)

var state:int = S.ACTIVE
var time_left := 0.0
var user_id := 0
var mat:StandardMaterial3D
var label:Label3D
var sparks:CPUParticles3D

func _ready() -> void:
	add_to_group("traversal_node")
	collision_layer = 0 # never blocks anything
	collision_mask = 0
	monitoring = false
	monitorable = false
	GDSync.expose_func(_host_use)
	GDSync.expose_func(_set_state)
	_build()
	_refresh()

func _build() -> void:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.14
	cyl.height = 0.9
	m.mesh = cyl
	mat = StandardMaterial3D.new()
	mat.emission_enabled = true
	m.material_override = mat
	add_child(m)
	
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.009
	label.font_size = 72
	label.outline_size = 12
	label.position = Vector3(0, 1.1, 0)
	add_child(label)
	
	sparks = CPUParticles3D.new()
	sparks.amount = 28
	sparks.lifetime = 0.6
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.initial_velocity_min = 1.0
	sparks.initial_velocity_max = 3.0
	sparks.gravity = Vector3(0, -6, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.015
	sm.height = 0.03
	var spm := StandardMaterial3D.new()
	spm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spm.albedo_color = Color(1.0, 0.85, 0.3)
	sm.material = spm
	sparks.mesh = sm
	sparks.emitting = false
	add_child(sparks)

# ---------- Requests ----------
func request_use() -> void:
	var id := GDSync.get_client_id()
	if GDSync.is_host():
		_host_use(id)
	else:
		GDSync.call_func_on(GDSync.get_host(), _host_use, id)

func _host_use(id:int) -> void:
	if !GDSync.is_host() or state != S.ACTIVE:
		return
	var p := get_tree().current_scene.find_child(str(id), true, false) as player
	if p == null or p.monster or p.downed or p.trapped or p.dead:
		return
	if p.global_position.distance_to(global_position) > use_range + 8.0:
		return
	GDSync.call_func_all(_set_state, S.COOLDOWN, cooldown_time, id)

# Called by a monster kit on the host
func host_sabotage(duration:float) -> bool:
	if !GDSync.is_host():
		return false
	if state == S.SABOTAGED:
		return false # already destroyed: can't be hit again, timer isn't reset
	GDSync.call_func_all(_set_state, S.SABOTAGED, duration, 0)
	return true

# ---------- State (every client) ----------
func _set_state(s:int, duration:float, uid:int) -> void:
	state = s
	time_left = duration
	user_id = uid
	_refresh()

func _process(delta:float) -> void:
	if state == S.ACTIVE:
		return
	time_left -= delta
	if time_left <= 0.0:
		_set_state(S.ACTIVE, 0.0, 0) # every client expires it on its own
	else:
		label.text = str(ceili(time_left))

func _refresh() -> void:
	match state:
		S.ACTIVE:
			mat.albedo_color = Color(0.2, 1.0, 0.3)
			mat.emission = Color(0.2, 1.0, 0.3)
			mat.emission_energy_multiplier = 2.5
			label.visible = false
			sparks.emitting = false
		S.COOLDOWN:
			mat.albedo_color = Color(0.1, 0.28, 0.14)
			mat.emission_energy_multiplier = 0.0
			label.visible = true
			label.modulate = Color(1, 1, 1)
			label.text = str(ceili(time_left))
			sparks.emitting = false
		S.SABOTAGED:
			mat.albedo_color = Color(0.22, 0.22, 0.22) # no green at all
			mat.emission_energy_multiplier = 0.0
			label.visible = true
			label.modulate = Color(1.0, 0.45, 0.35)
			label.text = str(ceili(time_left))
			sparks.emitting = true
