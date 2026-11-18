class_name LevelRewards
extends RefCounted

static func gold_coins_for(level:int) -> int:
	if level % 5 == 0:
		return level
	return 1 + floori(level / 5.0)

static func credits_for(level:int) -> int:
	if level == 1:
		return 1000
	return 250 * (level - 1)

static func for_level(level:int) -> Array[ItemStack]:
	var out:Array[ItemStack] = []
	if level < 1 or level > LevelMath.MAX_LEVEL:
		return out
	out.append(ItemDB.make_stack("gold_coins", gold_coins_for(level)))
	out.append(ItemDB.make_stack("credits", credits_for(level)))
	return out
