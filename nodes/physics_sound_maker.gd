class_name physics_sounds extends Node

var parent_rigid_body:RigidBody3D


@export var sound_list_high_velocity:Array[AudioStream]

@export var sound_list_low_velocity:Array[AudioStream]

@export var sound_velocity:float

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	parent_rigid_body = get_parent()
	pass # Replace with function body.

var spawned_sound:Array[SynchronizedAudioStreamPlayer3D]

var sound_cooldown = 0

var velocity_cooldown = 0

var last_velocity:float

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if parent_rigid_body:
		if parent_rigid_body.get_contact_count() > 0:
			if last_velocity > sound_velocity and sound_cooldown < 1 and !sound_list_high_velocity.is_empty():
				sound_cooldown = 4
				print("physic")
				var audio:SynchronizedAudioStreamPlayer3D=SynchronizedAudioStreamPlayer3D.new()
				audio.stream = sound_list_high_velocity.pick_random()
				audio.volume_db = 0.1
				audio.pitch_scale = randf_range(0.95,1.02)
				audio.panning_strength = 2
				audio.max_polyphony = 10
				audio.max_db = 1
				get_tree().current_scene.add_child(audio)
				spawned_sound.append(audio)
				audio.play_synced()
			elif last_velocity > (sound_velocity / 3) and sound_cooldown < 1 and !sound_list_low_velocity.is_empty():
				sound_cooldown = 2
				print("physic")
				var audio:SynchronizedAudioStreamPlayer3D=SynchronizedAudioStreamPlayer3D.new()
				audio.stream = sound_list_low_velocity.pick_random()
				audio.volume_db = 0.1
				audio.pitch_scale = randf_range(0.95,1.02)
				audio.panning_strength = 2
				audio.max_polyphony = 10
				audio.max_db = 1
				get_tree().current_scene.add_child(audio)
				spawned_sound.append(audio)
				audio.play_synced()
			elif sound_cooldown > 0:
				sound_cooldown -= 1
		if velocity_cooldown < 1:
			velocity_cooldown = 1
			last_velocity = abs(parent_rigid_body.linear_velocity).length() + (abs(parent_rigid_body.angular_velocity).length() / 10)
		else:
			velocity_cooldown -= 0.5
			
	
				
	for sound:SynchronizedAudioStreamPlayer3D in spawned_sound:
		sound.global_position = parent_rigid_body.global_position
		if !sound.playing:
			spawned_sound.erase(sound)
			sound.queue_free()
				
	pass
