class_name PersistenceBackend
extends RefCounted
## Storage interface of the dedicated server (ARQ v2 §15.1). M2 ships MemoryBackend (tests, offline) and
## FileBackend (one JSON document, atomic write); SqliteBackend arrives in M5 with the same calls. Everything is
## keyed the way the SQLite schema is: world_meta, players by token hash, chunk deltas by (cx, cz), hordes, events.


func open(_path: String) -> Error:
	return OK


func close() -> void:
	pass


## Writes everything pending to the medium (no-op for memory).
func flush() -> Error:
	return OK


func load_world_meta() -> Dictionary:
	return {}


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


## Saves only the dirty tables of `delta` (merged over what is stored) and clears its dirty flags.
func save_chunk_delta(_delta: ChunkDelta) -> void:
	pass


## Keys (WorldConst.key) of every stored chunk delta.
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


func backup(_path: String) -> Error:
	return ERR_UNAVAILABLE
