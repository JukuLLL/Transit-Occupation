extends Control

@onready var select_mic: OptionButton = $CanvasLayer2/microphone/select_mic
@onready var select_out: OptionButton = $CanvasLayer2/output/select_out


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for device:String in AudioServer.get_input_device_list():
		select_mic.add_item(device)
	for device:String in AudioServer.get_output_device_list():
		select_out.add_item(device)
	pass # Replace with function body.
	
func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		queue_free()


func _on_select_mic_item_selected(index: int) -> void:
	AudioServer.input_device = select_mic.get_item_text(index)
	pass # Replace with function body.


func _on_select_out_item_selected(index: int) -> void:
	AudioServer.output_device = select_out.get_item_text(index)
	pass # Replace with function body.


func _on_select_gi_item_selected(index: int) -> void:
	if index == 0:
		RenderingServer.voxel_gi_set_quality(RenderingServer.VOXEL_GI_QUALITY_LOW)
	else:
		RenderingServer.voxel_gi_set_quality(RenderingServer.VOXEL_GI_QUALITY_HIGH)
	pass # Replace with function body.
