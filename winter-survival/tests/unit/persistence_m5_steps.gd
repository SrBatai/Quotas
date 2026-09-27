extends "res://tests/unit/persistence_steps.gd"
## Body of tests/unit/persistence_m5_test.gd (M5). Reuses the M2 suite (`_suite`) of persistence_steps.gd on
## SqliteBackend and adds: reload, WAL / integrity, a crash in the middle of an autosave batch (a child process is
## killed with the transaction open), migrations v0/v1 → current on both backends, newer schema refused,
## world_meta stamping, VACUUM INTO backups, bans, loot nominal counters and the BackendFactory rules.

const DIR := "user://persistence_m5"


func run_m5(p_tree: SceneTree) -> void:
	tree = p_tree
	await tree.process_frame
	print("== VENTISCA persistence M5 test (SqliteBackend + schema %d + migrations)" % PersistenceSchema.VERSION)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_factory_rules()
	_file_migrations()
	for b in [MemoryBackend.new(), FileBackend.new()]:
		_meta_bans_nominal(b, DIR + "/extras_%s.json" % b.kind())
	if SqliteBackend.available():
		var path := DIR + "/suite.db"
		_rm_db(path)
		_suite(SqliteBackend.new(), "sqlite", path)
		_sqlite_reload(path)
		_meta_bans_nominal(SqliteBackend.new(), DIR + "/extras.db")
		_sqlite_migrations()
		await _sqlite_crash()
	else:
		print("SKIP: godot-sqlite not installed (tools/fetch_godot_sqlite.sh): SQLite checks skipped")
	print("== %d checks, %s" % [_checks, "FAILED" if _failed else "ALL PASSED"])
	tree.quit(1 if _failed else 0)


func _rm_db(path: String) -> void:
	for suffix in ["", "-wal", "-shm", ".json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _factory_rules() -> void:
	var r := BackendFactory.create("", DIR + "/legacy.json")
	check((r[0] as PersistenceBackend).kind() == "file" and str(r[2]).ends_with(".json"), "factory: no backend key + .json save_path -> FileBackend (M2 configs unchanged)")
	r = BackendFactory.create("memory", "")
	check((r[0] as PersistenceBackend).kind() == "memory", "factory: backend=memory")
	r = BackendFactory.create("file", DIR + "/f.json")
	check((r[0] as PersistenceBackend).kind() == "file", "factory: backend=file")
	_rm_db(DIR + "/auto.db")
	r = BackendFactory.create("sqlite", DIR + "/auto.json")
	var want := "sqlite" if SqliteBackend.available() else "file"
	check((r[0] as PersistenceBackend).kind() == want, "factory: backend=sqlite -> %s (%s)" % [want, r[2]])
	(r[0] as PersistenceBackend).close()


## world_meta stamping, bans and nominal counters (every backend).
func _meta_bans_nominal(b: PersistenceBackend, path: String) -> void:
	var tag := b.kind()
	_rm_db(path)
	check(b.open(path) == OK, "[%s] open %s" % [tag, path])
	b.save_world_meta({"day": 5, "hour": 7.5})
	b.save_world_meta({"weather": "blizzard"})
	var m := b.load_world_meta()
	check(int(m.get("day", 0)) == 5 and str(m.get("weather", "")) == "blizzard", "[%s] world_meta merges (day %s, weather %s)" % [tag, m.get("day"), m.get("weather")])
	check(int(m.get(PersistenceSchema.META_WORLD_VERSION, -1)) == PersistenceSchema.world_version() and m.has(PersistenceSchema.META_CITY_VERSION)
		and int(m.get(PersistenceSchema.META_SCHEMA, -1)) == PersistenceSchema.VERSION,
		"[%s] world_meta stamped: world_version=%s city_version=%s schema=%s" % [tag, m.get("world_version"), m.get("city_version"), m.get("schema_version")])
	b.save_ban("abc123", "10.0.0.7", "tramposo")
	b.save_ban("ip:10.0.0.9", "10.0.0.9", "spam")
	var bans := b.load_bans()
	check(bans.size() == 2 and str((bans["abc123"] as Dictionary).get("reason", "")) == "tramposo", "[%s] bans stored (%d)" % [tag, bans.size()])
	check(b.remove_ban("abc123") and not b.remove_ban("nobody") and b.load_bans().size() == 1, "[%s] unban" % tag)
	b.save_nominal({"VALDENIEVE|ammo": 12, "CLARO DEL CAZADOR|weapon": 1})
	b.save_nominal({"VALDENIEVE|ammo": 14})
	var n := b.load_nominal()
	check(int(n.get("VALDENIEVE|ammo", 0)) == 14 and int(n.get("CLARO DEL CAZADOR|weapon", 0)) == 1, "[%s] loot nominal counters (%s)" % [tag, n])
	check(b.flush() == OK, "[%s] flush" % tag)
	b.close()
	# reopen: everything came back from the medium
	var b2: PersistenceBackend = MemoryBackend.new() if tag == "memory" else (FileBackend.new() if tag == "file" else SqliteBackend.new())
	if tag != "memory":
		b2.open(path)
		check(int(b2.load_world_meta().get("day", 0)) == 5 and b2.load_bans().size() == 1 and int(b2.load_nominal().get("VALDENIEVE|ammo", 0)) == 14,
			"[%s] meta / bans / nominal survive the reload" % tag)
		b2.close()


## FileBackend: the M2 document (no schema_version) is migrated; a newer document is refused.
func _file_migrations() -> void:
	var p := DIR + "/m2_doc.json"
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": "0.6.0-m4", "world": {"day": 4, "hour": 10.0}, "players": {"t": {"name": "Eva"}},
		"chunks": {str(WorldConst.key(24, 24)): {"cx": 24, "cz": 24, "objects": {"77": {"felled": true}}}}, "hordes": [], "events": []}))
	f.close()
	var fb := FileBackend.new()
	check(fb.open(p) == OK and fb.loaded_schema() == 0, "[file] M2 document (no schema_version) opens")
	var m := fb.load_world_meta()
	check(int(m.get("world_version", -1)) == PersistenceSchema.world_version() and m.has("city_version") and int(m.get("day", 0)) == 4,
		"[file] migrations 1..%d applied to the document (world_version %s, city_version %s)" % [PersistenceSchema.VERSION, m.get("world_version"), m.get("city_version")])
	var d := fb.load_chunk_delta(24, 24)
	check(d != null and bool(d.objects.get(77, {}).get("felled", false)) and fb.player_count() == 1, "[file] migrated document keeps chunks and players")
	fb.flush()
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	check(doc is Dictionary and int((doc as Dictionary).get("schema_version", 0)) == PersistenceSchema.VERSION, "[file] schema_version %d written back" % PersistenceSchema.VERSION)
	(doc as Dictionary)["schema_version"] = PersistenceSchema.VERSION + 7
	f = FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	check(FileBackend.new().open(p) == ERR_FILE_UNRECOGNIZED, "[file] a document from a newer server is refused (never downgraded)")


func _sqlite_reload(path: String) -> void:
	var b := SqliteBackend.new()
	check(b.open(path) == OK and b.loaded_schema == PersistenceSchema.VERSION, "[sqlite] reopen (schema %d, no migration)" % b.loaded_schema)
	check(b.journal_mode() == "wal" and b.integrity == "ok" and b.user_version() == PersistenceSchema.VERSION,
		"[sqlite] journal_mode=%s, quick_check=%s, user_version=%d" % [b.journal_mode(), b.integrity, b.user_version()])
	check(b.player_count() == 2 and b.load_player("tok_a").get("name", "") == "Ana" and (b.load_player("tok_a").get("slots", []) as Array).size() == 2,
		"[sqlite] players survive the reload (profile_json)")
	check(int(b.load_world_meta().get("day", 0)) == 3 and int(b.load_world_meta().get("world_version", -1)) == PersistenceSchema.world_version(),
		"[sqlite] world meta survives the reload, world_version=%s" % b.load_world_meta().get("world_version"))
	var d := b.load_chunk_delta(24, 24)
	check(d != null and int(d.objects.get(101, {}).get("hits", 0)) == 3 and bool(d.objects.get(101, {}).get("felled", false))
		and str(d.structures.get(202, {}).get("kind", "")) == "campfire" and d.containers.has(150) and d.drops.has(304),
		"[sqlite] chunk delta rows survive the reload (objects, containers, structures, drops; int wids)")
	check(b.chunk_keys() == [WorldConst.key(24, 24), WorldConst.key(25, 23)], "[sqlite] chunk keys via WorldConst.key (%s)" % str(b.chunk_keys()))
	check(b.load_hordes().size() == 1 and b.events().size() == 2, "[sqlite] hordes and events survive the reload")
	# far chunks of the 96² grid (SE quadrant, W1) and 63-bit wids
	var far := ChunkDelta.make(WorldConst.chunk_of(3500.0), WorldConst.chunk_of(3600.0))
	far.merge(&"objects", 0x7FFFFFFFFFFFFF01, {"felled": true})
	b.save_chunk_delta(far)
	var back := b.load_chunk_delta(far.cx, far.cz)
	check(back != null and back.objects.has(0x7FFFFFFFFFFFFF01) and b.chunk_keys().has(WorldConst.key(far.cx, far.cz)),
		"[sqlite] SE-quadrant chunk (%d, %d) key %d and a 63-bit wid round-trip" % [far.cx, far.cz, WorldConst.key(far.cx, far.cz)])
	# VACUUM INTO backup: a consistent copy that opens on its own
	var bak := DIR + "/backups/world-test.db"
	check(b.backup(bak) == OK and FileAccess.file_exists(bak), "[sqlite] VACUUM INTO backup written")
	b.close()
	var bb := SqliteBackend.new()
	check(bb.open(bak) == OK and bb.player_count() == 2 and bb.chunk_keys().size() == 3, "[sqlite] the backup opens with every row")
	bb.close()
	_rm_db(bak)


## A v1 file (the §15.2 tables only) is upgraded to the current schema; a file from a newer server is refused.
func _sqlite_migrations() -> void:
	var p := DIR + "/v1.db"
	_rm_db(p)
	var raw: Object = ClassDB.instantiate(&"SQLite")
	raw.set("path", p)
	raw.set("verbosity_level", 0)
	raw.call("open_db")
	var m1: RefCounted = load("res://scripts/persistence/migrations/001_initial.gd").new()
	for sql in (m1.call("sqlite") as PackedStringArray):
		raw.call("query", sql)
	raw.call("query", "PRAGMA user_version=1;")
	raw.call("query_with_bindings", "INSERT INTO containers(wid, cx, cz, items_json, rolled_day, opened_by, updated, data_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
		[42, 24, 24, "[]", 1, "", 0, JSON.stringify({"items": [{"id": "vendas", "count": 2}], "rolled_day": 1})])
	raw.call("query", "INSERT INTO chunks(cx, cz, first_visit, last_visit) VALUES (24, 24, 0, 0);")
	raw.call("close_db")
	var b := SqliteBackend.new()
	check(b.open(p) == OK and b.loaded_schema == 1 and b.user_version() == PersistenceSchema.VERSION, "[sqlite] v1 file migrated to schema %d" % b.user_version())
	var cols := []
	for row in b._select("PRAGMA table_info(containers);"):
		cols.append(str(row["name"]))
	check(cols.has("table_id") and cols.has("bags_json") and not b._select("SELECT name FROM sqlite_master WHERE name = 'nominal';").is_empty(),
		"[sqlite] migration 2 added containers.table_id / bags_json and the nominal table")
	var d := b.load_chunk_delta(24, 24)
	check(d != null and d.containers.has(42) and int(b.load_world_meta().get("world_version", -1)) == PersistenceSchema.world_version(),
		"[sqlite] v1 rows kept; world_meta.world_version = %s after the migration" % b.load_world_meta().get("world_version"))
	b._exec("PRAGMA user_version=%d;" % (PersistenceSchema.VERSION + 5))
	b.close()
	var b2 := SqliteBackend.new()
	check(b2.open(p) == ERR_FILE_UNRECOGNIZED, "[sqlite] a file from a newer server is refused (never downgraded)")
	_rm_db(p)


## Crash safety: a child process commits batch A, opens batch B, and is killed before B commits.
func _sqlite_crash() -> void:
	var p := DIR + "/crash.db"
	_rm_db(p)
	var marker := ProjectSettings.globalize_path(DIR + "/crash.marker")
	DirAccess.remove_absolute(marker)
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tests/unit/crash_writer.gd",
		"++", ProjectSettings.globalize_path(p), marker])
	var pid := OS.create_process(OS.get_executable_path(), args)
	var waited := 0.0
	while waited < 30.0 and not FileAccess.file_exists(marker):
		await tree.create_timer(0.1).timeout
		waited += 0.1
	var ready := FileAccess.file_exists(marker)
	OS.kill(pid)
	await tree.create_timer(0.3).timeout
	check(ready, "[sqlite] crash writer committed batch A and opened batch B (%.1f s)" % waited)
	var b := SqliteBackend.new()
	var err := b.open(p)
	check(err == OK and b.integrity == "ok", "[sqlite] after the kill the file opens, quick_check = %s" % b.integrity)
	check(b.load_player("committed").get("name", "") == "A" and b.load_player("uncommitted").is_empty() and b.load_chunk_delta(30, 30) == null,
		"[sqlite] the committed autosave survived the crash, the half-written batch was rolled back")
	b.close()
	_rm_db(p)
	DirAccess.remove_absolute(marker)
