extends CanvasLayer
# Autoload (scene) name: ReceivedPopup

@export var slot_scene:PackedScene

@onready var root:Control = $Root
@onready var items_box:Container = $Root/Panel/Layout/ItemsFrame/Scroll/Items
@onready var claim_button:Button = $Root/Panel/Layout/ClaimButton

var _queue:Array = [] # reward lists waiting to be shown

func _ready() -> void:
	root.visible = false
	claim_button.pressed.connect(_on_claim_pressed)

# Call from anywhere: ReceivedPopup.show_items(array_of_ItemStack)
# Only call it AFTER the items have been granted.
func show_items(stacks:Array) -> void:
	if stacks.is_empty() or slot_scene == null:
		return
	_queue.append(stacks)
	if !root.visible:
		_show_next()

func _show_next() -> void:
	if _queue.is_empty():
		root.visible = false
		return
	var stacks:Array = _queue.pop_front()
	for c in items_box.get_children():
		items_box.remove_child(c)
		c.queue_free()
	for stack in stacks:
		var slot := slot_scene.instantiate() as ItemSlot
		items_box.add_child(slot)
		slot.setup(stack)
	root.visible = true
	claim_button.grab_focus()

# CLAIM only closes the window. It never grants anything.
func _on_claim_pressed() -> void:
	_show_next()
