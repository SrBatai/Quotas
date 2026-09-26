class_name PopulationManager
extends Node
## Server: the resident zombies of each chunk (ARQ v2 §10.6, GDD v2 §6.4, PLAN C21; the L2/L3 levels of C9 are
## per-chunk counters here). A chunk's target comes from the seed and the macro biome (forest 0–1, field 0–1, lake
## ice 0–1 always frozen, mountains 0, settlements 3–8), × the server rule `zombie_count_scale` (× 0.6 on the web).
## When a player gets within HOT_RADIUS of a chunk, its (target − killed) residents become ZombieSystem records at
## hashed points of the chunk: FROZEN_SHARE of the outdoor ones stand frozen (the minefield), the rest idle; a forest
## POI with a `Spawn_Zombie_n` gets one sleeper inside. Records farther than Balance.ZOMBIE_DESPAWN_RADIUS from every
## player go back into their chunk's counter. Kills persist in the chunk's ChunkDelta `population` table; after
## RESPAWN_DAYS without a visit only 60 % of the killed come back (GDD §6.4, `loot_respawn`-like rule).
## The hunter's clearing has no residents: its night visitors come from the Director.

const HOT_RADIUS := 110.0
const FROZEN_SHARE := 0.4
const CLEARING_SAFE := 100.0
const RESPAWN_DAYS := 3
const GEN := 404   # hash generator id

static var instance: PopulationManager

var enabled: bool = true
var sys: ZombieSystem
var world: World
var scale: float = 1.0
## chunk key -> {"n": target, "killed": int, "out": records alive in the world, "spawned": bool}
var pop: Dictionary = {}
var _t: float = 0.0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func setup(p_sys: ZombieSystem, p_world: World) -> void:
	sys = p_sys
	world = p_world
	name = "PopulationManager"
	if OS.has_feature("web"):
		scale = 0.6


func _rule_scale() -> float:
	return clampf(float(WorldState.rules_now().get("zombie_count_scale", 1.0)), 0.0, 4.0) * scale


## Resident target of a chunk (deterministic from the seed and the macro map).
func target_of(key: int) -> int:
	var cx := WorldConst.key_cx(key)
	var cz := WorldConst.key_cz(key)
	var c := WorldConst.chunk_center(cx, cz)
	if maxf(absf(c.x), absf(c.z)) < CLEARING_SAFE or not WorldConst.in_playable(c.x, c.z):
		return 0
	var hf := world.hf
	var seed_v := hf.world_seed
	var u := WorldConst.rand01(seed_v, GEN, cx, cz, 0)
	var b := hf.macro.biome_at(c.x, c.z)
	var n := 0
	match b:
		MacroMap.Biome.DENSE_FOREST, MacroMap.Biome.FOREST:
			n = 1 if u < 0.45 else 0
		MacroMap.Biome.FIELD:
			n = 1 if u < 0.35 else 0
		MacroMap.Biome.LAKE:
			n = 1 if u < 0.3 else 0
		MacroMap.Biome.SETTLEMENT:
			n = 3 + int(WorldConst.rand01(seed_v, GEN, cx, cz, 1) * 6.0)
	for pad in PoiRegistry.PADS:
		var pc: Vector2 = pad["center"]
		if str(pad.get("model", "")) == "cabin_small" and WorldConst.key(WorldConst.chunk_of(pc.x), WorldConst.chunk_of(pc.y)) == key:
			n += 1
	return int(round(float(n) * _rule_scale()))


func _entry(key: int) -> Dictionary:
	var e: Dictionary = pop.get(key, {})
	if e.is_empty():
		e = {"n": target_of(key), "killed": 0, "out": 0, "spawned": false}
		var nw := NetWorld.instance
		if nw != null and nw.chunks.has(key):
			var saved: Dictionary = (nw.chunks[key] as ChunkDelta).population
			e["killed"] = int(saved.get("killed", 0))
			var last := int(saved.get("last_visit", WorldState.day_now()))
			if WorldState.day_now() - last >= RESPAWN_DAYS:
				e["killed"] = int(floor(float(e["killed"]) * 0.4))
		pop[key] = e
	return e


func _process(delta: float) -> void:
	if not enabled or sys == null or world == null or not world.is_configured:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0
	var players := _player_positions()
	if players.is_empty():
		return
	# wake the residents of hot chunks
	for k in world.streamer.chunks:
		var ch: WorldChunk = world.streamer.chunks[k]
		if ch.state != WorldChunk.State.LOADED:
			continue
		var c := WorldConst.chunk_center(ch.cx, ch.cz)
		var near := false
		for p in players:
			if Vector2(c.x - p.x, c.z - p.z).length() <= HOT_RADIUS:
				near = true
				break
		if near:
			var e := _entry(k)
			if not bool(e["spawned"]):
				_spawn_chunk(k, e, ch)
	# far records go back into their chunk's counter
	for i in sys.used.size():
		if sys.used[i] == 0 or sys.lod[i] != 2:
			continue
		var p := sys.pos[i]
		var d := INF
		for q in players:
			d = minf(d, Vector2(q.x - p.x, q.z - p.z).length())
		if d > Balance.ZOMBIE_DESPAWN_RADIUS:
			var k := sys.chunk[i]
			var e: Dictionary = pop.get(k, {})
			if not e.is_empty():
				e["out"] = maxi(int(e["out"]) - 1, 0)
				if int(e["out"]) == 0:
					e["spawned"] = false
			sys.release(i)


func _player_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	var players := world.get_node_or_null("Players")
	if players == null:
		return out
	for c in players.get_children():
		if c is Player and not (c as Player).disconnected:
			out.append((c as Node3D).global_position)
	return out


func _spawn_chunk(key: int, e: Dictionary, ch: WorldChunk) -> void:
	e["spawned"] = true
	var want := int(e["n"]) - int(e["killed"]) - int(e["out"])
	_mark_visit(key)
	if want <= 0:
		return
	var seed_v := world.hf.world_seed
	var o := WorldConst.chunk_origin(ch.cx, ch.cz)
	var made := 0
	# a sleeper in the forest cabin of this chunk (its Spawn_Zombie_0, when the POI model has one)
	for n in ch.objects.get_children() if ch.objects != null else []:
		if made >= want or not n.is_in_group("poi_prop"):
			continue
		var sp := (n as Node3D).find_child("Spawn_Zombie_0", true, false) as Node3D
		if sp != null:
			var i := sys.spawn(ZombieKinds.Kind.WALKER, sp.global_position, sp.global_rotation.y, ZombieKinds.State.IDLE, -1, key)
			if i >= 0:
				sys.home[i] = sp.global_position
				made += 1
	var attempt := 0
	while made < want and attempt < want * 6:
		attempt += 1
		var x := o.x + 4.0 + WorldConst.rand01(seed_v, GEN, ch.cx, ch.cz, 10 + attempt * 3) * (WorldConst.CHUNK_SIZE - 8.0)
		var z := o.y + 4.0 + WorldConst.rand01(seed_v, GEN, ch.cx, ch.cz, 11 + attempt * 3) * (WorldConst.CHUNK_SIZE - 8.0)
		var u := WorldConst.rand01(seed_v, GEN, ch.cx, ch.cz, 12 + attempt * 3)
		var lake := world.terrain.is_lake(x, z)
		var frozen := lake or u < FROZEN_SHARE
		var k := ZombieKinds.Kind.WALKER if frozen else ZombieKinds.pick(u, WorldState.day_now(), false)
		var st := ZombieKinds.State.FROZEN if frozen else ZombieKinds.State.IDLE
		if frozen:
			k = ZombieKinds.Kind.FROZEN
		var i := sys.spawn(k, Vector3(x, 0.0, z), u * TAU, st, -1, key)
		if i >= 0:
			made += 1
	e["out"] = int(e["out"]) + made


func _mark_visit(key: int) -> void:
	var nw := NetWorld.instance
	if nw == null:
		return
	var d := nw.delta_for_key(key)
	d.population["last_visit"] = WorldState.day_now()
	d.dirty[&"population"] = true


## ZombieSystem: a resident died (the kill persists in the chunk's delta).
func on_killed(key: int) -> void:
	if key < 0:
		return
	var e: Dictionary = pop.get(key, {})
	if not e.is_empty():
		e["killed"] = int(e["killed"]) + 1
		e["out"] = maxi(int(e["out"]) - 1, 0)
	var nw := NetWorld.instance
	if nw != null:
		var d := nw.delta_for_key(key)
		d.population["killed"] = int(d.population.get("killed", 0)) + 1
		d.dirty[&"population"] = true
