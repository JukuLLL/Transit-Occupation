class_name Jumpscare
extends Resource

@export_group("Sound")
@export var sound:AudioStream            # this monster's jumpscare sound
@export var volume_db := 0.0

@export_group("Sequence")
@export var duration := 1.0              # seconds both characters are locked
@export var stand_distance := 1.6        # how far in front of the survivor the monster stands
@export var look_height := 1.3           # where on the monster the survivor looks (meters above its feet)

@export_group("Monster attack")
@export var monster_anim := ""           # AnimationPlayer animation to play (empty = placeholder lunge)
@export var lunge_distance := 0.7        # placeholder lunge, in meters

@export_group("Survivor reaction")
@export var survivor_anim := ""          # AnimationPlayer animation to play (empty = placeholder recoil)
@export var recoil_degrees := 25.0       # body lean back (negative if it leans the wrong way)
@export var camera_kick := 14.0          # degrees the first-person view snaps upward
@export var camera_roll := 8.0           # degrees the first-person view tilts
@export var shake := 1.0                 # camera shake strength (0 = none)
