class_name LevelCard
extends Button

@onready var number_label:Label = $Content/NumberLabel
@onready var claim_indicator:CanvasItem = $ClaimIndicator
@onready var claimed_label:CanvasItem = $ClaimedLabel

var level := 0

func setup(l:int) -> void:
	level = l
	number_label.text = str(l)
	pressed.connect(_on_pressed)
	PlayerProgress.progress_changed.connect(_refresh)
	PlayerProgress.rewards_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	var claimed := PlayerProgress.is_claimed(level)
	var claimable := PlayerProgress.can_claim(level)
	claim_indicator.visible = claimable
	claimed_label.visible = claimed
	disabled = !claimable
	if claimed:
		modulate = Color(0.7, 1.0, 0.7)
	elif claimable:
		modulate = Color.WHITE
	else:
		modulate = Color(0.55, 0.55, 0.55)

func _on_pressed() -> void:
	PlayerProgress.claim(level)
