class_name ItemDef
extends RefCounted

var id:String
var display_name:String
var icon_path:String
var rarity:int
var kind:String # "currency" for now; future kinds: "cosmetic", "key", ...

func _init(p_id:String, p_name:String, p_icon_path:String, p_rarity:int, p_kind:String = "item") -> void:
	id = p_id
	display_name = p_name
	icon_path = p_icon_path
	rarity = p_rarity
	kind = p_kind

func icon() -> Texture2D:
	return load(icon_path) as Texture2D
