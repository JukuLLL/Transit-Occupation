class_name ItemSlot
extends Control

@onready var rarity_box:TextureRect = $RarityBox
@onready var icon_rect:TextureRect = $IconMargin/Icon
@onready var quantity_label:Label = $Quantity

# 1 shows nothing, anything above 1 shows "+amount"
static func quantity_text(quantity:int) -> String:
	if quantity > 1:
		return "+%d" % quantity
	return ""

# Call this after the slot has been added to the scene tree
func setup(stack:ItemStack, slot_size:Vector2 = Vector2.ZERO) -> void:
	if slot_size != Vector2.ZERO:
		custom_minimum_size = slot_size
	if stack == null or stack.item == null:
		return
	rarity_box.texture = Rarity.box_texture(stack.item.rarity)
	icon_rect.texture = stack.item.icon()
	var text := ItemSlot.quantity_text(stack.quantity)
	quantity_label.text = text
	quantity_label.visible = text != ""
