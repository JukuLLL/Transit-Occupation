class_name GroupedAreaLIght3D extends AreaLight3D

@export var allow_modifications:bool=true
@export var shadows_default:bool=true

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.add_to_group("lights")
	shadow_enabled = shadows_default
	pass # Replace with function body.


func change_light_color(color_to:Color,fade:bool=false,fade_time:float=0):
	if !allow_modifications:return
	if fade:
		create_tween().tween_property(self,"light_color",color_to,fade_time)
	else:
		light_color = color_to
		
func hide_light():
	if !allow_modifications:return
	self.hide()
