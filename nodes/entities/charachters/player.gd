class_name player extends CharacterBody3D

#region Variables
var latest_damage_source:String="NULL"

var downed:bool = false
var picked_up:bool = false
var downed_interact:interactable

@export var ping_lifetime:float = 7.0
@export var ping_max_distance:float = 300.0
var current_ping:PingMarker
var teammate_hud:Node
@export var health :int=100
@export var lives :int=3
@export var speed := 5.0
@export var sprint_speed := 10.0
@export var jump_multiplier:float=1
@export var max_bhop_inaccuracy:int=20
@export var mouse_sensitivity := 0.002
@export var grapple_ray:RayCast3D
@export var grapple_force:float=1
@export var in_grapple = false
@export var grapple_sensitivity := 300
@export var grapple_distance:float=1.0

@export var monster:bool=false
@export var monster_hold_spot:Marker3D

@export var filter:PackedScene
@onready var plr_head = $Head
@onready var crosshair = $Head.crosshair
@onready var first_person_camera:Camera3D = $Head.first_person_camera
@onready var third_person_camera_spot = $Head.third_person_camera
@onready var player_mesh = $MeshInstance3D

# DASH
@export var dash_speed = 10
@export var dash_cooldown = 60

var first_person := true




# JUMP
@export var gravity :Vector3= Vector3(0,0.4,0)
var bhop = false
var floor_counter = 0
var jump_velocity := 7.0
var new_speed = 5.0
var new_velocity = Vector3.ZERO
var friction = 5

var cross_hair_regular_pos:Vector2
var grapple_area:Rect2
var gravity_state = 1

var last_movement:float=0

#endregion


#region Bhop_combo

# B-HOP COMBO
var bhop_combo := 0
var best_bhop_combo := 0
var combo_label: Label
var combo_tween: Tween

func _create_combo_ui():
	if combo_label != null: return # owner_changed can fire more than once
	var layer := CanvasLayer.new()
	add_child(layer)
	
	combo_label = Label.new()
	combo_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	combo_label.offset_left = -420
	combo_label.offset_right = -24
	combo_label.offset_top = 24
	combo_label.offset_bottom = 80
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	combo_label.add_theme_font_size_override("font_size", 32)
	combo_label.add_theme_color_override("font_outline_color", Color.BLACK)
	combo_label.add_theme_constant_override("outline_size", 6)
	combo_label.visible = false
	layer.add_child(combo_label)

func set_bhop_combo(value: int):
	bhop_combo = value
	best_bhop_combo = max(best_bhop_combo, bhop_combo)
	if combo_label == null: return
	
	if bhop_combo <= 0:
		combo_label.visible = false
		return
	
	combo_label.visible = true
	combo_label.text = "Successful B-Hop: x%d" % bhop_combo
	
	# Little "pop" every time the combo goes up
	combo_label.pivot_offset = Vector2(combo_label.size.x, combo_label.size.y * 0.5)
	if combo_tween: combo_tween.kill()
	combo_label.scale = Vector2(1.3, 1.3)
	combo_tween = create_tween()
	combo_tween.tween_property(combo_label, "scale", Vector2.ONE, 0.15)
#endregion


#region Initalization
func owner_changed(id:int):
	print("owner_changed")
	var is_owner:bool=GDSync.is_gdsync_owner(self)
	if !is_owner:
		plr_head.queue_free()
	if is_owner:
		_create_combo_ui()
		$OmniLight3D.visible = true
		first_person_camera.make_current()
		$OmniLight3D.visible = true
		first_person_camera.make_current()
		var screen:Rect2=get_viewport().get_visible_rect()
		crosshair.position = screen.size / 2
		cross_hair_regular_pos = crosshair.position
		grapple_area = screen
		grapple_area.position = grapple_area.end * 1.5
		first_person_camera.current = true
		player_mesh.visible = false
		first_person_camera.make_current()
		await get_tree().physics_frame
		if GDSync.player_get_data(GDSync.get_gdsync_owner(self),"TEAM") == "MONSTER":
			monster = true
			add_child(filter.instantiate())
			first_person_camera.compositor = load("res://shaders/comp/monster_vis.res")
			grapple_ray.set_collision_mask_value(32,false)
			plr_head.enable_monster()
		else:
			monster = false
			_create_teammate_hud()
			first_person_camera.compositor = load("res://shaders/comp/plr.res")
		print(GDSync.player_get_data(GDSync.get_gdsync_owner(self),"TEAM"))
	pass
	
func _create_teammate_hud():
	if teammate_hud != null: return # owner_changed can fire more than once
	teammate_hud = load("res://nodes/teammate_hud.gd").new()
	teammate_hud.me = self
	add_child(teammate_hud)
	
func _init() -> void:
	dash_cooldown = 0
	_init_dev()

func _ready():
	GDSync.connect_gdsync_owner_changed(self,owner_changed)
	GDSync.expose_node(self)
	
	grapple_ray = plr_head.grapple_ray
	if monster:
		grapple_ray.target_position.z = (25 * grapple_distance) * -1
	await get_tree().physics_frame
	GDSync.set_gdsync_owner($MeshInstance3D,name.to_int())
	await get_tree().physics_frame
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	new_speed = speed
#endregion

func visibility_to_blind():
	$MeshInstance3D.set_layer_mask_value(1,true)
	return
	if velocity.length() > 0:
		last_movement = 1500
		$MeshInstance3D.set_layer_mask_value(1,true)
	elif last_movement < 1:
		$MeshInstance3D.set_layer_mask_value(1,false)
	else:
		last_movement -= 1
		
#region movement_and_camera
func _unhandled_input(event):
	if !GDSync.is_gdsync_owner(self): return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Turn the player left/right
		rotation.y += (-event.relative.x * mouse_sensitivity) * gravity_state
		
		# Look up/down
		plr_head.rotation.x += (-event.relative.y * mouse_sensitivity)
		
		# Prevent the camera from flipping upside down
		plr_head.rotation.x = clamp(
			plr_head.rotation.x,
			deg_to_rad(-80),
			deg_to_rad(80)
		)
	
	if event.is_action_pressed("toggle_camera"):
		toggle_camera()
		
	if event.is_action_pressed("ping"):
		do_ping()
		
			
func do_ping():
	var cam:Camera3D = first_person_camera
	var from:Vector3 = cam.global_position
	var to:Vector3 = from - cam.global_transform.basis.z * ping_max_distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit:Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var ping_name:String = str(Network.plr_name)
	if ping_name == "":
		ping_name = "Player"
	GDSync.call_func_all(show_ping, hit.position, ping_name)

func show_ping(world_pos:Vector3, sender_name:String):
	# One ping per player: a new ping replaces the old one
	if is_instance_valid(current_ping):
		current_ping.queue_free()
	var marker := PingMarker.new()
	marker.world_pos = world_pos
	marker.display_name = sender_name
	marker.lifetime = ping_lifetime
	add_child(marker)
	current_ping = marker

func toggle_camera():
	first_person = not first_person
	var third_transform:Vector3=plr_head.to_local(third_person_camera_spot.global_position)
	
	if first_person:
		create_tween().tween_property(first_person_camera,"position",third_transform,0.2)
		# Don't see our own body in first person
		player_mesh.visible = true
	
	else:
		create_tween().tween_property(first_person_camera,"position",Vector3.ZERO,0.2)
		# Show body in third person
		player_mesh.visible = false
		
func movement(delta):
	var input := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	
	var direction := Vector3(input.x, 0, input.y)
	direction = transform.basis * direction
	direction.y = 0
	if direction.length() > 0:
		direction = direction.normalized()
	
	floor_counter = clampi(floor_counter,0,max_bhop_inaccuracy + 1)
		
	if Input.is_action_pressed("sprint"):
		if !bhop:
			new_speed = lerpf(new_speed,sprint_speed,delta * 5)
	else:
		if !bhop:
			new_speed = lerpf(new_speed,speed,delta * 5)
			
	if dash_cooldown != null:
		dash_cooldown -= 1
		dash_cooldown = clampi(dash_cooldown,0,INT32_MAX)
		if plr_head:
			plr_head.update_dash(dash_cooldown)
	
	if Input.is_action_just_pressed("dash"):
		dash()
		
	if is_on_floor():
		
		floor_counter += 1
		if Input.is_action_just_pressed("jump"):
			var was_chained: bool = bhop
			velocity.y += (jump_velocity * gravity_state) * jump_multiplier
			if velocity.length() > 0.2:
				bhop = true
				floor_counter = 0
				if was_chained:
					set_bhop_combo(bhop_combo +1)
		else:
			velocity.y = 0
		if floor_counter > max_bhop_inaccuracy - 1:
			bhop = false
			if bhop_combo != 0:
				set_bhop_combo(0)
		if input:
			velocity.x = move_toward(velocity.x,direction.x * new_speed,delta * 40)
			velocity.z = move_toward(velocity.z,direction.z * new_speed,delta * 40)
		else:
			if !bhop:
				velocity.x -= velocity.x / (friction / 2)
				velocity.z -= velocity.z / (friction / 2)
		
	else:
		velocity.y -= gravity.y * gravity_state
		new_velocity = velocity
		if input:
			if !bhop:
				velocity.x = move_toward(velocity.x,direction.x * new_speed,delta * 35)
				velocity.z = move_toward(velocity.z,direction.z * new_speed, delta * 35)
			else:
				var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
				var current_horizontal_speed = horizontal_velocity.length()
				var new_horizontal_velocity = direction * current_horizontal_speed
				velocity.x = move_toward(velocity.x,new_horizontal_velocity.x,delta * 35)
				velocity.z = move_toward(velocity.z,new_horizontal_velocity.z, delta * 35)
		else:
			if !bhop:
				velocity.x -= velocity.x / 10
				velocity.z -= velocity.z / 10
				
func dash():
	if dash_cooldown > 1:
		return
	bhop = true
	floor_counter = 0
	dash_cooldown = 60
	var push:Vector3=transform.basis * Vector3.FORWARD
	velocity += push * dash_speed
	
	pass
#endregion

func _physics_process(delta):

	downed_check()

#region others
	if !GDSync.is_gdsync_owner(self):
		pass
#endregion
		
#region client
	else:
		visibility_to_blind()
			
		$Label.text = str(velocity.length())
		$Label2.text = str(grappling_target)
		
		movement(delta)
		
		if grapple_pos != null:
			grapple_ray.look_at(grapple_pos)
		if grapple_ray.is_colliding():
			grappling_target = grapple_ray.get_collider()
		
		grappling_hook(delta)
		if monster:
			ability_check()
			if Input.is_action_just_pressed("left_click"):
				attack()
			
		interact_check()
		
		move_and_slide()
#endregion
	
	
#region Downed
func interact(plr_path:NodePath):
	var plr:player=get_node(plr_path)
	if downed:
		if plr.monster:
			GDSync.call_func_on(GDSync.get_gdsync_owner(self),pickup,plr_path)
		else:
			if !picked_up:
				GDSync.call_func_on(self.name.to_int(),revive)
	pass
	
func revive():
	if GDSync.is_gdsync_owner(self):
		health = 100
		plr_head.update_health(health)
		downed = false
	pass
	
func pickup(monster_path:NodePath):
	var monster:player= get_node(monster_path)
	print("picked " + str(picked_up))
	if !picked_up:
		GDSync.call_func_all(sync_pick_up,true)
		monster_hold_spot = monster.monster_hold_spot
	else:
		GDSync.call_func_all(sync_pick_up,false)
	pass
	
func sync_pick_up(on:bool):
	print("picked_up")
	picked_up = on
	GDSync.sync_var(self,"picked_up")
	for plr:player in get_tree().get_nodes_in_group("plr"):
		if plr != self:
			if on:
				self.add_collision_exception_with(plr)
			else:
				self.remove_collision_exception_with(plr)


	
#endregion

#region hit_reactions

func _hit_by_phyics():
	if monster: return
	velocity /= 10
	if plr_head:
		plr_head.damage_indicator()
		plr_head.shake(1)
	
func hit_by_damager(damage:int=1,damage_cause:String="NULL",force:Vector3=Vector3.ZERO,debug:Variant=null):
	if downed: return
	if monster: return
	print("hit")
	latest_damage_source = damage_cause
	if debug:
		print(str(debug))
	velocity /= 2
	if force:
		velocity += force
	health -= damage
	GDSync.sync_var(self,"health",true)
	if plr_head:
		plr_head.damage_indicator()
		plr_head.shake(0.01 * (damage / 5))
		plr_head.update_health(health)
	
	if health < 1:
		if lives < 1:
			GDSync.call_func_all(death)
		else:
			GDSync.call_func_all(down_player)
		
func down_player():
	if monster: return
	downed = true
	lives -= 1
	velocity = Vector3.ZERO
	if downed_interact == null:
		downed_interact = interactable.new()
	add_child(downed_interact)
	downed_interact.synced = false
	var shp := SphereShape3D.new()
	shp.radius = 1
	var col := CollisionShape3D.new()
	col.shape = shp
	downed_interact.add_child(col)
	downed_interact.interacting.connect(interact)
	pass
	
func downed_check():
	if downed:
		if GDSync.is_gdsync_owner(self):
			var ray :RayCast3D= plr_head.interact_ray
			ray.enabled = false
			var down:Vector3=Vector3(0,velocity.y,0)
			velocity = down
		if picked_up:
			velocity = Vector3.ZERO
			if monster_hold_spot != null and picked_up:
				print(picked_up)
				global_position = monster_hold_spot.global_position
				#GDSync.sync_var_on(Network.monster_id,self,"global_position")
	else:
		if downed_interact != null:
			downed_interact.queue_free()

		
func death():
	if GDSync.is_gdsync_owner(self):
		var scene:PackedScene=load("res://nodes/entities/charachters/spectator.scn")
		var cam:FreeLookCamera=scene.instantiate()
		get_tree().current_scene.add_child(cam)
		cam.global_position = global_position
		cam.make_current()
		pass
	self.hide()
	process_mode = Node.PROCESS_MODE_DISABLED
	set_process_input(false)
	set_physics_process(false)
	set_process(false)
	pass
#endregion
	
#region grapple
var grappling_target:Node3D=self

var grapple_pos:Vector3=Vector3.ZERO

func is_in_range(pos:Vector2) -> bool:
	$Label3.text = str(cross_hair_regular_pos.distance_to(pos))
	if cross_hair_regular_pos.distance_to(pos) < grapple_sensitivity:
		return true
	else:
		return false
	
var grapple_spots:Array[grabble_point]
	
func set_grapple_target(pos:Vector3):
	grapple_pos = pos
	if first_person_camera.is_position_in_frustum(grapple_pos):
		in_grapple = true
	if grappling_target != null and !first_person_camera.is_position_behind(grapple_pos):
		if grappling_target.is_in_group("grapple") and is_in_range(first_person_camera.unproject_position(grapple_pos)):
			crosshair.position = first_person_camera.unproject_position(grapple_pos)
			crosshair.play("interact")
		
func grappling_hook(delta:float):
	if is_inside_tree():
		if grapple_spots.is_empty():
			grapple_spots.append_array(get_tree().get_nodes_in_group("grapple"))
		var closest:grabble_point = grapple_spots.get(0)
		for spot:grabble_point in grapple_spots:
			if global_position.distance_squared_to(spot.global_position) < global_position.distance_squared_to(closest.global_position):
				closest = spot
		set_grapple_target(closest.global_position)
		var mouse= Input.is_action_pressed("right_click")
		if mouse and grapple_ray.is_colliding() and grappling_target.is_in_group("grapple") and is_in_range(first_person_camera.unproject_position(grapple_pos)) and first_person_camera.is_position_in_frustum(grapple_pos):
			if !closest.allow_pull:
				pass
			else:
				var direction:Vector3=global_position.direction_to(grapple_ray.get_collision_point())
				velocity += direction * (grapple_force * (global_position.distance_to(grapple_ray.get_collision_point()) / 7)) - Vector3(0,0.1,0)
			if !monster:
					GDSync.emit_signal_remote_all(closest.grabbled)
		elif !grappling_target.is_in_group("grapple") or !is_in_range(first_person_camera.unproject_position(grapple_pos)):
			#grapple_ray.rotation = Vector3.ZERO
			in_grapple = false
			crosshair.position = cross_hair_regular_pos
			crosshair.play("default")
			pass
#endregion

#region interacting
		
var last_interactable:interactable
		
func interact_check():
	var ray:RayCast3D=plr_head.interact_ray
	var collider:Node3D=ray.get_collider()
	var interactable_object:interactable
	if ray.is_colliding():
		collider=ray.get_collider()
		if collider.has_method("interact"):
			interactable_object=collider
			last_interactable = interactable_object
			plr_head.allow_interact(last_interactable.KEY,true)
	if Input.is_action_pressed("left_click"):
		if collider != null:
			if collider.has_method("interact"):
				interactable_object.interact(self)
	elif Input.is_action_just_released("left_click") or !ray.is_colliding() or collider != last_interactable:
		var key:String
		if last_interactable != null:
			last_interactable.lose_focus()
			key = last_interactable.KEY
		else:
			key = ""
		plr_head.allow_interact(key,false)
		pass
#endregion
		
#region monster abilities

func ability_check():
	fling_object()
	gravity_flip()
	pass
	

func attack():
	$Damager._damage()
	
	
var grab_held = false

var fling_target:flingable_object
		
func fling_object():
	if !monster: return
	var ray:RayCast3D=plr_head.monster_grab_ray
	
	if grab_held:
		if !fling_target.cooldown:
			$selection_ring.visible = true
			$selection_ring.global_position = fling_target.global_position
		if fling_target.global_position.distance_to(global_position) > 25:
				grab_held = false
				$selection_ring.visible = false
				fling_target = null
	if Input.is_action_just_pressed("grab") and !grab_held:
		if ray.is_colliding():
			if ray.get_collider().owner.has_method("_pull_and_throw"):
				fling_target = ray.get_collider().owner
				grab_held = true

				
	elif Input.is_action_just_pressed("grab") and grab_held:
		if fling_target != null:
			grab_held = false
			$selection_ring.visible = false
			ray.force_raycast_update()
			var host:int=GDSync.get_host()
			await get_tree().physics_frame
			if ray.is_colliding():
				if ray.get_collider().is_class("CharacterBody3D"):
					GDSync.call_func_all(fling_target._pull_and_throw,global_position,ray.get_collision_point(),26,4,self.get_path(),ray.get_collider().get_path())
				else:
					GDSync.call_func_all(fling_target._pull_and_throw,global_position,ray.get_collision_point(),16,4,self.get_path(),"")	
			else:
				GDSync.call_func_all(fling_target._pull_and_throw,global_position,to_global(ray.target_position),12,4,self.get_path(),"")	
			fling_target = null
			
func gravity_flip():
	if Input.is_action_just_pressed("grav"):
		print("grav 1")
		GDSync.emit_signal_remote_all(Network.unfreeze)
		if $gravity_area/CollisionShape3D.disabled == true:
			print("grav 2")
			GDSync.call_func_all(sync_grav_vis,true,$gravity_area/CollisionShape3D.get_path())
			await get_tree().physics_frame
			print($gravity_area.get_overlapping_bodies())
			var plr_array:Array=Network.plr_node_finder($gravity_area.get_overlapping_bodies())
			await get_tree().physics_frame
			print(plr_array)
			for plr:player in plr_array:
				if plr.gravity_state == 1:
					print(GDSync.get_gdsync_owner(plr))
					GDSync.call_func_on(GDSync.get_gdsync_owner(plr),plr.change_gravity_state,1)
					GDSync.call_func_on(GDSync.get_gdsync_owner(plr),GeneralScreen.chaos,true)
		else:
			GDSync.call_func_all(sync_grav_vis,false,$gravity_area/CollisionShape3D.get_path())
		
	if !$gravity_area/CollisionShape3D.disabled:
		var plr_array:Array=Network.plr_node_finder($gravity_area.get_overlapping_bodies())
		for plr:player in plr_array:
			if plr.gravity_state == 1:
				GDSync.call_func_on(GDSync.get_gdsync_owner(plr),plr.change_gravity_state,-1)
				GDSync.call_func_on(GDSync.get_gdsync_owner(plr),GeneralScreen.chaos,true)
					
func sync_grav_vis(on:bool,grav_area_path:NodePath):
	var shape:CollisionShape3D=get_node(grav_area_path)
	if on:
		shape.disabled = false
		shape.visible = true
	else:
		shape.disabled = true
		shape.visible = false
		
	
func change_gravity_state(to:int):
	gravity_state = to
	GDSync.sync_var(self,"gravity_state")
	if gravity_state == 1:
		up_direction = Vector3.UP
		create_tween().tween_property(self,"global_rotation_degrees:z",0,1)
		#global_rotation_degrees.z = 0
	elif gravity_state == -1:
		up_direction = Vector3.DOWN
		create_tween().tween_property(self,"global_rotation_degrees:z",180,1)
		#global_rotation_degrees.z = 180


func _on_gravity_area_body_exited(body: Node3D) -> void:
	if Network.name_is_player(body.name.to_int()):
		var plr:player=body
		if plr.gravity_state == -1:
			GDSync.call_func_on(GDSync.get_gdsync_owner(plr),plr.change_gravity_state,1)
			GDSync.call_func_on(GDSync.get_gdsync_owner(plr),GeneralScreen.chaos,false)
	pass # Replace with function body.


func _on_gravity_area_body_entered(body: Node3D) -> void:
	if monster:
		if body.is_class("RigidBody3D"):
			var grappable:flingable_object=body
			grappable.freeze_timer.start()
			grappable.freeze = false
	pass # Replace with function body.
	
#endregion

#region DEV

func _init_dev():
	Console.add_command("set_health",set_health_dev,["string"],1,"set health : SYNCED")

func set_health_dev(hp:String):
	print("hp to " + hp)
	health = hp.to_int()
	GDSync.sync_var(self,"health",true)
	if plr_head:
		plr_head.update_health(hp.to_int())
	
#endregion
