class_name player extends CharacterBody3D

@export var speed := 5.0
@export var sprint_speed := 10.0
@export var jump_multiplier:float=1
@export var mouse_sensitivity := 0.002
@export var grapple_ray:RayCast3D
@export var grapple_force:float=1
@export var in_grapple = false
@export var grapple_sensitivity := 300
@export var grapple_distance:float=1.0

@export var monster:bool=false

@onready var head = $Head
@onready var crosshair = $Head.crosshair
@onready var first_person_camera = $Head.first_person_camera
@onready var third_person_camera = $Head.third_person_camera
@onready var player_mesh = $MeshInstance3D

var first_person := true

# DASH
var dash_cooldown := 2.0
var dash_timer := 0.4
var dash_speed := 8
var dash_duration := 0.7
var dash_momentum_timer := 0.7

# JUMP
var jump_velocity := 7.0
var gravity := 20.0

# MOVEMENT
var bunnyhop_acceleration := 0.05
var ground_acceleration := 20.0
var ground_friction := 10000

# Keeps track of whether the player has extra momentum
# from a dash or bunnyhopping.
var has_extra_momentum := false
var cross_hair_regular_pos:Vector2
var grapple_area:Rect2
@export var filter:PackedScene

func owner_changed(id:int):
	print("owner_changed")
	var is_owner:bool=GDSync.is_gdsync_owner(self)
	if !is_owner:
		head.queue_free()
	if is_owner:
		$OmniLight3D.visible = true
		first_person_camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var screen:Rect2=get_viewport().get_visible_rect()
		crosshair.position = screen.size / 2
		cross_hair_regular_pos = crosshair.position
		grapple_area = screen
		grapple_area.position = grapple_area.end * 1.5
		first_person_camera.current = true
		third_person_camera.current = false
		player_mesh.visible = false
		first_person_camera.make_current()
		await get_tree().physics_frame
		if GDSync.player_get_data(GDSync.get_gdsync_owner(self),"TEAM") == "MONSTER":
			monster = true
			add_child(filter.instantiate())
			grapple_ray.set_collision_mask_value(32,false)
		else:
			monster = false
		print(GDSync.player_get_data(GDSync.get_gdsync_owner(self),"TEAM"))
	pass

func _ready():
	grapple_ray = head.grapple_ray
	GDSync.connect_gdsync_owner_changed(self,owner_changed)
	if monster:
		grapple_ray.target_position.z = (25 * grapple_distance) * -1


func _unhandled_input(event):
	if !GDSync.is_gdsync_owner(self): return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Turn the player left/right
		rotate_y(-event.relative.x * mouse_sensitivity)
		
		# Look up/down
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		
		# Prevent the camera from flipping upside down
		head.rotation.x = clamp(
			head.rotation.x,
			deg_to_rad(-80),
			deg_to_rad(80)
		)
	
	if event.is_action_pressed("toggle_camera"):
		toggle_camera()
	if Input.is_action_just_pressed("ui_cancel"):
		await get_tree().process_frame
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta):
	if !GDSync.is_gdsync_owner(self): return
	$Label.text = str(velocity.length())
	$Label2.text = str(grappling_target)
	# DASH COOLDOWN
	if dash_timer > 0:
		dash_timer -= delta
	
	
	# GET MOVEMENT INPUT
	var input := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	
	var direction := Vector3(input.x, 0, input.y)
	
	# Convert movement from local player space to world space
	direction = transform.basis * direction
	direction.y = 0
	
	if direction.length() > 0:
		direction = direction.normalized()
	
	
	# GROUND MOVEMENT
	if is_on_floor():
		
		# Jump
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity * jump_multiplier
			
			# Preserve existing momentum.
			# This is what allows bunnyhopping.
			if direction:
				velocity.x -= direction.x
				velocity.z -= direction.z
			
			# Keep the extra momentum when jumping
			if has_extra_momentum:
				has_extra_momentum = true
		
		else:
			# DASH MOMENTUM
			if has_extra_momentum:
				# Countdown the dash momentum
				dash_momentum_timer -= delta
				
				# Dash has finished
				if dash_momentum_timer <= 0:
					# Completely stop the player
					velocity.x = move_toward(velocity.x,0,delta * 250)
					velocity.z = move_toward(velocity.z,0,delta * 250)
					
					if velocity.length() == 0:
						has_extra_momentum = false
			
			# NORMAL GROUND MOVEMENT
			else:
				if direction:
					var current_speed := speed
					
					if Input.is_action_pressed("sprint"):
						current_speed = sprint_speed
					
					var target_velocity := direction * current_speed
					
					velocity.x = move_toward(
						velocity.x,
						target_velocity.x,
						ground_acceleration * delta
					)
					
					velocity.z = move_toward(
						velocity.z,
						target_velocity.z,
						ground_acceleration * delta
					)
				
				else:
					# Stop normal movement
					velocity.x = move_toward(
						velocity.x,
						0,
						ground_friction * delta
					)
					
					velocity.z = move_toward(
						velocity.z,
						0,
						ground_friction * delta
					)
	
	
	# AIR MOVEMENT
	else:
		# Gravity
		velocity.y -= gravity * delta
		
		# Air control
		var current_speed := speed
		var target_velocity :Vector3= direction * current_speed
		velocity.x = move_toward(
					velocity.x,
					target_velocity.x,
					bunnyhop_acceleration * 10
				)
				
		velocity.z = move_toward(
					velocity.z,
					target_velocity.z,
					bunnyhop_acceleration * 10
				)
			#velocity.x += (direction.x * bunnyhop_acceleration)
		#	velocity.z += (direction.z * bunnyhop_acceleration)
	
	
	# DASH
	if Input.is_action_just_pressed("dash") and dash_timer <= 0:
		do_dash(direction)
	if grapple_pos != null:
		grapple_ray.look_at(grapple_pos)
	if grapple_ray.is_colliding():
		grappling_target = grapple_ray.get_collider()
	
	grappling_hook(delta)
	
	fling_object()
	
	move_and_slide()
	
var grappling_target:Node3D=self

var grapple_pos:Vector3=Vector3.ZERO

func is_in_range(pos:Vector2) -> bool:
	$Label3.text = str(cross_hair_regular_pos.distance_to(pos))
	if cross_hair_regular_pos.distance_to(pos) < grapple_sensitivity:
		return true
	else:
		return false
		
var grab_held = false
		
func fling_object():
	if !monster: return
	var ray:RayCast3D=head.monster_grab_ray
	
	if grab_held:
		if !fling_target.cooldown:
			$selection_ring.visible = true
			$selection_ring.global_position = fling_target.global_position
			fling_target.add_collision_exception_with(self)
			ray.add_exception(fling_target)
		if fling_target.global_position.distance_to(global_position) > 25:
				grab_held = false
				fling_target.remove_collision_exception_with(self)
				$selection_ring.visible = false
				ray.remove_exception(fling_target)
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
			ray.add_exception(fling_target)
			ray.force_raycast_update()
			await get_tree().physics_frame
			if ray.is_colliding():
				if ray.get_collider().is_class("CharacterBody3D"):
					fling_target._pull_and_throw(global_position,ray.get_collision_point(),26,4,self)	
				else:
					fling_target._pull_and_throw(global_position,ray.get_collision_point(),16,4,self)	
			else:
				fling_target._pull_and_throw(global_position,to_global(ray.target_position),12,4,self)	
			fling_target = null
			ray.remove_exception(fling_target)
			
var fling_target:flingable_object
	
func set_grapple_target(pos:Vector3):
	grapple_pos = pos
	if first_person_camera.is_position_in_frustum(grapple_pos):
		in_grapple = true
	if grappling_target != null:
		if grappling_target.is_in_group("grapple") and is_in_range(first_person_camera.unproject_position(grapple_pos)):
			crosshair.position = first_person_camera.unproject_position(grapple_pos)
			crosshair.play("interact")
		
func grappling_hook(delta:float):
	var mouse_side:float = Input.get_axis("left_click","right_click")
	if mouse_side and grapple_ray.is_colliding() and grappling_target.is_in_group("grapple") and is_in_range(first_person_camera.unproject_position(grapple_pos)) and first_person_camera.is_position_in_frustum(grapple_pos):
		var direction:Vector3=global_position.direction_to(grapple_ray.get_collision_point())
		velocity += direction * (grapple_force * (global_position.distance_to(grapple_ray.get_collision_point()) / 7)) - Vector3(0,0.1,0)
	elif !grappling_target.is_in_group("grapple") or !is_in_range(first_person_camera.unproject_position(grapple_pos)):
		#grapple_ray.rotation = Vector3.ZERO
		in_grapple = false
		crosshair.position = cross_hair_regular_pos
		crosshair.play("default")
		pass
		
		


func do_dash(direction: Vector3):
	if direction == Vector3.ZERO:
		direction = -transform.basis.z
		direction.y = 0
		direction = direction.normalized()
	var current_dash = dash_speed
	
	if monster:
		current_dash *= 2
	# Add dash momentum
	velocity.x += direction.x * current_dash
	velocity.z += direction.z * current_dash
	
	# Start the dash momentum timer
	dash_momentum_timer = dash_duration
	
	# Remember that we're carrying dash momentum
	has_extra_momentum = true
	
	# Start dash cooldown
	dash_timer = dash_cooldown


func toggle_camera():
	first_person = not first_person
	
	if first_person:
		first_person_camera.current = true
		third_person_camera.current = false
		
		# Don't see our own body in first person
		player_mesh.visible = false
	
	else:
		first_person_camera.current = false
		third_person_camera.current = true
		
		# Show body in third person
		player_mesh.visible = true
