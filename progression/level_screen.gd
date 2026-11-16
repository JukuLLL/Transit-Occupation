extends Control

@export var card_scene:PackedScene

@onready var exit_button:Button = $ExitButton
@onready var level_label:Label = $Info/CurrentLevelLabel
@onready var xp_label:Label = $Info/XPLabel
@onready var xp_bar:ProgressBar = $Info/XPBar
@onready var scroll:ScrollContainer = $LevelScroll
@onready var card_list:HBoxContainer = $LevelScroll/LevelList

func _ready() -> void:
	exit_button.pressed.connect(queue_free)
	if card_scene == null:
		push_error("LevelScreen: assign Card Scene in the Inspector.")
		return
	for l in range(1, LevelMath.MAX_LEVEL + 1):
		var card := card_scene.instantiate() as LevelCard
		card_list.add_child(card)
		card.setup(l)
	PlayerProgress.progress_changed.connect(_refresh)
	_refresh()
	
	# Dev helper: only exists while running from the editor
	var dev := get_node_or_null("DevAddXP") as Button
	if dev != null:
		dev.visible = OS.has_feature("editor")
		dev.pressed.connect(func(): PlayerProgress.add_xp(250))
	
	_scroll_to_relevant_level()

func _refresh() -> void:
	var b := LevelMath.breakdown(PlayerProgress.total_xp)
	level_label.text = "LEVEL %d" % b["level"]
	if b["needed"] == 0:
		xp_label.text = "MAX LEVEL"
		xp_bar.max_value = 1
		xp_bar.value = 1
	else:
		xp_label.text = "%d/%d XP" % [b["xp"], b["needed"]]
		xp_bar.max_value = b["needed"]
		xp_bar.value = b["xp"]

# Opens the list at the first unclaimed reward, or at your current level
func _scroll_to_relevant_level() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var target := maxi(PlayerProgress.level, 1)
	for l in range(1, PlayerProgress.level + 1):
		if PlayerProgress.can_claim(l):
			target = l
			break
	var card := card_list.get_child(target - 1) as Control
	scroll.scroll_horizontal = int(maxf(card.position.x - 60.0, 0.0))
