class_name BackendFactory
## Picks and opens the persistence backend of a server from server.cfg `[world] backend` + `save_path`
## (ARQ v2 §15.1, §16.2; PLAN R6):
##   sqlite (default)  SqliteBackend on `save_path` (default user://world.db); when the godot-sqlite GDExtension is
##                     not loaded (web, a platform without a binary, the addon not fetched) it falls back to FileBackend
##                     on the same path with `.json`, prints a [EVT] line and keeps going (same schema, same tests).
##   file              FileBackend (one JSON document, atomic writes).
##   memory            MemoryBackend (tests; nothing is written).
## Without a `backend` key, a `.json` save_path keeps the M2 behaviour (file): old configs and tests are unchanged.

const DEFAULT_PATH := "user://world.db"


## Returns [backend, kind_requested, path_used]. The backend is open (or empty after a failed open, never null).
static func create(kind: String, save_path: String) -> Array:
	var k := kind.strip_edges().to_lower()
	var p := save_path if save_path != "" else DEFAULT_PATH
	if k == "":
		k = "file" if p.get_extension() == "json" else "sqlite"
	if k == "memory":
		return [MemoryBackend.new(), k, ""]
	if k == "sqlite":
		var db_path := p if p.get_extension() != "json" else p.get_basename() + ".db"
		if SqliteBackend.available():
			var sb := SqliteBackend.new()
			var err := sb.open(db_path)
			if err == OK:
				return [sb, k, db_path]
			print("[EVT] persistence: SQLite open failed (%s); falling back to the JSON file backend" % sb.last_error)
		else:
			print("[EVT] persistence: godot-sqlite not available (addons/godot-sqlite missing or unsupported platform); using the JSON file backend")
		p = db_path.get_basename() + ".json"
	var fb := FileBackend.new()
	var ferr := fb.open(p)
	if ferr != OK and ferr != ERR_FILE_CORRUPT:
		push_warning("BackendFactory: %s" % fb.last_error)
	return [fb, k, p]


## Copies a JSON store (M2 FileBackend document) into `dst` (a new SQLite store): world_meta, profiles, every chunk
## delta, hordes, bans. Returns the number of chunks copied.
static func import_json(src_path: String, dst: PersistenceBackend) -> int:
	var src := FileBackend.new()
	if src.open(src_path) != OK:
		return 0
	dst.begin_batch()
	dst.save_world_meta(src.world_meta)
	for th in src.players:
		dst.save_player(str(th), src.players[th])
	var n := 0
	for k in src.chunk_keys():
		var d := src.load_chunk_delta(WorldConst.key_cx(k), WorldConst.key_cz(k))
		if d == null:
			continue
		for t in ChunkDelta.TABLES:
			d.dirty[t] = true
		dst.save_chunk_delta(d)
		n += 1
	dst.save_hordes(src.hordes)
	for b in src.bans:
		var e: Dictionary = src.bans[b]
		dst.save_ban(str(b), str(e.get("ip", "")), str(e.get("reason", "")))
	dst.flush()
	return n
