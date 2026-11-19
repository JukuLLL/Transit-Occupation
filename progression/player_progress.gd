extends Node
# Autoload name: PlayerProgress

signal progress_changed
signal rewards_changed
signal level_up(new_level:int)
signal reward_claimed(level:int)

const SYNC_DIR := "user://saves"        # the folder Steam Cloud will sync
const LOCAL_DIR := "user://saves_local" # used when Steam isn't running, never synced
const SAVE_VERSION := 1

var total_xp := 0
var level := 0
var claimed:Dictionary = {} # level -> true

var _save_path := ""

func _ready() -> void:
	_save_path = _build_save_path()
	_load()

# ---------- Questions ----------
func is_reached(l:int) -> bool:
	return l >= 1 and l <= level

func is_claimed(l:int) -> bool:
	return claimed.has(l)

func can_claim(l:int) -> bool:
	return is_reached(l) and !is_claimed(l)

func has_claimable() -> bool:
	for l in range(1, level + 1):
		if !claimed.has(l):
			return true
	return false

# ---------- Changes ----------
func add_xp(amount:int) -> void:
	if amount <= 0:
		return
	var old_level := level
	var cap := LevelMath.total_xp_for_level(LevelMath.MAX_LEVEL)
	total_xp = mini(total_xp + amount, cap)
	level = LevelMath.level_from_total_xp(total_xp)
	_save()
	progress_changed.emit()
	if level > old_level:
		rewards_changed.emit()
		for l in range(old_level + 1, level + 1):
			level_up.emit(l)

func claim(l:int) -> bool:
	if !can_claim(l):
		return false
	claimed[l] = true
	if !_save():
		claimed.erase(l) # not saved, so not claimed: no double rewards later
		return false
	_grant_reward(l)
	rewards_changed.emit()
	reward_claimed.emit(l)
	return true

func _grant_reward(l:int) -> void:
	for stack in LevelRewards.for_level(l):
		ItemDB.grant(stack)

# ---------- Saving ----------
func _steam_account_known() -> bool:
	return SteamManager.steam_ok and str(SteamManager.steam_id) != "0"

func _build_save_path() -> String:
	if _steam_account_known():
		DirAccess.make_dir_recursive_absolute(SYNC_DIR)
		return "%s/progress_%s.cfg" % [SYNC_DIR, str(SteamManager.steam_id)]
	DirAccess.make_dir_recursive_absolute(LOCAL_DIR)
	return LOCAL_DIR + "/progress_offline.cfg"

# Reads the file and keeps whichever is further: never lowers XP, never forgets a claim
func _merge_from_disk() -> int:
	if !FileAccess.file_exists(_save_path):
		return OK
	var cfg := ConfigFile.new()
	var err := cfg.load(_save_path)
	if err != OK:
		return err
	var disk_xp := maxi(int(cfg.get_value("progress", "total_xp", 0)), 0)
	if disk_xp > total_xp:
		total_xp = disk_xp
	level = LevelMath.level_from_total_xp(total_xp)
	for l in cfg.get_value("progress", "claimed_levels", []):
		var lv := int(l)
		if lv >= 1 and lv <= LevelMath.MAX_LEVEL:
			claimed[lv] = true
	return OK

func _load() -> void:
	var err := _merge_from_disk()
	if err != OK:
		push_error("Progress file could not be read (error %d). Keeping a backup copy." % err)
		DirAccess.copy_absolute(_save_path, "%s.corrupt_%d" % [_save_path, int(Time.get_unix_time_from_system())])

func _save() -> bool:
	_merge_from_disk() # protects progress that a newer synced file already has
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("meta", "saved_at", Time.get_unix_time_from_system())
	cfg.set_value("progress", "total_xp", total_xp)
	cfg.set_value("progress", "claimed_levels", claimed.keys())
	var tmp := _save_path + ".tmp"
	if cfg.save(tmp) == OK and DirAccess.rename_absolute(tmp, _save_path) == OK:
		return true
	return cfg.save(_save_path) == OK

# Dev only: wipes XP, level and claimed rewards.
# Writes the file directly, because a normal save would merge the old progress back in.
func dev_reset() -> void:
	total_xp = 0
	level = 0
	claimed.clear()
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("meta", "saved_at", Time.get_unix_time_from_system())
	cfg.set_value("progress", "total_xp", 0)
	cfg.set_value("progress", "claimed_levels", [])
	cfg.save(_save_path)
	progress_changed.emit()
	rewards_changed.emit()
