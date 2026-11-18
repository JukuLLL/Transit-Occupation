class_name ItemDB
extends RefCounted

static var _items:Dictionary = {}

static func _ensure_loaded() -> void:
	if !_items.is_empty():
		return
	# To add a new item or currency later: add one line here
	_register(ItemDef.new("credits", "Credits", "res://items/credits.png", Rarity.Type.COMMON, "currency"))
	_register(ItemDef.new("gold_coins", "Gold Coins", "res://items/goldcoins.png", Rarity.Type.LEGENDARY, "currency"))

static func _register(def:ItemDef) -> void:
	_items[def.id] = def

static func get_item(id:String) -> ItemDef:
	_ensure_loaded()
	return _items.get(id)

static func make_stack(id:String, quantity:int) -> ItemStack:
	return ItemStack.new(get_item(id), quantity)

# Actually gives the player the stack. Returns false if it could not.
static func grant(stack:ItemStack) -> bool:
	if stack == null or stack.item == null or stack.quantity <= 0:
		return false
	match stack.item.kind:
		"currency":
			var tree := Engine.get_main_loop() as SceneTree
			if tree == null:
				return false
			var currency := tree.root.get_node_or_null("Currency")
			if currency == null:
				return false
			return bool(currency.add_currency(stack.item.id, stack.quantity))
	push_warning("ItemDB: don't know how to grant item kind '%s'" % stack.item.kind)
	return false
