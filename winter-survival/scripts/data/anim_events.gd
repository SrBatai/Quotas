class_name AnimEvents
## Animation event times (ASSET_SPEC v2 M4.3): `res://data/anim_events.json`, written by the Blender animation
## builders. Keys are the .glb action names, so looping clips keep their `-loop` suffix, which the Godot importer
## strips: the loader normalises them to the Godot clip names. `hit_start` / `hit_end` are the damage windows the
## server evaluates (player melee: Melee.gd; zombie attacks: ZombieSystem._start_attack). Missing file / clip /
## event → the caller's default (the pre-M4 Balance constants).

const PATH := "res://data/anim_events.json"

static var _db: Dictionary = {}
static var _loaded: bool = false


static func _load() -> void:
	_loaded = true
	_db = {}
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		push_warning("AnimEvents: cannot parse %s" % PATH)
		return
	for k in parsed:
		var clip := String(k).trim_suffix("-loop")
		if parsed[k] is Dictionary:
			_db[clip] = parsed[k]


## Seconds from the start of `clip` (Godot name, e.g. "Melee1H_Light_A" or "Zom_Grab") to `event`.
static func at(clip: String, event: String, default: float) -> float:
	if not _loaded:
		_load()
	var row: Dictionary = _db.get(clip, {})
	return float(row.get(event, default))


static func has(clip: String, event: String) -> bool:
	if not _loaded:
		_load()
	return (_db.get(clip, {}) as Dictionary).has(event)
