class_name player extends CharacterBody3D

@export var speed := 5.0
@export var sprint_speed := 10.0
@export var mouse_sensitivity := 0.002
@export var grapple_ray:RayCast3D
@export var grapple_force:float=1
@export var in_grapple = false
@export var grapple_sensitivity := 300

@onready var head = $Head
@onready var first_person_camera = $Head/FirstPersonCamera
@onready var third_person_camera = $Head/ThirdPersonArm/ThirdPersonCamera
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

func owner_changed(id:int):
	print("owner_changed")
	var is_owner:bool=GDSync.is_gdsync_owner(self)
	if !is_owner:
		$crosshair.visible = false
		$Head.queue_free()
	if is_owner:
		$Head/FirstPersonCamera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var screen:Rect2=get_viewport().get_visible_rect()
		$crosshair.position = screen.size / 2
		cross_hair_regular_pos = $crosshair.position
		grapple_area = screen
		grapple_area.position = grapple_area.end * 1.5
		first_person_camera.current = true
		third_person_camera.current = false
		player_mesh.visible = false
	pass

func _ready():
	GDSync.connect_gdsync_owner_changed(self,owner_changed)


func _unhandled_input(event):
	if !GDSync.is_gdsync_owner(self): return
	if event is InputEventMouseMotion:
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
			velocity.y = jump_velocity
			
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
					bunnyhop_acceleration
				)
				
		velocity.z = move_toward(
					velocity.z,
					target_velocity.z,
					bunnyhop_acceleration
				)
			#velocity.x += (direction.x * bunnyhop_acceleration)
		#	velocity.z += (direction.z * bunnyhop_acceleration)
	
	
	# DASH
	if Input.is_action_just_pressed("dash") and dash_timer <= 0:
		do_dash(direction)
	grapple_ray.look_at(grapple_pos)
	if grapple_ray.is_colliding():
		grappling_target = grapple_ray.get_collider()
	
	grappling_hook(delta)
	
	move_and_slide()
	
var grappling_target:Node3D=self

var grapple_pos:Vector3=Vector3.ZERO

func is_in_range(pos:Vector2) -> bool:
	$Label3.text = str(cross_hair_regular_pos.distance_to(pos))
	if cross_hair_regular_pos.distance_to(pos) < grapple_sensitivity:
		return true
	else:
		return false
		
var grapple_positions = []
	
func set_grapple_target(pos:Vector3):
	grapple_pos = pos
	if $Head/FirstPersonCamera.is_position_in_frustum(grapple_pos):
		in_grapple = true
	if grappling_target != null:
		if grappling_target.is_in_group("grapple") and is_in_range($Head/FirstPersonCamera.unproject_position(grapple_pos)):
			$crosshair.position = $Head/FirstPersonCamera.unproject_position(grapple_pos)
			$crosshair.play("interact")
		
func grappling_hook(delta:float):
	var mouse_side:float = Input.get_axis("left_click","right_click")
	if mouse_side and grapple_ray.is_colliding() and grappling_target.is_in_group("grapple") and is_in_range($Head/FirstPersonCamera.unproject_position(grapple_pos)) and $Head/FirstPersonCamera.is_position_in_frustum(grapple_pos):
		var direction:Vector3=global_position.direction_to(grapple_ray.get_collision_point())
		velocity += direction * (grapple_force * (global_position.distance_to(grapple_ray.get_collision_point()) / 7)) - Vector3(0,0.1,0)
	elif !grappling_target.is_in_group("grapple") or !is_in_range($Head/FirstPersonCamera.unproject_position(grapple_pos)):
		#grapple_ray.rotation = Vector3.ZERO
		in_grapple = false
		$crosshair.position = cross_hair_regular_pos
		$crosshair.play("default")
		pass
		


func do_dash(direction: Vector3):
	if direction == Vector3.ZERO:
		direction = -transform.basis.z
		direction.y = 0
		direction = direction.normalized()
	
	# Add dash momentum
	velocity.x += direction.x * dash_speed
	velocity.z += direction.z * dash_speed
	
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
