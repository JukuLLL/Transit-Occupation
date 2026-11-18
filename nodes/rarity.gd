class_name Rarity
extends RefCounted

enum Type { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const BOX_PATHS := {
	Type.COMMON: "res://rarity/commonbox.png",
	Type.UNCOMMON: "res://rarity/uncommonbox.png",
	Type.RARE: "res://rarity/rarebox.png",
	Type.EPIC: "res://rarity/epicbox.png",
	Type.LEGENDARY: "res://rarity/legendarybox.png",
}
const NAMES := {
	Type.COMMON: "Common",
	Type.UNCOMMON: "Uncommon",
	Type.RARE: "Rare",
	Type.EPIC: "Epic",
	Type.LEGENDARY: "Legendary",
}
const COLORS := {
	Type.COMMON: Color(0.75, 0.75, 0.75),
	Type.UNCOMMON: Color(0.35, 0.85, 0.35),
	Type.RARE: Color(0.3, 0.55, 1.0),
	Type.EPIC: Color(0.7, 0.35, 0.95),
	Type.LEGENDARY: Color(1.0, 0.65, 0.15),
}

static func box_texture(rarity:int) -> Texture2D:
	return load(BOX_PATHS.get(rarity, BOX_PATHS[Type.COMMON])) as Texture2D

static func display_name(rarity:int) -> String:
	return NAMES.get(rarity, "Common")

static func color(rarity:int) -> Color:
	return COLORS.get(rarity, Color.WHITE)
