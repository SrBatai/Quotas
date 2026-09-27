class_name Autosave
extends Node
## Server autosave (ARQ v2 §15.3, PLAN C12): every `[world] autosave_seconds` (60) one batch = one SQLite
## transaction with every dirty ChunkDelta + the connected profiles + world_meta (PlayerManager.save_all). A crash
## loses at most that window: the store always holds the last complete autosave (WAL / atomic JSON rename).
## Also once per real day a `VACUUM INTO` (SQLite) or file copy (JSON) backup to <save dir>/backups/world-YYYYMMDD.*,
## keeping `[world] backup_keep` (7) of them. Other save points call PlayerManager directly: player leave, chunk
## hibernation, container close, admin `save` / `save-and-quit` / `backup`.

var manager: PlayerManager
var period: float = 60.0
var keep: int = 7
var saves: int = 0
var last_save_ms: float = 0.0
var last_backup: String = ""
var _t: float = 0.0


func setup(p_manager: PlayerManager) -> void:
	manager = p_manager
	period = maxf(float(Net.cfg_get("world", "autosave_seconds", 60.0)), 5.0)
	keep = maxi(int(Net.cfg_get("world", "backup_keep", 7)), 1)


func _process(delta: float) -> void:
	if manager == null or not Net.is_dedicated:
		return
	_t += delta
	if _t >= period:
		_t = 0.0
		var t0 := Time.get_ticks_usec()
		manager.save_all()
		last_save_ms = (Time.get_ticks_usec() - t0) / 1000.0
		saves += 1
		daily_backup()


## Directory of the daily backups (next to the save file).
func backup_dir() -> String:
	return manager.save_path.get_base_dir().path_join("backups")


## Writes today's backup if it does not exist yet and prunes the oldest beyond `keep`. Returns the path ("" = none).
func daily_backup(force: bool = false) -> String:
	if manager == null or manager.backend == null or manager.save_path == "":
		return ""
	var d := Time.get_date_dict_from_system(true)
	var ext := "db" if manager.backend.kind() == "sqlite" else "json"
	var path := backup_dir().path_join("world-%04d%02d%02d.%s" % [d["year"], d["month"], d["day"], ext])
	if not force and FileAccess.file_exists(path):
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup_dir()))
	var err := manager.backend.backup(path)
	if err != OK:
		push_warning("Autosave: backup %s failed (%s)" % [path, error_string(err)])
		return ""
	last_backup = path
	print("[EVT] backup %s" % path)
	_prune()
	return path


func _prune() -> void:
	var dir := DirAccess.open(ProjectSettings.globalize_path(backup_dir()))
	if dir == null:
		return
	var files: Array[String] = []
	for f in dir.get_files():
		if f.begins_with("world-") and (f.ends_with(".db") or f.ends_with(".json")):
			files.append(f)
	files.sort()
	while files.size() > keep:
		var old: String = files.pop_front()
		dir.remove(old)
		print("[EVT] backup pruned %s" % old)
