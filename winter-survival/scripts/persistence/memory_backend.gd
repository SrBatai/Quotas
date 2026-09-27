class_name MemoryBackend
extends PersistenceBackend
## In-memory persistence (tests, offline play): the same tables as the SQLite schema, held as dictionaries.
## FileBackend extends it and only adds the JSON serialisation and the document migrations.

const MAX_EVENTS := 500

var world_meta: Dictionary = {}
var players: Dictionary = {}        # token_hash -> profile
var chunks: Dictionary = {}         # key -> Dictionary (ChunkDelta.to_dict form, string wids)
var hordes: Array = []
var bans: Dictionary = {}           # token_hash / "ip:<addr>" -> {ip, reason, ts}
var nominal: Dictionary = {}        # "region|category" -> spawned (loot nominal counters, GDD §9.3)
var _events: Array = []


func kind() -> String:
	return "memory"


func load_world_meta() -> Dictionary:
	return world_meta.duplicate(true)


func save_world_meta(d: Dictionary) -> void:
	world_meta.merge(d.duplicate(true), true)
	world_meta = PersistenceSchema.stamp_meta(world_meta)


func load_player(token_hash: String) -> Dictionary:
	return (players.get(token_hash, {}) as Dictionary).duplicate(true)


func save_player(token_hash: String, d: Dictionary) -> void:
	if token_hash == "":
		return
	players[token_hash] = d.duplicate(true)


func player_count() -> int:
	return players.size()


func load_chunk_delta(cx: int, cz: int) -> ChunkDelta:
	var k := WorldConst.key(cx, cz)
	if not chunks.has(k):
		return null
	return ChunkDelta.from_dict(chunks[k])


func save_chunk_delta(delta: ChunkDelta) -> void:
	if delta == null or not delta.is_dirty():
		return
	var k := delta.key()
	var stored: Dictionary = chunks.get(k, {"cx": delta.cx, "cz": delta.cz})
	var part := delta.to_dict(true)
	for t in ChunkDelta.TABLES:
		if part.has(String(t)):
			stored[String(t)] = part[String(t)]   # a dirty table is stored whole (it is the authoritative copy)
	chunks[k] = stored
	delta.clear_dirty()


func chunk_keys() -> Array[int]:
	var out: Array[int] = []
	for k in chunks:
		out.append(int(k))
	out.sort()
	return out


func load_hordes() -> Array:
	return hordes.duplicate(true)


func save_hordes(a: Array) -> void:
	hordes = a.duplicate(true)


func log_event(type: String, data: Dictionary) -> void:
	_events.append({"ts": int(Time.get_unix_time_from_system()), "type": type, "data": data.duplicate(true)})
	while _events.size() > MAX_EVENTS:
		_events.pop_front()


func events() -> Array:
	return _events.duplicate(true)


func load_bans() -> Dictionary:
	return bans.duplicate(true)


func save_ban(key: String, ip: String, reason: String) -> void:
	if key != "":
		bans[key] = {"ip": ip, "reason": reason, "ts": int(Time.get_unix_time_from_system())}


func remove_ban(key: String) -> bool:
	return bans.erase(key)


func load_nominal() -> Dictionary:
	return nominal.duplicate()


func save_nominal(d: Dictionary) -> void:
	nominal.merge(d, true)


## Whole store as one JSON-friendly dictionary (FileBackend writes it; tests compare it).
func to_document() -> Dictionary:
	var ch := {}
	for k in chunks:
		ch[str(k)] = chunks[k]
	return {"version": Net.GAME_VERSION, "schema_version": PersistenceSchema.VERSION, "world": world_meta,
		"players": players, "chunks": ch, "hordes": hordes, "events": _events, "bans": bans, "nominal": nominal}


func from_document(doc: Dictionary) -> void:
	world_meta = doc.get("world", {})
	players = doc.get("players", {})
	chunks.clear()
	var ch: Dictionary = doc.get("chunks", {})
	for k in ch:
		chunks[int(k)] = ch[k]
	hordes = doc.get("hordes", [])
	_events = doc.get("events", [])
	bans = doc.get("bans", {})
	nominal = doc.get("nominal", {})
