extends SceneTree
## M5 persistence gate (ARQ v2 §15, PLAN M5 + v3.8.4): the M2 suite on SqliteBackend (godot-sqlite), schema
## version + numbered migrations on both backends (an M2 JSON document and a v1 SQLite file are upgraded to
## PersistenceSchema.VERSION), world_meta world_version / city_version, WAL, crash safety of the autosave batch,
## VACUUM INTO backups, bans, loot nominal counters and the BackendFactory fallback rules.
## Run: godot --headless --path . -s tests/unit/persistence_m5_test.gd  → "== N checks, ALL PASSED" / exit 1.
## Without the addon (tools/fetch_godot_sqlite.sh not run) the SQLite part reports SKIP and the rest still runs.

var _body: RefCounted


func _initialize() -> void:
	var script: GDScript = load("res://tests/unit/persistence_m5_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load persistence_m5_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run_m5(self)
	var t := create_timer(90.0)
	t.timeout.connect(func() -> void:
		print("FAIL: persistence M5 test watchdog timeout")
		quit(1))
