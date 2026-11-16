extends TextureButton

@export var level_screen_scene:PackedScene

@onready var number_label:Label = $LevelNumber
@onready var claim_indicator:CanvasItem = $ClaimIndicator

var open_screen:Node

func _ready() -> void:
	pressed.connect(_on_pressed)
	PlayerProgress.progress_changed.connect(_refresh)
	PlayerProgress.rewards_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	number_label.text = str(PlayerProgress.level)
	claim_indicator.visible = PlayerProgress.has_claimable()

func _on_pressed() -> void:
	if level_screen_scene == null or is_instance_valid(open_screen):
		return
	open_screen = level_screen_scene.instantiate()
	get_tree().current_scene.add_child(open_screen)
