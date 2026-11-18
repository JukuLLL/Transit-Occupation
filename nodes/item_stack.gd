class_name ItemStack
extends RefCounted

var item:ItemDef
var quantity := 1

func _init(p_item:ItemDef = null, p_quantity:int = 1) -> void:
	item = p_item
	quantity = p_quantity
