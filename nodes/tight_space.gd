@tool
class_name TightSpace extends Area3D

@export var size := Vector3(2, 2, 2):
	set(v):
		size = v.max(Vector3(0.1, 0.1, 0.1))
		_refresh()

var _shape:CollisionShape3D
var _viz:Node3D

func _ready() -> void:
	collision_layer = 0   # nothing can ever collide with the volume
	collision_mask = 1    # it only looks for bodies on the players' layer
	monitorable = false
	_shape = CollisionShape3D.new()
	_shape.shape = BoxShape3D.new()
	add_child(_shape)
	if Engine.is_editor_hint():
		_build_editor_viz() # created only inside the editor, never in a running game
	else:
		body_entered.connect(_on_enter)
		body_exited.connect(_on_exit)
	_refresh()

func _on_enter(b:Node3D) -> void:
	var p := b as player
	if p != null and p.monster:
		p.tight_space_enter()

func _on_exit(b:Node3D) -> void:
	var p := b as player
	if p != null and p.monster:
		p.tight_space_exit()

func _refresh() -> void:
	if _shape == null:
		return
	(_shape.shape as BoxShape3D).size = size
	if _viz != null:
		_viz.scale = size

# ---------- Editor only: transparent red block with a clear outline ----------
func _build_editor_viz() -> void:
	_viz = Node3D.new()
	add_child(_viz)
	
	var fill := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE # scaled to "size" by _viz
	fill.mesh = box
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1, 0.1, 0.1, 0.25)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill.material_override = fm
	_viz.add_child(fill)
	
	var h := 0.5
	var c := [Vector3(-h,-h,-h), Vector3(h,-h,-h), Vector3(h,-h,h), Vector3(-h,-h,h),
			Vector3(-h,h,-h), Vector3(h,h,-h), Vector3(h,h,h), Vector3(-h,h,h)]
	var edges := [0,1, 1,2, 2,3, 3,0, 4,5, 5,6, 6,7, 7,4, 0,4, 1,5, 2,6, 3,7]
	var pts := PackedVector3Array()
	for i in edges:
		pts.append(c[i])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	var wire := ArrayMesh.new()
	wire.add_surface_from_array(Mesh.PRIMITIVE_LINES, arr)
	var lines := MeshInstance3D.new()
	lines.mesh = wire
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1, 0.2, 0.2, 1)
	lines.material_override = lm
	_viz.add_child(lines)
