class_name CityPopulation
extends Node
## Server: the population per floor of the hero towers (C1, doc 09 §4.4 «Población por planta», PLAN C32). Each floor
## k ≥ 1 of a tower is an L3 counter (its residents − its kills): nobody exists there until a player is inside the
## tower (or within NEAR m of its door) at most WINDOW floors away; then the floor's living residents become
## ZombieSystem records standing on that floor (hashed points of its office floor plate, away from the stair core),
## and when no player is within WINDOW floors for RELEASE s they go back into the counter. Kills are remembered in
## the tower chunk's ChunkDelta `population` table (`hero_<id>_<k>`), so a cleared floor stays cleared after a
## restart. Records of this manager carry chunk key −3 (PopulationManager never counts or recycles them itself; its
## far-release of L1 records beyond 200 m is harmless: the floor re-materializes from its counter).

const GEN_FLOORS := 0x464C5250    # "FLRP"
const NEAR := 30.0
const WINDOW := 2
const RELEASE := 8.0
const CHUNK_KEY := -3

static var instance: CityPopulation

var world: World
var sys: ZombieSystem
var enabled: bool = true
## "hero|k" -> {"n": residents, "killed": int, "slots": PackedInt32Array, "ids": PackedInt32Array, "idle": float}
var floors: Dictionary = {}
var stats: Dictionary = {"materialized": 0, "released": 0, "killed": 0}
var _t: float = 0.0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func setup(p_world: World) -> void:
	world = p_world
	name = "CityPopulation"


## Residents of floor k of a hero tower (seed and tower, never the lobby: floor 0 belongs to the street): 0–4 on
## plain floors, 3–6 on furnished ones, none on the top floor (the command post that held out).
static func residents(seed_v: int, rec: Dictionary, k: int) -> int:
	var n := int(rec["floors"])
	if k <= 0 or k >= n - 1:
		return 0
	var u := WorldConst.rand01(seed_v, GEN_FLOORS, int(rec["id"]), k, 0)
	if HeroTower.furnished(rec).has(k):
		return 3 + int(u * 4.0)
	return int(u * 5.0)


## Standing points of floor k (tower local plan): the office plate outside the core and away from the facades.
static func floor_points(rec: Dictionary, k: int, count: int, seed_v: int) -> Array:
	var sz := CityLots.v2(rec["size"])
	var sw := HeroTower.stairwell(sz)
	var out: Array = []
	var tries := 0
	while out.size() < count and tries < count * 12:
		tries += 1
		var x := (WorldConst.rand01(seed_v, GEN_FLOORS, int(rec["id"]), k, 10 + tries * 2) * 2.0 - 1.0) * (sz.x * 0.5 - 2.0)
		var z := (WorldConst.rand01(seed_v, GEN_FLOORS, int(rec["id"]), k, 11 + tries * 2) * 2.0 - 1.0) * (sz.y * 0.5 - 2.0)
		if x > float(sw["x0"]) - 1.5 and x < float(sw["lift_x1"]) + 1.5 and z > float(sw["z0"]) - 1.5 and z < float(sw["z1"]) + 2.5:
			continue   # the core and its door
		var ok := true
		for w in HeroTower.office_walls(sz, sw):
			var a: Vector2 = w[0]
			var b: Vector2 = w[1]
			if Geometry2D.get_closest_point_to_segment(Vector2(x, z), a, b).distance_to(Vector2(x, z)) < 1.0:
				ok = false
		for dk in HeroTower.desks(sz, k):
			var dp: Vector3 = dk
			if absf(dp.x - x) < 1.4 and absf(dp.z - z) < 1.0:
				ok = false
		if ok:
			out.append(Vector2(x, z))
	return out


func _process(delta: float) -> void:
	if not enabled or not Net.is_server or world == null or not world.is_configured:
		return
	if PopulationManager.instance != null and not PopulationManager.instance.enabled:
		return   # `/director off` (tests): no residents anywhere, the floors included
	if sys == null:
		sys = ZombieSystem.instance
		if sys == null or sys.world == null:
			return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	var players: Array = []
	var pl := world.get_node_or_null("Players")
	if pl != null:
		for c in pl.get_children():
			if c is Player and not (c as Player).disconnected:
				players.append((c as Node3D).global_position)
	for t in get_tree().get_nodes_in_group("hero_tower"):
		var ht := t as HeroTower
		if not ht.is_inside_tree():
			continue
		var want := {}
		for p in players:
			var l := ht.global_transform.affine_inverse() * (p as Vector3)
			if absf(l.x) > ht.size.x * 0.5 + NEAR or absf(l.z) > ht.size.y * 0.5 + NEAR:
				continue
			var inside := absf(l.x) < ht.size.x * 0.5 and absf(l.z) < ht.size.y * 0.5
			var k := ht.floor_at_y((p as Vector3).y) if inside else 0
			for f in range(maxi(k - WINDOW, 1), mini(k + WINDOW, ht.floors - 1) + 1):
				want[f] = true
		for f in range(1, ht.floors):
			var key := "%d|%d" % [ht.hero_id, f]
			var e := _entry(ht, f)
			_count_losses(ht, f, e)
			if want.has(f):
				e["idle"] = 0.0
				if (e["slots"] as PackedInt32Array).is_empty():
					_materialize(ht, f, e)
			elif not (e["slots"] as PackedInt32Array).is_empty():
				e["idle"] = float(e["idle"]) + 0.5
				if float(e["idle"]) >= RELEASE:
					_release(e)
			floors[key] = e


func _entry(ht: HeroTower, k: int) -> Dictionary:
	var key := "%d|%d" % [ht.hero_id, k]
	if floors.has(key):
		return floors[key]
	var seed_v := world.hf.world_seed
	var e := {"n": residents(seed_v, ht.rec, k), "killed": 0, "slots": PackedInt32Array(), "ids": PackedInt32Array(), "idle": 0.0}
	var nw := NetWorld.instance
	var ck := WorldConst.key_of(ht.global_position)
	if nw != null and nw.chunks.has(ck):
		e["killed"] = int((nw.chunks[ck] as ChunkDelta).population.get("hero_%d_%d" % [ht.hero_id, k], 0))
	floors[key] = e
	return e


## Dead records of a floor become kills (persisted in the tower chunk's delta); records released by someone else
## (PopulationManager's far release) just go back into the counter.
func _count_losses(ht: HeroTower, k: int, e: Dictionary) -> void:
	var slots: PackedInt32Array = e["slots"]
	var ids: PackedInt32Array = e["ids"]
	if slots.is_empty():
		return
	var keep_s := PackedInt32Array()
	var keep_i := PackedInt32Array()
	var killed := 0
	for j in slots.size():
		var i := slots[j]
		var same := i < sys.used.size() and sys.used[i] == 1 and sys.net_id[i] == ids[j]
		if same and sys.state[i] != ZombieKinds.State.DEAD:
			keep_s.append(i)
			keep_i.append(ids[j])
		elif same:
			killed += 1
	e["slots"] = keep_s
	e["ids"] = keep_i
	if killed > 0:
		e["killed"] = int(e["killed"]) + killed
		stats["killed"] = int(stats["killed"]) + killed
		_persist(ht, k, e)


func _materialize(ht: HeroTower, k: int, e: Dictionary) -> void:
	var want := int(e["n"]) - int(e["killed"])
	if want <= 0:
		return
	var seed_v := world.hf.world_seed
	var pts := floor_points(ht.rec, k, want, seed_v)
	var y := ht.floor_y(k)
	var slots := PackedInt32Array()
	var ids := PackedInt32Array()
	for j in pts.size():
		var lp: Vector2 = pts[j]
		var wp := ht.global_transform * Vector3(lp.x, 0.0, lp.y)
		wp.y = y + 0.05
		var u := WorldConst.rand01(seed_v, GEN_FLOORS, ht.hero_id, k, 200 + j)
		var kind := ZombieKinds.pick(u, WorldState.day_now(), false)
		var i := sys.spawn(kind, wp, u * TAU, ZombieKinds.State.IDLE, -1, CHUNK_KEY)
		if i < 0:
			break
		sys.pos[i] = wp
		sys.home[i] = wp
		sys.goal[i] = wp
		sys.last_seen[i] = wp
		slots.append(i)
		ids.append(sys.net_id[i])
	e["slots"] = slots
	e["ids"] = ids
	stats["materialized"] = int(stats["materialized"]) + slots.size()
	_persist(ht, k, e)


func _release(e: Dictionary) -> void:
	var slots: PackedInt32Array = e["slots"]
	var ids: PackedInt32Array = e["ids"]
	for j in slots.size():
		var i := slots[j]
		if i < sys.used.size() and sys.used[i] == 1 and sys.net_id[i] == ids[j]:
			sys.release(i)
			stats["released"] = int(stats["released"]) + 1
	e["slots"] = PackedInt32Array()
	e["ids"] = PackedInt32Array()
	e["idle"] = 0.0


func _persist(ht: HeroTower, k: int, e: Dictionary) -> void:
	var nw := NetWorld.instance
	if nw == null:
		return
	var d := nw.delta_for_key(WorldConst.key_of(ht.global_position))
	d.population["hero_%d_%d" % [ht.hero_id, k]] = int(e["killed"])
	d.dirty[&"population"] = true


## Living floor records of a tower (tests / the net scenario).
func alive_on(hero: int) -> int:
	var n := 0
	for key in floors:
		if str(key).begins_with("%d|" % hero):
			n += (floors[key]["slots"] as PackedInt32Array).size()
	return n
