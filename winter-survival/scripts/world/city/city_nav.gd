class_name CityNav
extends Node
## Server: the navigation of the enterable floors of Altavega (C1, doc 09 §4.4; R17 «Teselas por planta perezosas,
## escaleras como enlaces, ≤ 12 teselas/s»). Keeps a NavFloorTile per (hero tower, floor) that some player needs —
## a player inside the tower or within NEAR m of it wants the floors k−1 … k+1 of its own floor k (floor 0 is the
## street navmesh of NavBaker) — bakes them one at a time in a worker, adds them as regions of the world's navigation
## map (NavBaker.map, the one the zombies' NavQueryQueue asks) and joins consecutive floors with a bidirectional
## NavigationLink3D from the top of the stair's second flight to the landing of the next floor. Tiles nobody wants
## for KEEP s are freed with their links. Web (no threads): synchronous bakes at 0.5 m cells, one per REBAKE_WEB s.

const NEAR := 30.0
const KEEP := 10.0
const MAX_PER_SECOND := 12
const REBAKE_WEB := 0.3

static var instance: CityNav

var world: World
var map: RID
var tiles: Dictionary = {}        # "hero|k" -> NavFloorTile (baked)
var links: Dictionary = {}        # "hero|k" -> [RID…] (the links from floor k to k + 1)
var _pending: Dictionary = {}     # "hero|k" -> true (wanted, not baked yet)
var _running: NavFloorTile
var _bakes_t: Array[float] = []   # completion times of the last bakes (rate limit)
var _t: float = 0.0
var stats: Dictionary = {"baked": 0, "bake_usec_max": 0, "links": 0, "freed": 0, "polygons": 0}


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null
	if _running != null:
		_running.cancelled = true
		if _running.task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(_running.task_id)
	for k in tiles.keys():
		_free_tile(k)


func setup(p_world: World) -> void:
	world = p_world
	name = "CityNav"


func _ready_map() -> bool:
	if map.is_valid():
		return true
	if NavBaker.instance == null or not NavBaker.instance.map.is_valid():
		return false
	map = NavBaker.instance.map
	return true


static func key_of(hero: int, k: int) -> String:
	return "%d|%d" % [hero, k]


func _process(delta: float) -> void:
	if world == null or not Net.is_server or not _ready_map():
		return
	_collect()
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	var now := Time.get_ticks_msec() / 1000.0
	var towers := get_tree().get_nodes_in_group("hero_tower")
	var players: Array = []
	var pl := world.get_node_or_null("Players")
	if pl != null:
		for c in pl.get_children():
			if c is Player and not (c as Player).disconnected:
				players.append((c as Node3D).global_position)
	for t in towers:
		var ht := t as HeroTower
		if not ht.is_inside_tree():
			continue
		for p in players:
			var l := ht.global_transform.affine_inverse() * (p as Vector3)
			if absf(l.x) > ht.size.x * 0.5 + NEAR or absf(l.z) > ht.size.y * 0.5 + NEAR:
				continue
			var inside := absf(l.x) < ht.size.x * 0.5 and absf(l.z) < ht.size.y * 0.5
			var k := ht.floor_at_y((p as Vector3).y) if inside else 0
			for f in range(maxi(k - 1, 1), mini(k + 1, ht.floors - 1) + 1):
				var key := key_of(ht.hero_id, f)
				if tiles.has(key):
					(tiles[key] as NavFloorTile).last_wanted = now
				elif _running == null or key_of(_running.hero_id, _running.floor_k) != key:
					_pending[key] = ht
	# free the tiles nobody wanted for KEEP s (and tiles of towers that left the tree)
	for key in tiles.keys():
		var tile: NavFloorTile = tiles[key]
		if now - tile.last_wanted > KEEP or _tower(tile.hero_id) == null:
			_free_tile(key)
	# start one bake (rate limited)
	while not _bakes_t.is_empty() and now - _bakes_t[0] > 1.0:
		_bakes_t.remove_at(0)
	if _running != null or _pending.is_empty() or _bakes_t.size() >= MAX_PER_SECOND:
		return
	var key0: String = _pending.keys()[0]
	var tw: HeroTower = _pending[key0]
	_pending.erase(key0)
	if not is_instance_valid(tw) or not tw.is_inside_tree():
		return
	var tile0 := NavFloorTile.make(tw, int(key0.get_slice("|", 1)), NavBaker.instance.cell)
	tile0.last_wanted = now
	if WorldStreamer.threads_ok():
		_running = tile0
		tile0.task_id = WorkerThreadPool.add_task(tile0.run, false, "navfloor %s" % key0)
	else:
		tile0.run()
		_apply(tile0)


func _collect() -> void:
	if _running == null or not WorkerThreadPool.is_task_completed(_running.task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_running.task_id)
	var t := _running
	_running = null
	if not t.cancelled:
		_apply(t)


func _apply(t: NavFloorTile) -> void:
	var key := key_of(t.hero_id, t.floor_k)
	if t.nm == null or _tower(t.hero_id) == null or tiles.has(key):
		return   # (a tile baked twice keeps the first: no second region)
	t.region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(t.region, map)
	NavigationServer3D.region_set_use_edge_connections(t.region, false)
	NavigationServer3D.region_set_navigation_mesh(t.region, t.nm)
	tiles[key] = t
	_bakes_t.append(Time.get_ticks_msec() / 1000.0)
	stats["baked"] = int(stats["baked"]) + 1
	stats["bake_usec_max"] = maxi(int(stats["bake_usec_max"]), t.usec)
	stats["polygons"] = int(stats["polygons"]) + t.polygon_count()
	_link(t.hero_id, t.floor_k - 1)
	_link(t.hero_id, t.floor_k)


## The stair links from floor k to k + 1 once both ends have a tile (floor 0 = the street navmesh, always there):
## flight A (the landing of floor k → the half landing), flight B (the half landing → the landing of floor k + 1)
## and the stairwell door of floor k + 1 (office floor ↔ its landing: the 1 m doorway is narrower than the eroded
## agent). Every link is a straight line a walker follows up the ramp.
func _link(hero: int, k: int) -> void:
	var key := key_of(hero, k)
	if k < 0 or links.has(key):
		return
	var tw := _tower(hero)
	if tw == null or k + 1 >= tw.floors:
		return
	if k >= 1 and not tiles.has(key_of(hero, k)):
		return
	if not tiles.has(key_of(hero, k + 1)):
		return
	var rids: Array = []
	var ends: Array = stair_links(tw, k)
	if k == 0:
		ends.append(door_link(tw, 0))
	for pair in ends:
		var rid := NavigationServer3D.link_create()
		NavigationServer3D.link_set_map(rid, map)
		NavigationServer3D.link_set_bidirectional(rid, true)
		NavigationServer3D.link_set_start_position(rid, pair[0])
		NavigationServer3D.link_set_end_position(rid, pair[1])
		rids.append(rid)
	links[key] = rids
	stats["links"] = int(stats["links"]) + rids.size()


## World ends of the links from floor k to k + 1: [[landing k, half landing], [half landing, landing k + 1],
## [office floor k + 1, landing k + 1]].
static func stair_links(tw: HeroTower, k: int) -> Array:
	var sw := HeroTower.stairwell(tw.size)
	var xa := float(sw["x0"]) + HeroTower.FLIGHT_W * 0.5
	var xb := float(sw["x1"]) - HeroTower.FLIGHT_W * 0.5
	var zl := float(sw["z1"]) - 0.6
	var zh := float(sw["z0"]) + HeroTower.LANDING * 0.5
	var y0 := HeroTower.level(k, tw.gh, tw.fh)
	var y1 := HeroTower.level(k + 1, tw.gh, tw.fh)
	var xf := tw.global_transform
	return [[xf * Vector3(xa, y0, zl), xf * Vector3(xa, (y0 + y1) * 0.5, zh)],
		[xf * Vector3(xb, (y0 + y1) * 0.5, zh), xf * Vector3(xb, y1, zl)],
		door_link(tw, k + 1)]


## The stairwell door of floor k: the office floor in front of it ↔ the landing behind it.
static func door_link(tw: HeroTower, k: int) -> Array:
	var sw := HeroTower.stairwell(tw.size)
	var x := float(sw["x0"]) + 0.7
	var y := HeroTower.level(k, tw.gh, tw.fh)
	return [tw.global_transform * Vector3(x, y, float(sw["z1"]) + 1.2), tw.global_transform * Vector3(x, y, float(sw["z1"]) - 0.6)]


func _free_tile(key: String) -> void:
	var t: NavFloorTile = tiles.get(key)
	if t != null and t.region.is_valid():
		NavigationServer3D.free_rid(t.region)
	tiles.erase(key)
	var hero := int(key.get_slice("|", 0))
	var k := int(key.get_slice("|", 1))
	for lk in [key_of(hero, k - 1), key_of(hero, k)]:
		if links.has(lk):
			for rid in links[lk]:
				NavigationServer3D.free_rid(rid)
			links.erase(lk)
	stats["freed"] = int(stats["freed"]) + 1


func _tower(hero: int) -> HeroTower:
	for t in get_tree().get_nodes_in_group("hero_tower"):
		if (t as HeroTower).hero_id == hero and (t as HeroTower).is_inside_tree():
			return t as HeroTower
	return null


## Tests: bake every wanted tile now (synchronously) — returns how many were baked.
func bake_now() -> int:
	var n := 0
	_process(1.0)
	if _running != null:
		WorkerThreadPool.wait_for_task_completion(_running.task_id)
		_collect()
		n += 1
	var guard := 0
	while not _pending.is_empty() and guard < 200:
		guard += 1
		var key0: String = _pending.keys()[0]
		var tw: HeroTower = _pending[key0]
		_pending.erase(key0)
		if not is_instance_valid(tw):
			continue
		var t := NavFloorTile.make(tw, int(key0.get_slice("|", 1)), NavBaker.instance.cell if NavBaker.instance != null else 0.25)
		t.last_wanted = Time.get_ticks_msec() / 1000.0
		t.run()
		_apply(t)
		n += 1
	return n
