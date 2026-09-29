extends RefCounted
## Migration 1: the tables of ARQ v2 §15.2. Each table also keeps the whole game entry in `data_json`
## (`profile_json` for players, `population_json` for chunks): the typed columns are indexes and admin views, the
## JSON is what the game reads back, so a new field never needs a migration. `corpses`, `vehicles`, `bases` and
## `blueprints` are created for parity with the plan (M5 stores corpses as `structures` of kind "corpse" plus their
## `containers` row; vehicles, bases and blueprints arrive in M7/M8).

const VERSION := 1


func sqlite() -> PackedStringArray:
	return PackedStringArray([
		"CREATE TABLE IF NOT EXISTS world_meta(key TEXT PRIMARY KEY, value TEXT);",
		"CREATE TABLE IF NOT EXISTS players(token_hash TEXT PRIMARY KEY, name TEXT, x REAL, y REAL, z REAL, yaw REAL, hp REAL, warmth REAL, hunger REAL, stamina REAL, fever REAL, max_hp REAL, inventory_json TEXT, equipment_json TEXT, skills_json TEXT, objectives_json TEXT, flags_json TEXT, faction TEXT, downs INT, last_seen INT, created INT, profile_json TEXT);",
		"CREATE TABLE IF NOT EXISTS chunks(cx INT, cz INT, first_visit INT, last_visit INT, pop_alive INT, pop_killed INT, cleared_until INT, population_json TEXT, PRIMARY KEY(cx, cz));",
		"CREATE TABLE IF NOT EXISTS world_objects(wid INT PRIMARY KEY, cx INT, cz INT, kind TEXT, state INT, hp REAL, data_json TEXT, updated INT);",
		"CREATE TABLE IF NOT EXISTS containers(wid INT PRIMARY KEY, cx INT, cz INT, items_json TEXT, rolled_day INT, opened_by TEXT, updated INT, data_json TEXT);",
		"CREATE TABLE IF NOT EXISTS structures(wid INT PRIMARY KEY, cx INT, cz INT, kind TEXT, x REAL, y REAL, z REAL, yaw REAL, owner TEXT, faction TEXT, hp REAL, data_json TEXT, updated INT);",
		"CREATE TABLE IF NOT EXISTS vehicles(wid INT PRIMARY KEY, cx INT, cz INT, model TEXT, transform_json TEXT, fuel REAL, battery REAL, parts_json TEXT, inventory_json TEXT, keys_json TEXT, locked INT, updated INT);",
		"CREATE TABLE IF NOT EXISTS drops(wid INT PRIMARY KEY, cx INT, cz INT, item TEXT, count INT, x REAL, y REAL, z REAL, expires INT, data_json TEXT);",
		"CREATE TABLE IF NOT EXISTS corpses(wid INT PRIMARY KEY, cx INT, cz INT, owner TEXT, x REAL, y REAL, z REAL, inventory_json TEXT, expires INT);",
		"CREATE TABLE IF NOT EXISTS hordes(id INT PRIMARY KEY, kind TEXT, count INT, x REAL, z REAL, target_x REAL, target_z REAL, state TEXT, data_json TEXT);",
		"CREATE TABLE IF NOT EXISTS bases(id INTEGER PRIMARY KEY, building_wid INT, faction TEXT, tier INT, slots_json TEXT, heat REAL, updated INT);",
		"CREATE TABLE IF NOT EXISTS blueprints(id TEXT PRIMARY KEY, unlocked_by TEXT, day INT);",
		"CREATE TABLE IF NOT EXISTS bans(token_hash TEXT PRIMARY KEY, ip TEXT, reason TEXT, ts INT);",
		"CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INT, type TEXT, data_json TEXT);",
		"CREATE INDEX IF NOT EXISTS idx_objects_chunk ON world_objects(cx, cz);",
		"CREATE INDEX IF NOT EXISTS idx_containers_chunk ON containers(cx, cz);",
		"CREATE INDEX IF NOT EXISTS idx_structures_chunk ON structures(cx, cz);",
		"CREATE INDEX IF NOT EXISTS idx_vehicles_chunk ON vehicles(cx, cz);",
		"CREATE INDEX IF NOT EXISTS idx_drops_chunk ON drops(cx, cz);",
		"CREATE INDEX IF NOT EXISTS idx_corpses_chunk ON corpses(cx, cz);",
	])


## The M2 JSON document (world, players, chunks, hordes, events; or the M1 players + clock) → version 1.
func document(doc: Dictionary) -> void:
	for k in ["world", "players", "chunks", "bans"]:
		if not doc.get(k) is Dictionary:
			doc[k] = {}
	for k in ["hordes", "events"]:
		if not doc.get(k) is Array:
			doc[k] = []
