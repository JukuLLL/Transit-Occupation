class_name LevelMath
extends RefCounted

const MAX_LEVEL := 50

# XP needed to go from (level - 1) to level
static func xp_for_level(level:int) -> int:
	if level < 1 or level > MAX_LEVEL:
		return 0
	if level <= 10:
		return level * 100
	return (level - 9) * 1000

# Total XP from zero needed to reach a level
static func total_xp_for_level(level:int) -> int:
	var total := 0
	for l in range(1, mini(level, MAX_LEVEL) + 1):
		total += xp_for_level(l)
	return total

# Returns {"level": current level, "xp": XP earned inside it, "needed": XP for the next level (0 at max)}
static func breakdown(total_xp:int) -> Dictionary:
	var level := 0
	var remaining := maxi(total_xp, 0)
	while level < MAX_LEVEL:
		var need := xp_for_level(level + 1)
		if remaining < need:
			return {"level": level, "xp": remaining, "needed": need}
		remaining -= need
		level += 1
	return {"level": MAX_LEVEL, "xp": 0, "needed": 0}

static func level_from_total_xp(total_xp:int) -> int:
	return int(breakdown(total_xp)["level"])
