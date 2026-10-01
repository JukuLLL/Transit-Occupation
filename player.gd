extends CharacterBody3D

@export var speed := 5.0
@export var sprint_speed := 10.0
@export var mouse_sensitivity := 0.002

@onready var head = $Head
@onready var first_person_camera = $Head/FirstPersonCamera
@onready var third_person_camera = $Head/ThirdPersonArm/ThirdPersonCamera
@onready var player_mesh = $MeshInstance3D

var first_person := true

# DASH
var dash_cooldown := 2.0
var dash_timer := 0.0
var dash_speed := 10.0
var dash_duration := 0.7
var dash_momentum_timer := 0.0

# JUMP
var jump_velocity := 7.0
var gravity := 20.0

# MOVEMENT
var bunnyhop_acceleration := 1.5
var ground_acceleration := 20.0
var ground_friction := 100.0

# Keeps track of whether the player has extra momentum
# from a dash or bunnyhopping.
var has_extra_momentum := false


func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	first_person_camera.current = true
	third_person_camera.current = false
	
	player_mesh.visible = false


func _unhandled_input(event):
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
				velocity.x += direction.x * bunnyhop_acceleration
				velocity.z += direction.z * bunnyhop_acceleration
			
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
					velocity.x = 0
					velocity.z = 0
					
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
		if direction:
			velocity.x += direction.x * bunnyhop_acceleration * delta
			velocity.z += direction.z * bunnyhop_acceleration * delta
	
	
	# DASH
	if Input.is_action_just_pressed("dash") and dash_timer <= 0:
		do_dash(direction)
	
	
	move_and_slide()


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
