class_name TimedDamager extends Damager

@export var interval:float = 1.0

var timers:Dictionary = {}

func _physics_process(delta: float) -> void:
	var current:Array = get_overlapping_bodies()
	
	for body in current:
		if body is player and GDSync.is_gdsync_owner(body):
			# First touch starts at "interval", so you get hit right away
			timers[body] = timers.get(body, interval) + delta
			if timers[body] >= interval:
				timers[body] = 0.0
				_damage()
	
	# Forget players who stepped off the block
	for body in timers.keys():
		if body not in current:
			timers.erase(body)
