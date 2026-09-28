class_name SqliteBackend
extends PersistenceBackend
## Production persistence of the dedicated server (ARQ v2 §15, PLAN C12, M5): godot-sqlite (MIT GDExtension,
## addons/godot-sqlite, fetched by tools/fetch_godot_sqlite.sh at a pinned version + SHA-256) with
## `journal_mode=WAL`, `synchronous=NORMAL` and `user_version` = PersistenceSchema.VERSION (numbered migrations in
## scripts/persistence/migrations/). Only deltas over the seeded world are stored (C12): world_meta, players, one
## row per changed object / container / structure / drop of a chunk (+ the chunk's population), hordes, events, bans.
## Chunks are addressed with WorldConst.key(cx, cz) / key_cx / key_cz (96² grid, W1); rows keep cx, cz columns.
## Crash safety: the autosave writes everything in ONE transaction (begin_batch → flush = COMMIT); a crash before
## the commit rolls back to the previous autosave on the next open (WAL), never a half-written world.
## The SQLite class exists only when the GDExtension loaded, so this script never names it: `db` is untyped and
## created through ClassDB (the script parses and the web build runs without the addon; BackendFactory falls back
## to FileBackend).

const EVENTS_KEEP := 5000

var path: String = ""
var db: Object = null
var _in_batch: bool = false
var _events_since_prune: int = 0
## Schema version found on disk before the migrations ran (0 = new file). Tests read it.
var loaded_schema: int = 0
## `PRAGMA quick_check` answer at open ("ok" when the file is sound).
var integrity: String = ""


static func available() -> bool:
	return ClassDB.class_exists(&"SQLite")


func kind() -> String:
	return "sqlite"


func open(p_path: String) -> Error:
	if not available():
		last_error = "godot-sqlite GDExtension not loaded (addons/godot-sqlite)"
		return ERR_UNAVAILABLE
	path = p_path
	var dir := path.get_base_dir()
	if dir != "" and not dir.ends_with(":/") and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	db = ClassDB.instantiate(&"SQLite")
	db.set("path", path)
	db.set("verbosity_level", 0)
	if not bool(db.call("open_db")):
		last_error = "cannot open %s (%s)" % [path, str(db.get("error_message"))]
		db = null
		return ERR_CANT_OPEN
	_exec("PRAGMA journal_mode=WAL;")
	_exec("PRAGMA synchronous=NORMAL;")
	_exec("PRAGMA busy_timeout=3000;")
	var qc := _select("PRAGMA quick_check;")
	integrity = str((qc[0] as Dictionary).values()[0]) if not qc.is_empty() else "?"
	if integrity != "ok":
		push_warning("SqliteBackend: %s quick_check = %s" % [path, integrity])
	loaded_schema = user_version()
	if loaded_schema > PersistenceSchema.VERSION:
		last_error = "%s has schema %d, newer than this server (%d)" % [path, loaded_schema, PersistenceSchema.VERSION]
		close()
		return ERR_FILE_UNRECOGNIZED
	for m in PersistenceSchema.migrations_after(loaded_schema):
		var v := int(m.get("VERSION"))
		_exec("BEGIN IMMEDIATE;")
		var ok := true
		for sql in (m.call("sqlite") as PackedStringArray):
			if not _exec(sql):
				ok = false
				break
		if ok:
			ok = _exec("PRAGMA user_version=%d;" % v)
		if not ok:
			_exec("ROLLBACK;")
			last_error = "migration %d failed: %s" % [v, str(db.get("error_message"))]
			push_warning("SqliteBackend: " + last_error)
			close()
			return ERR_DATABASE_CANT_WRITE
		_exec("COMMIT;")
		print("[EVT] persistence: %s migrated to schema %d" % [path, v])
	return OK


func is_open() -> bool:
	return db != null


func user_version() -> int:
	var r := _select("PRAGMA user_version;")
	return int((r[0] as Dictionary).get("user_version", 0)) if not r.is_empty() else 0


func schema_version() -> int:
	return user_version() if db != null else 0


func journal_mode() -> String:
	var r := _select("PRAGMA journal_mode;")
	return str((r[0] as Dictionary).get("journal_mode", "")) if not r.is_empty() else ""


func close() -> void:
	if db == null:
		return
	flush()
	_exec("PRAGMA wal_checkpoint(TRUNCATE);")   # a clean shutdown leaves one self-contained .db file
	db.call("close_db")
	db = null


# ------------------------------------------------------------------ low level
func _exec(sql: String) -> bool:
	if db == null:
		return false
	if not bool(db.call("query", sql)):
		last_error = "%s -> %s" % [sql.substr(0, 80), str(db.get("error_message"))]
		push_warning("SqliteBackend: " + last_error)
		return false
	return true


func _run(sql: String, binds: Array) -> bool:
	if db == null:
		return false
	if not bool(db.call("query_with_bindings", sql, binds)):
		last_error = "%s -> %s" % [sql.substr(0, 80), str(db.get("error_message"))]
		push_warning("SqliteBackend: " + last_error)
		return false
	return true


func _select(sql: String, binds: Array = []) -> Array:
	if db == null:
		return []
	var ok: bool = bool(db.call("query_with_bindings", sql, binds)) if not binds.is_empty() else bool(db.call("query", sql))
	if not ok:
		last_error = "%s -> %s" % [sql.substr(0, 80), str(db.get("error_message"))]
		push_warning("SqliteBackend: " + last_error)
		return []
	var r: Variant = db.get("query_result")
	return (r as Array).duplicate() if r is Array else []


## Runs `body` inside a transaction unless a batch is already open (then it joins the batch).
func _tx(body: Callable) -> void:
	if db == null:
		return
	if _in_batch:
		body.call()
		return
	_exec("BEGIN IMMEDIATE;")
	body.call()
	_exec("COMMIT;")


static func _json(v: Variant) -> String:
	return JSON.stringify(v)


static func _parse(s: Variant) -> Variant:
	if s == null or str(s) == "":
		return null
	var v: Variant = JSON.parse_string(str(s))
	return v


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


# ------------------------------------------------------------------ batches
func begin_batch() -> void:
	if db == null or _in_batch:
		return
	if _exec("BEGIN IMMEDIATE;"):
		_in_batch = true


func flush() -> Error:
	if db == null:
		return ERR_UNCONFIGURED
	if _in_batch:
		_in_batch = false
		if not _exec("COMMIT;"):
			return ERR_DATABASE_CANT_WRITE
	return OK


# ------------------------------------------------------------------ world meta
func load_world_meta() -> Dictionary:
	var out := {}
	for row in _select("SELECT key, value FROM world_meta;"):
		var v: Variant = _parse(row["value"])
		out[str(row["key"])] = v if v != null else str(row["value"])
	return out


func save_world_meta(d: Dictionary) -> void:
	var meta := PersistenceSchema.stamp_meta(d)
	_tx(func() -> void:
		for k in meta:
			_run("INSERT INTO world_meta(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;",
				[str(k), _json(meta[k])]))


# ------------------------------------------------------------------ players
func load_player(token_hash: String) -> Dictionary:
	var r := _select("SELECT profile_json FROM players WHERE token_hash = ?;", [token_hash])
	if r.is_empty():
		return {}
	var v: Variant = _parse(r[0]["profile_json"])
	return v if v is Dictionary else {}


func save_player(token_hash: String, d: Dictionary) -> void:
	if token_hash == "" or db == null:
		return
	var now := _now()
	_tx(func() -> void:
		_run("""INSERT INTO players(token_hash, name, x, y, z, yaw, hp, warmth, hunger, stamina, inventory_json, objectives_json,
			flags_json, downs, last_seen, created, profile_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
			ON CONFLICT(token_hash) DO UPDATE SET name = excluded.name, x = excluded.x, y = excluded.y, z = excluded.z,
			yaw = excluded.yaw, hp = excluded.hp, warmth = excluded.warmth, hunger = excluded.hunger, stamina = excluded.stamina,
			inventory_json = excluded.inventory_json, objectives_json = excluded.objectives_json, flags_json = excluded.flags_json,
			downs = excluded.downs, last_seen = excluded.last_seen, profile_json = excluded.profile_json;""",
			[token_hash, str(d.get("name", "")), float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)),
			float(d.get("yaw", 0.0)), float(d.get("health", 100.0)), float(d.get("warmth", 0.0)), float(d.get("hunger", 0.0)),
			float(d.get("stamina", 100.0)), _json(d.get("slots", [])), _json(d.get("quest", {})),
			_json({"dead": d.get("dead", false), "cause": d.get("cause", ""), "outfit": d.get("outfit", 0)}),
			int(d.get("downs", 0)), now, now, _json(d)]))


func player_count() -> int:
	var r := _select("SELECT COUNT(*) AS n FROM players;")
	return int(r[0]["n"]) if not r.is_empty() else 0


# ------------------------------------------------------------------ chunk deltas
func load_chunk_delta(cx: int, cz: int) -> ChunkDelta:
	var c := _select("SELECT population_json FROM chunks WHERE cx = ? AND cz = ?;", [cx, cz])
	if c.is_empty():
		return null
	var d := {"cx": cx, "cz": cz}
	var pop: Variant = _parse(c[0]["population_json"])
	d["population"] = pop if pop is Dictionary else {}
	for t in [["objects", "world_objects"], ["containers", "containers"], ["structures", "structures"], ["drops", "drops"]]:
		var table := {}
		for row in _select("SELECT wid, data_json FROM %s WHERE cx = ? AND cz = ?;" % t[1], [cx, cz]):
			var e: Variant = _parse(row["data_json"])
			table[int(row["wid"])] = e if e is Dictionary else {}
		d[t[0]] = table
	return ChunkDelta.from_dict(d)


func save_chunk_delta(delta: ChunkDelta) -> void:
	if delta == null or not delta.is_dirty() or db == null:
		return
	var cx := WorldConst.key_cx(delta.key())
	var cz := WorldConst.key_cz(delta.key())
	var now := _now()
	_tx(func() -> void:
		_run("INSERT INTO chunks(cx, cz, first_visit, last_visit) VALUES (?, ?, ?, ?) ON CONFLICT(cx, cz) DO UPDATE SET last_visit = excluded.last_visit;",
			[cx, cz, now, now])
		if delta.dirty.get(&"population", false):
			var p := delta.population
			_run("UPDATE chunks SET pop_alive = ?, pop_killed = ?, cleared_until = ?, population_json = ? WHERE cx = ? AND cz = ?;",
				[int(p.get("alive", 0)), int(p.get("killed", 0)), int(p.get("cleared_until", 0)), _json(p), cx, cz])
		if delta.dirty.get(&"objects", false):
			_run("DELETE FROM world_objects WHERE cx = ? AND cz = ?;", [cx, cz])
			for wid in delta.objects:
				var e: Dictionary = delta.objects[wid]
				_run("INSERT OR REPLACE INTO world_objects(wid, cx, cz, kind, state, hp, data_json, updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
					[int(wid), cx, cz, str(e.get("kind", "")), 1 if bool(e.get("felled", false)) or bool(e.get("removed", false)) else 0,
					float(e.get("hp", 0.0)), _json(e), now])
		if delta.dirty.get(&"containers", false):
			_run("DELETE FROM containers WHERE cx = ? AND cz = ?;", [cx, cz])
			for wid in delta.containers:
				var e: Dictionary = delta.containers[wid]
				_run("INSERT OR REPLACE INTO containers(wid, cx, cz, items_json, rolled_day, opened_by, updated, data_json, table_id, bags_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
					[int(wid), cx, cz, _json(e.get("items", [])), int(e.get("rolled_day", -1)), str(e.get("opened_by", "")), now, _json(e),
					str(e.get("table", "")), _json(e.get("bags", {}))])
		if delta.dirty.get(&"structures", false):
			_run("DELETE FROM structures WHERE cx = ? AND cz = ?;", [cx, cz])
			for wid in delta.structures:
				var e: Dictionary = delta.structures[wid]
				_run("INSERT OR REPLACE INTO structures(wid, cx, cz, kind, x, y, z, yaw, owner, faction, hp, data_json, updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
					[int(wid), cx, cz, str(e.get("kind", "")), float(e.get("x", 0.0)), float(e.get("y", 0.0)), float(e.get("z", 0.0)),
					float(e.get("yaw", 0.0)), str(e.get("owner", "")), str(e.get("faction", "")), float(e.get("hp", 0.0)), _json(e), now])
		if delta.dirty.get(&"drops", false):
			_run("DELETE FROM drops WHERE cx = ? AND cz = ?;", [cx, cz])
			for wid in delta.drops:
				var e: Dictionary = delta.drops[wid]
				_run("INSERT OR REPLACE INTO drops(wid, cx, cz, item, count, x, y, z, expires, data_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
					[int(wid), cx, cz, str(e.get("item", "")), int(e.get("amount", 1)), float(e.get("x", 0.0)), float(e.get("y", 0.0)),
					float(e.get("z", 0.0)), int(e.get("expires", 0)), _json(e)]))
	delta.clear_dirty()


func chunk_keys() -> Array[int]:
	var out: Array[int] = []
	for row in _select("SELECT cx, cz FROM chunks;"):
		out.append(WorldConst.key(int(row["cx"]), int(row["cz"])))
	out.sort()
	return out


# ------------------------------------------------------------------ hordes, events, bans, nominal
func load_hordes() -> Array:
	var out: Array = []
	for row in _select("SELECT data_json FROM hordes ORDER BY id;"):
		var v: Variant = _parse(row["data_json"])
		if v is Dictionary:
			out.append(v)
	return out


func save_hordes(a: Array) -> void:
	_tx(func() -> void:
		_exec("DELETE FROM hordes;")
		var i := 0
		for h in a:
			var e: Dictionary = h
			i += 1
			_run("INSERT INTO hordes(id, kind, count, x, z, target_x, target_z, state, data_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
				[int(e.get("id", i)), str(e.get("kind", "")), int(e.get("count", 0)), float(e.get("x", 0.0)), float(e.get("z", 0.0)),
				float(e.get("target_x", 0.0)), float(e.get("target_z", 0.0)), str(e.get("state", "")), _json(e)]))


func log_event(type: String, data: Dictionary) -> void:
	if db == null:
		return
	_tx(func() -> void:
		_run("INSERT INTO events(ts, type, data_json) VALUES (?, ?, ?);", [_now(), type, _json(data)])
		_events_since_prune += 1
		if _events_since_prune >= 200:
			_events_since_prune = 0
			_exec("DELETE FROM events WHERE id <= (SELECT MAX(id) FROM events) - %d;" % EVENTS_KEEP))


func events() -> Array:
	var out: Array = []
	var rows := _select("SELECT ts, type, data_json FROM events ORDER BY id DESC LIMIT 500;")
	rows.reverse()
	for row in rows:
		var v: Variant = _parse(row["data_json"])
		out.append({"ts": int(row["ts"]), "type": str(row["type"]), "data": v if v is Dictionary else {}})
	return out


func load_bans() -> Dictionary:
	var out := {}
	for row in _select("SELECT token_hash, ip, reason, ts FROM bans;"):
		out[str(row["token_hash"])] = {"ip": str(row["ip"]), "reason": str(row["reason"]), "ts": int(row["ts"])}
	return out


func save_ban(key: String, ip: String, reason: String) -> void:
	if key == "":
		return
	_tx(func() -> void:
		_run("INSERT OR REPLACE INTO bans(token_hash, ip, reason, ts) VALUES (?, ?, ?, ?);", [key, ip, reason, _now()]))


func remove_ban(key: String) -> bool:
	var had := not _select("SELECT 1 AS x FROM bans WHERE token_hash = ?;", [key]).is_empty()
	if had:
		_tx(func() -> void: _run("DELETE FROM bans WHERE token_hash = ?;", [key]))
	return had


## Loot nominal counters (GDD §9.3): "region|category" -> spawned.
func load_nominal() -> Dictionary:
	var out := {}
	for row in _select("SELECT region, category, spawned FROM nominal;"):
		out["%s|%s" % [row["region"], row["category"]]] = int(row["spawned"])
	return out


func save_nominal(d: Dictionary) -> void:
	_tx(func() -> void:
		for k in d:
			var parts := str(k).split("|")
			if parts.size() == 2:
				_run("INSERT OR REPLACE INTO nominal(region, category, spawned) VALUES (?, ?, ?);", [parts[0], parts[1], int(d[k])]))


# ------------------------------------------------------------------ zone discovery (H2, schema 3)
func load_discoveries() -> Dictionary:
	var out := {}
	for row in _select("SELECT scope, zone_id, by_token, by_name, day, ts FROM discoveries;"):
		var scope := str(row["scope"])
		if not out.has(scope):
			out[scope] = {}
		(out[scope] as Dictionary)[str(row["zone_id"])] = {"by": str(row["by_name"]), "token": str(row["by_token"]),
			"day": int(row["day"]), "ts": int(row["ts"])}
	return out


func save_discovery(scope: String, zone_id: String, rec: Dictionary) -> void:
	if db == null or scope == "" or zone_id == "":
		return
	_tx(func() -> void:
		_run("INSERT OR IGNORE INTO discoveries(scope, zone_id, by_token, by_name, day, ts) VALUES (?, ?, ?, ?, ?, ?);",
			[scope, zone_id, str(rec.get("token", "")), str(rec.get("by", "")), int(rec.get("day", 0)), int(rec.get("ts", _now()))]))


# ------------------------------------------------------------------ backup
## `VACUUM INTO` a consistent copy (works while the server runs; the target must not exist).
func backup(to_path: String) -> Error:
	if db == null:
		return ERR_UNCONFIGURED
	var abs_path := ProjectSettings.globalize_path(to_path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)
	var dir := abs_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if _in_batch:
		flush()
	return OK if _exec("VACUUM INTO '%s';" % abs_path.replace("'", "''")) else ERR_CANT_CREATE
