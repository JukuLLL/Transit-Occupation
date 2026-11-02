class_name BruteKit extends MonsterKit

@export_category("Basic attack")
@export var attack_damage := 25
@export var attack_interval := 1.0
@export var attack_range := 2.6
@export var attack_cone := 0.35      # how closely you must aim at the survivor (1 = dead center)
@export var miss_time := 0.5
@export var miss_speed := 0.5        # speed multiplier while penalized

@export_category("Dash")
@export var dash_cooldown := 30.0
@export var dash_duration := 2.0
@export var dash_speed := 28.0
@export var dash_hit_radius := 1.3

@export_category("All-Seeing")
@export var scan_cooldown := 20.0
@export var drone_range := 14.0
@export var drone_height := 2.5
@export var drone_lifetime := 8.0
@export var scan_radius := 7.0
@export var reveal_time := 4.0

@export_category("Loud footsteps")
@export var stride := 2.4
@export var footstep_db := 12.0
@export var footstep_sounds:Array[AudioStream] # leave empty to use the placeholder thud

# ---- local state (the Brute's own machine) ----
var swing_cd := 0.0
var dash_cd := 0.0
var scan_cd := 0.0
var miss_left := 0.0
var dashing := false
var dash_left := 0.0
var dash_dir := Vector3.FORWARD
var prev_pos := Vector3.ZERO
var stride_acc := 0.0
var reveals:Dictionary = {}       # survivor id -> marker mesh
var reveal_until:Dictionary = {}  # survivor id -> end time (msec)
var dash_ring:CooldownRing
var scan_ring:CooldownRing

# ---- host state ----
var h_attack_at := 0
var h_dash_at := 0
var h_dash_until := 0
var h_dash_active := false
var h_scan_at := 0

var _step_player:AudioStreamPlayer3D
var _thud:AudioStreamWAV

func _expose() -> void:
	for c in [_host_attack, _attack_result, _host_dash, _dash_ack, _dash_denied,
			_host_dash_hit, _host_scan, _scan_ack, _drone_spawn, _reveal, _play_step]:
		GDSync.expose_func(c)

func speed_multiplier() -> float:
	return miss_speed if miss_left > 0.0 else 1.0

# =====================================================================
# Local tick
# =====================================================================
func tick(delta:float) -> void:
	swing_cd = maxf(swing_cd - delta, 0.0)
	dash_cd = maxf(dash_cd - delta, 0.0)
	scan_cd = maxf(scan_cd - delta, 0.0)
	miss_left = maxf(miss_left - delta, 0.0)
	_expire_reveals()
	_update_crosshair()
	_update_hud()
	_footsteps(delta)
	if dashing:
		return
	if Input.is_action_just_pressed("left_click"):
		_try_attack()
	if Input.is_action_just_pressed("brute_dash"):
		_try_dash()
	if Input.is_action_just_pressed("brute_scan"):
		_try_scan()

func _setup_local() -> void:
	if is_instance_valid(plr.plr_head) and plr.plr_head.dash_ring:
		plr.plr_head.dash_ring.hide() # the survivor dash ring isn't used by monsters
	var layer := CanvasLayer.new()
	layer.layer = 5
	plr.add_child(layer)
	var screen := plr.get_viewport().get_visible_rect().size
	dash_ring = _make_ring(layer, Vector2(screen.x / 2 - 110, screen.y - 140), "SHIFT")
	scan_ring = _make_ring(layer, Vector2(screen.x / 2 + 20, screen.y - 140), "E")

func _make_ring(layer:CanvasLayer, pos:Vector2, key:String) -> CooldownRing:
	var ring := CooldownRing.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ring)
	ring.size = Vector2(90, 90)
	ring.position = pos
	var l := Label.new()
	l.text = key
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return ring

func _update_hud() -> void:
	if dash_ring:
		dash_ring.progress = 1.0 - dash_cd / dash_cooldown
	if scan_ring:
		scan_ring.progress = 1.0 - scan_cd / scan_cooldown

func _update_crosshair() -> void:
	var can := !dashing and swing_cd <= 0.0 and _find_attack_target() != null
	plr.crosshair.modulate = Color(1.0, 0.15, 0.15) if can else Color.WHITE

# =====================================================================
# Basic attack
# =====================================================================
func _aiming_at_interactable() -> bool:
	var ray:RayCast3D = plr.plr_head.interact_ray
	if !ray.is_colliding():
		return false
	var c = ray.get_collider()
	return is_instance_valid(c) and c.has_method("interact") # e.g. picking up a downed survivor

func _find_attack_target() -> player:
	var cam := plr.first_person_camera
	var from := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var best:player = null
	var best_dot := attack_cone
	for p in survivors():
		if !can_target(p):
			continue
		if plr.global_position.distance_to(p.global_position) > attack_range:
			continue
		var to := p.global_position + Vector3.UP * 0.5
		var d := fwd.dot((to - from).normalized())
		if d < best_dot:
			continue
		if !_line_clear(from, to): # no hits through walls
			continue
		best = p
		best_dot = d
	return best

func _try_attack() -> void:
	if swing_cd > 0.0 or _aiming_at_interactable():
		return
	swing_cd = attack_interval
	var t := _find_attack_target()
	if t == null:
		miss_left = miss_time # a swing at nothing is a miss
	_call_host(_host_attack, [client_id, t.name.to_int() if t else 0])

func _host_attack(sender:int, target_id:int) -> void:
	if !GDSync.is_host() or sender != client_id:
		return
	var now := Time.get_ticks_msec()
	if now < h_attack_at - 150: # small latency tolerance
		_call_on(client_id, _attack_result, [false])
		return
	h_attack_at = now + int(attack_interval * 1000.0)
	var hit := false
	var t := plr.get_parent().get_node_or_null(str(target_id)) as player
	if t != null and can_target(t):
		var close := plr.global_position.distance_to(t.global_position) <= attack_range + 2.5
		if close and _line_clear(plr.global_position + Vector3.UP * 1.0, t.global_position + Vector3.UP * 0.5):
			hit = true
			_call_on(target_id, t.hit_by_damager, [attack_damage, "Brute"])
	_call_on(client_id, _attack_result, [hit])

func _attack_result(hit:bool) -> void:
	if is_local and !hit and miss_left <= 0.0:
		miss_left = miss_time

# =====================================================================
# Dash
# =====================================================================
func _try_dash() -> void:
	if dash_cd > 0.0:
		return
	dash_cd = dash_cooldown # predicted, the host confirms or corrects it
	_begin_dash()
	_call_host(_host_dash, [client_id])

func _begin_dash() -> void:
	dashing = true
	dash_left = dash_duration
	var f := -plr.global_transform.basis.z
	f.y = 0.0
	dash_dir = f.normalized()
	prev_pos = plr.global_position
	plr.bhop = false

func _end_dash() -> void:
	if !dashing:
		return
	dashing = false
	plr.velocity.x = 0.0
	plr.velocity.z = 0.0

func _host_dash(sender:int) -> void:
	if !GDSync.is_host() or sender != client_id:
		return
	var now := Time.get_ticks_msec()
	if now < h_dash_at - 300:
		_call_on(client_id, _dash_denied, [maxf(0.0, (h_dash_at - now) / 1000.0)])
		return
	h_dash_at = now + int(dash_cooldown * 1000.0)
	h_dash_until = now + int(dash_duration * 1000.0) + 500
	h_dash_active = true
	_call_on(client_id, _dash_ack, [dash_cooldown])

func _dash_ack(cd:float) -> void:
	if is_local:
		dash_cd = cd

func _dash_denied(remaining:float) -> void:
	if is_local:
		dash_cd = remaining
		_end_dash()

func before_slide(delta:float) -> void:
	if !dashing:
		return
	dash_left -= delta
	prev_pos = plr.global_position
	plr.velocity.x = dash_dir.x * dash_speed
	plr.velocity.z = dash_dir.z * dash_speed

func after_slide(_delta:float) -> void:
	if !dashing:
		return
	# Swept check from last frame to this one, so high speed can't skip a survivor
	var cur := plr.global_position
	for p in survivors():
		if !can_target(p, true):
			continue
		if _dist_to_segment(p.global_position, prev_pos, cur) <= dash_hit_radius:
			_dash_hit(p)
			return
	# A solid wall or another survivor body in front ends the dash
	for i in plr.get_slide_collision_count():
		var c := plr.get_slide_collision(i)
		var other := c.get_collider() as player
		if other != null and !other.monster and can_target(other, true):
			_dash_hit(other)
			return
		var n := c.get_normal()
		if absf(n.y) < 0.5 and n.dot(dash_dir) < -0.5:
			_end_dash()
			return
	if dash_left <= 0.0:
		_end_dash()

func _dash_hit(p:player) -> void:
	_end_dash() # only the first survivor is hit
	_call_host(_host_dash_hit, [client_id, p.name.to_int()])

func _host_dash_hit(sender:int, target_id:int) -> void:
	if !GDSync.is_host() or sender != client_id:
		return
	if !h_dash_active or Time.get_ticks_msec() > h_dash_until:
		return
	var t := plr.get_parent().get_node_or_null(str(target_id)) as player
	if t == null or !can_target(t, true):
		return
	if plr.global_position.distance_to(t.global_position) > dash_hit_radius + 6.0:
		return
	h_dash_active = false
	_call_all(t.death) # instant elimination

func _dist_to_segment(p:Vector3, a:Vector3, b:Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

# =====================================================================
# All-Seeing (drone)
# =====================================================================
func _try_scan() -> void:
	if scan_cd > 0.0:
		return
	var cam := plr.first_person_camera
	var from := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * drone_range)
	q.exclude = [plr.get_rid()]
	var hit := plr.get_world_3d().direct_space_state.intersect_ray(q)
	var target:Vector3 = (hit.position - fwd * 0.6) if !hit.is_empty() else from + fwd * drone_range
	target += Vector3.UP * drone_height
	scan_cd = scan_cooldown
	_call_host(_host_scan, [client_id, from, target])

func _host_scan(sender:int, from:Vector3, target:Vector3) -> void:
	if !GDSync.is_host() or sender != client_id:
		return
	var now := Time.get_ticks_msec()
	if now < h_scan_at - 300:
		return
	h_scan_at = now + int(scan_cooldown * 1000.0)
	# Keep the drone within range of where the Brute really is
	var off := target - plr.global_position
	var max_d := drone_range + drone_height + 6.0
	if off.length() > max_d:
		target = plr.global_position + off.normalized() * max_d
	_call_all(_drone_spawn, [from, target, drone_lifetime])
	_call_on(client_id, _scan_ack, [scan_cooldown])
	_host_scan_loop(target, drone_lifetime)

func _scan_ack(cd:float) -> void:
	if is_local:
		scan_cd = cd

# Host: detection is decided here, and only the Brute is told who was found
func _host_scan_loop(center:Vector3, life:float) -> void:
	var t := 0.0
	while t < life and is_inside_tree() and !Network.round_over:
		for p in survivors():
			if p.dead or p.escaped:
				continue
			if p.global_position.distance_to(center) <= scan_radius:
				_call_on(client_id, _reveal, [p.name.to_int(), reveal_time])
		await get_tree().create_timer(0.25).timeout
		t += 0.25

# Everyone sees the placeholder drone
func _drone_spawn(from:Vector3, target:Vector3, life:float) -> void:
	var d := Node3D.new()
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.3
	s.height = 0.6
	m.mesh = s
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 1.0)
	m.material_override = mat
	d.add_child(m)
	get_tree().current_scene.add_child(d)
	d.global_position = from
	var tw := d.create_tween()
	tw.tween_property(d, "global_position", target, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(life).timeout
	if is_instance_valid(d):
		d.queue_free()

# Only the Brute's machine creates the see-through marker, so survivors never see it
func _reveal(survivor_id:int, time:float) -> void:
	if !is_local:
		return
	var t := plr.get_parent().get_node_or_null(str(survivor_id)) as player
	if t == null:
		return
	if !reveals.has(survivor_id) or !is_instance_valid(reveals[survivor_id]):
		var m := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.45
		cap.height = 1.9
		m.mesh = cap
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.15, 0.15, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		mat.render_priority = 10
		m.material_override = mat
		t.add_child(m)
		reveals[survivor_id] = m
	reveal_until[survivor_id] = Time.get_ticks_msec() + int(time * 1000.0)

func _expire_reveals() -> void:
	if reveals.is_empty():
		return
	var now := Time.get_ticks_msec()
	for id in reveals.keys():
		var m = reveals[id]
		if !is_instance_valid(m) or now > int(reveal_until.get(id, 0)):
			if is_instance_valid(m):
				m.queue_free()
			reveals.erase(id)
			reveal_until.erase(id)

# =====================================================================
# Loud footsteps (silenced while bunny hopping)
# =====================================================================
func _footsteps(delta:float) -> void:
	var speed := Vector2(plr.velocity.x, plr.velocity.z).length()
	if plr.is_on_floor() and speed > 2.0 and !plr.bhop and !dashing:
		stride_acc += speed * delta
		if stride_acc >= stride:
			stride_acc = 0.0
			_call_all(_play_step)
	else:
		stride_acc = 0.0

func _play_step() -> void:
	if _step_player == null:
		_step_player = AudioStreamPlayer3D.new()
		_step_player.unit_size = 18.0
		_step_player.max_distance = 70.0
		_step_player.max_db = footstep_db
		_step_player.volume_db = footstep_db
		plr.add_child(_step_player)
	if !footstep_sounds.is_empty():
		_step_player.stream = footstep_sounds.pick_random()
	else:
		if _thud == null:
			_thud = _make_thud()
		_step_player.stream = _thud
	_step_player.pitch_scale = randf_range(0.85, 1.0)
	_step_player.play()

# Placeholder: a short low thud, so no audio file is needed
func _make_thud() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.28)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var s := sin(TAU * (70.0 + 50.0 * exp(-t * 20.0)) * t) * exp(-t * 14.0)
		s += (randf() * 2.0 - 1.0) * 0.25 * exp(-t * 40.0)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
