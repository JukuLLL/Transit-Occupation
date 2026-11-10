class_name IndicatorSystem extends CanvasLayer

class Rule:
	var text := ""
	var offset := Vector3(0, 1.5, 0)
	var near := 6.0
	var far := 18.0
	var targets:Callable            # (viewer) -> Array of Node3D currently shown to this viewer
	var active := {}                # target instance id -> WorldIndicator

var viewer:player
var rules:Array[Rule] = []

func _ready() -> void:
	layer = 3
	_register_defaults()

# Adding a new indicator later = one call to this, plus a targets function
func add_rule(text:String, targets:Callable, offset := Vector3(0, 1.5, 0), near := 6.0, far := 18.0) -> Rule:
	var r := Rule.new()
	r.text = text
	r.targets = targets
	r.offset = offset
	r.near = near
	r.far = far
	rules.append(r)
	return r

func _register_defaults() -> void:
	add_rule("Genetic Material", _targets_material, Vector3(0, 1.2, 0))
	add_rule("Deposit Genetic Material to Algorithm Chamber", _targets_chamber, Vector3(0, 7.0, 0), 10.0, 25.0)
	add_rule("Grant Research Station access", _targets_station, Vector3(0, 6.0, 0), 10.0, 25.0)
	add_rule("Escape!", _targets_escape, Vector3(0, 2.5, 0), 8.0, 22.0)

# ---------- Rules: who sees what, and when ----------
# Survivors and the monster, only while the cube lies in the world
func _targets_material(_v:player) -> Array:
	var out := []
	for n in get_tree().get_nodes_in_group("genetic_material"):
		if is_instance_valid(n) and n.carrier_id == 0 and !n.consumed:
			out.append(n)
	return out

# Only a survivor who is carrying a cube, on every chamber
func _targets_chamber(v:player) -> Array:
	if v.monster or !is_instance_valid(v.carried_item):
		return []
	return get_tree().get_nodes_in_group("algorithm_chamber")

# Survivors only, from the start of the pipe objective until it is pulled down
func _targets_station(v:player) -> Array:
	if v.monster:
		return []
	var out := []
	for s in get_tree().get_nodes_in_group("research_station"):
		if s.active and !s.done:
			out.append(s)
	return out

# Survivors only, while an escape zone is active
func _targets_escape(v:player) -> Array:
	if v.monster:
		return []
	var out := []
	for z in get_tree().get_nodes_in_group("escape_zone"):
		if z.monitoring:
			out.append(z)
	return out

# ---------- Rendering ----------
func _process(_delta:float) -> void:
	if !is_instance_valid(viewer):
		return
	visible = !viewer.dead
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for rule in rules:
		var seen := {}
		for t in rule.targets.call(viewer):
			if !is_instance_valid(t):
				continue
			var id:int = t.get_instance_id()
			seen[id] = true
			var ind:WorldIndicator = rule.active.get(id)
			if ind == null:
				ind = WorldIndicator.new()
				add_child(ind)
				ind.setup(rule.text)
				rule.active[id] = ind
			ind.place(cam, t.global_position + rule.offset, rule.near, rule.far)
		for id in rule.active.keys():
			if !seen.has(id):
				if is_instance_valid(rule.active[id]):
					rule.active[id].queue_free()
				rule.active.erase(id)
