class_name LevelCard
extends Button

@export var slot_scene:PackedScene

@onready var number_label:Label = $Content/NumberLabel
@onready var reward_list:Container = $Content/RewardArea/RewardList
@onready var claim_indicator:CanvasItem = $ClaimIndicator
@onready var claimed_label:CanvasItem = $ClaimedLabel

var level := 0

func setup(l:int) -> void:
	level = l
	number_label.text = str(l)
	_build_rewards()
	pressed.connect(_on_pressed)
	PlayerProgress.progress_changed.connect(_refresh)
	PlayerProgress.rewards_changed.connect(_refresh)
	_refresh()

func _build_rewards() -> void:
	if slot_scene == null:
		push_error("LevelCard: assign Slot Scene in the Inspector.")
		return
	for stack in LevelRewards.for_level(level):
		var slot := slot_scene.instantiate() as ItemSlot
		reward_list.add_child(slot)
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.setup(stack, Vector2(100, 100))

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
	# The popup only opens after the rewards were really granted
	if PlayerProgress.claim(level):
		ReceivedPopup.show_items(LevelRewards.for_level(level))
