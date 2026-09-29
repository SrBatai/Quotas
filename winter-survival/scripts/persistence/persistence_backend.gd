class_name PersistenceBackend
extends RefCounted
## Storage interface of the dedicated server (ARQ v2 §15.1). Backends: SqliteBackend (production, M5: godot-sqlite,
## WAL), FileBackend (one JSON document, atomic write: the fallback when the GDExtension is missing, e.g. the web
## build or an unsupported platform) and MemoryBackend (tests, offline). BackendFactory picks one from server.cfg.
## Everything is keyed the way the SQLite schema is: world_meta, players by token hash, chunk deltas by (cx, cz)
## (WorldConst.key), hordes, events, bans. Schema versions and migrations: PersistenceSchema.
## Batches: `begin_batch()` opens one transaction (SQLite) that `flush()` commits: the autosave writes every dirty
## chunk + the connected profiles + world_meta atomically. Calls outside a batch commit on their own.

## Human-readable reason of the last failure ("" = none).
var last_error: String = ""


func kind() -> String:
	return "none"


func open(_path: String) -> Error:
	return OK


func close() -> void:
	pass


## Schema version of the open store (PersistenceSchema.VERSION after open() migrated it).
func schema_version() -> int:
	return PersistenceSchema.VERSION


## Starts a batch of writes that `flush()` makes durable at once (no-op where writes are already atomic).
func begin_batch() -> void:
	pass


## Writes everything pending to the medium (commit / atomic file write; no-op for memory).
func flush() -> Error:
	return OK


func load_world_meta() -> Dictionary:
	return {}


## Merges `d` into the stored world_meta (keys not in `d` are kept) and stamps world_version / city_version.
func save_world_meta(_d: Dictionary) -> void:
	pass


func load_player(_token_hash: String) -> Dictionary:
	return {}


func save_player(_token_hash: String, _d: Dictionary) -> void:
	pass


func player_count() -> int:
	return 0


func load_chunk_delta(_cx: int, _cz: int) -> ChunkDelta:
	return null


## Saves only the dirty tables of `delta` (a dirty table replaces the stored one) and clears its dirty flags.
func save_chunk_delta(_delta: ChunkDelta) -> void:
	pass


## Keys (WorldConst.key) of every stored chunk delta, sorted.
func chunk_keys() -> Array[int]:
	return []


func load_hordes() -> Array:
	return []


func save_hordes(_a: Array) -> void:
	pass


func log_event(_type: String, _data: Dictionary) -> void:
	pass


func events() -> Array:
	return []


## Bans (ARQ v2 §16.5): token_hash (or "ip:<address>") -> {ip, reason, ts}.
func load_bans() -> Dictionary:
	return {}


func save_ban(_key: String, _ip: String, _reason: String) -> void:
	pass


func remove_ban(_key: String) -> bool:
	return false


## Loot nominal counters (GDD §9.3, C22): "region|category" -> items spawned so far.
func load_nominal() -> Dictionary:
	return {}


func save_nominal(_d: Dictionary) -> void:
	pass


## Zone discoveries (H2, schema 3): scope ("group" with `shared_discovery`, else a token hash) -> {zone_id -> {by,
## token, day, ts}}.
func load_discoveries() -> Dictionary:
	return {}


## Stores one discovery (the first one of a zone in a scope wins; later calls for it change nothing).
func save_discovery(_scope: String, _zone_id: String, _rec: Dictionary) -> void:
	pass


func backup(_path: String) -> Error:
	return ERR_UNAVAILABLE
