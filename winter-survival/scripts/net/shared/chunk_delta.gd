class_name ChunkDelta
extends RefCounted
## Per-chunk record of everything that differs from the seeded world (ARQ v2 §8.8, M2 in-memory version):
##   objects    wid -> replicated fields of a generated object (tree hits/felled, pickup taken, bush, fire lit/fuel, open_by)
##   containers wid -> {items, open_by}  (server only: contents travel to the opener through NetWorld)
##   structures wid -> {kind, x, y, z, yaw, ...fields}  (placed by players; spawned through the StructureSpawner)
##   drops      wid -> {item, model, x, y, z, amount}   (replicated through the DropSpawner)
##   population {alive, killed, cleared_until, last_visit}  (M4)
## `dirty` marks the tables that changed since the last save; the whole record travels as CHUNK_DELTA to peers
## whose interest includes the chunk (M2: every peer, at join) and is dumped by the persistence backend.

const TABLES: Array[StringName] = [&"objects", &"containers", &"structures", &"drops", &"population"]

var cx: int = 0
var cz: int = 0
var objects: Dictionary = {}
var containers: Dictionary = {}
var structures: Dictionary = {}
var drops: Dictionary = {}
var population: Dictionary = {}
var dirty: Dictionary = {}


static func make(p_cx: int, p_cz: int) -> ChunkDelta:
	var d := ChunkDelta.new()
	d.cx = p_cx
	d.cz = p_cz
	return d


func key() -> int:
	return WorldConst.key(cx, cz)


func is_empty() -> bool:
	return objects.is_empty() and containers.is_empty() and structures.is_empty() and drops.is_empty() and population.is_empty()


func is_dirty() -> bool:
	return not dirty.is_empty()


func clear_dirty() -> void:
	dirty.clear()


func _table(name: StringName) -> Dictionary:
	match name:
		&"objects": return objects
		&"containers": return containers
		&"structures": return structures
		&"drops": return drops
		&"population": return population
	return {}


## Merges `fields` into the entry `wid` of `table` and marks the table dirty. Returns the merged entry.
func merge(table: StringName, wid: int, fields: Dictionary) -> Dictionary:
	var t := _table(table)
	var e: Dictionary = t.get(wid, {})
	e.merge(fields, true)
	t[wid] = e
	dirty[table] = true
	return e


func get_entry(table: StringName, wid: int) -> Dictionary:
	return _table(table).get(wid, {})


func erase(table: StringName, wid: int) -> void:
	var t := _table(table)
	if t.erase(wid):
		dirty[table] = true


## Replicated part (what a client needs): objects + structures + drops; containers only expose `open_by`.
func to_net_dict() -> Dictionary:
	return {"cx": cx, "cz": cz, "objects": objects.duplicate(true), "structures": structures.duplicate(true),
		"drops": drops.duplicate(true)}


## Full record for persistence (JSON-friendly: wids as strings).
func to_dict(only_dirty: bool = false) -> Dictionary:
	var out := {"cx": cx, "cz": cz}
	for t in TABLES:
		if only_dirty and not dirty.get(t, false):
			continue
		var src := _table(t)
		if t == &"population":
			out[String(t)] = src.duplicate(true)
			continue
		var packed := {}
		for wid in src:
			packed[str(wid)] = (src[wid] as Dictionary).duplicate(true)
		out[String(t)] = packed
	return out


static func from_dict(d: Dictionary) -> ChunkDelta:
	var out := ChunkDelta.make(int(d.get("cx", 0)), int(d.get("cz", 0)))
	out.merge_dict(d)
	out.dirty.clear()
	return out


## Merges a dictionary in either form (int or string wids) into this record (used by snapshots and loads).
func merge_dict(d: Dictionary) -> void:
	for t in TABLES:
		if not d.has(String(t)):
			continue
		var src: Dictionary = d[String(t)]
		if t == &"population":
			population.merge(src, true)
			dirty[t] = true
			continue
		for k in src:
			merge(t, int(k), src[k])


## Packs the replicated part for the wire (var_to_bytes + zstd, ARQ v2 §6.3 CHUNK_DELTA).
func pack() -> Dictionary:
	var raw := var_to_bytes(to_net_dict())
	return {"key": key(), "size": raw.size(), "bytes": raw.compress(FileAccess.COMPRESSION_ZSTD)}


static func unpack(size: int, bytes: PackedByteArray) -> Dictionary:
	if size < 4 or size > 4_000_000 or bytes.is_empty():
		return {}
	var raw := bytes.decompress(size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() < 4:
		return {}
	var v: Variant = bytes_to_var(raw)
	return v if v is Dictionary else {}
