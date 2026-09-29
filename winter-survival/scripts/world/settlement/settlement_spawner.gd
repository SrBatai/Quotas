class_name SettlementSpawner
extends Node
## World placement of the M6b sites (Settlements: La Herrería, the sawmill, the Gasolinera Norte, the Granja del
## Molino), like KitStreets / LootSpawns: one node per game (server and client flavours) hooked to
## WorldStreamer.chunk_loaded. When a chunk that holds site buildings / items finishes loading, a SettlementChunk is
## put under that chunk's `objects` node and builds them over the next frames (one building per frame, the rest in
## small batches); every piece is a direct child of `objects`, so the chunk's teardown frees them one at a time and
## they live and die with the chunk. Deterministic wids (buildings: KitBuilding.wid_for(seed, site, i); items:
## Settlements.GEN_ITEM) make every peer build the same village without replicating a node: only door / container
## deltas travel. Also registers the sites' own zones (the sawmill) with Locations (H2 titles) and owns the village
## lamps (VillageLights, clients with a display).

static var instance: SettlementSpawner

var world: World
## Tests / benches without a World: the seed of the plans.
var test_seed: int = 0
var live: Dictionary = {}          # chunk key -> SettlementChunk
var lights: VillageLights
## Tests / stats.
var chunks_built: int = 0
var buildings_built: int = 0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func setup(p_world: World) -> void:
	world = p_world
	name = "SettlementSpawner"
	for z in Settlements.zone_records():
		Locations.register(z)
	if KitBuilding.visual():
		lights = VillageLights.new()
		lights.name = "VillageLights"
		add_child(lights)
	if world.is_configured:
		_hook()
	else:
		world.configured.connect(_hook, CONNECT_ONE_SHOT)


func _hook() -> void:
	print("[SETTLEMENT] plans %s (seed %d, %d sites)" % [Settlements.plan_hash(seed_v()).substr(0, 16), seed_v(), Settlements.plans(seed_v()).size()])
	if world.streamer == null:
		return
	if KitBuilding.visual():
		print("[SETTLEMENT] warmed in %d ms" % (warm() / 1000))
	if not world.streamer.chunk_loaded.is_connected(_on_chunk_loaded):
		world.streamer.chunk_loaded.connect(_on_chunk_loaded)
		world.streamer.chunk_unloaded.connect(_on_chunk_unloaded)
	for k in world.streamer.loaded_keys():
		_on_chunk_loaded(k)


## Visual clients, while the world loads: the site models and merged prop meshes (SettlementChunk.warm) and one
## throwaway KitBuilding (the first one pays the building materials, the cutaway and the sign text: ≈ 25 ms that
## would otherwise land in the frame of the first village building met while driving). µs.
func warm() -> int:
	var t0 := Time.get_ticks_usec()
	SettlementChunk.warm(seed_v())
	var holder := Node3D.new()
	holder.name = "WarmUp"
	holder.visible = false
	add_child(holder)
	holder.global_position = Vector3(0.0, -500.0, 0.0)
	var b := KitBuilding.new()
	b.setup("shop_general", "brick", WorldConst.hash64(seed_v(), 0x5741524D, 1), seed_v(), 1, "WARM")
	holder.add_child(b)
	holder.free()
	return Time.get_ticks_usec() - t0


func seed_v() -> int:
	return world.seed_value if world != null else test_seed


func _on_chunk_loaded(key: int) -> void:
	if live.has(key) and is_instance_valid(live[key]):
		return
	var items := Settlements.items_in_chunk(seed_v(), key)
	if items.is_empty():
		return
	var c: WorldChunk = world.streamer.chunks.get(key)
	if c == null or c.objects == null:
		return
	var sc := SettlementChunk.new()
	sc.setup(key, items, seed_v(), world, self)
	c.objects.add_child(sc)
	live[key] = sc
	chunks_built += 1


## The chunk is being torn down: its doors / containers stop answering at once (a quick reload builds new ones with
## the same wids), its lamps leave the lights.
func _on_chunk_unloaded(key: int) -> void:
	var sc: SettlementChunk = live.get(key)
	live.erase(key)
	if sc != null and is_instance_valid(sc):
		sc.release()


## Builds (now) every chunk of the sites a test needs, under `parent` (tests / benches without a streamer).
func build_now(parent: Node3D, keys: Array) -> Array[SettlementChunk]:
	var out: Array[SettlementChunk] = []
	for key in keys:
		var items := Settlements.items_in_chunk(seed_v(), int(key))
		if items.is_empty():
			continue
		var sc := SettlementChunk.new()
		sc.setup(int(key), items, seed_v(), world, self)
		parent.add_child(sc)
		sc.build_all()
		live[int(key)] = sc
		out.append(sc)
	return out


## The KitBuilding of a site building (by site id and index), when its chunk is built; null otherwise.
func building(site_id: String, index: int) -> KitBuilding:
	for k in live:
		var sc: SettlementChunk = live[k]
		if not is_instance_valid(sc):
			continue
		for b in sc.buildings:
			if is_instance_valid(b) and str(b.get_meta("site", "")) == site_id and int(b.get_meta("index", -1)) == index:
				return b
	return null


## Every built KitBuilding of the sites (tests).
func all_buildings() -> Array[KitBuilding]:
	var out: Array[KitBuilding] = []
	for k in live:
		var sc: SettlementChunk = live[k]
		if is_instance_valid(sc):
			for b in sc.buildings:
				if is_instance_valid(b):
					out.append(b)
	return out


# ------------------------------------------------------------------ residents (PopulationManager hook, server)
## Spawns up to `want` residents of chunk `key` at their Settlements spots: indoors idle walkers (asleep until a noise
## or a player), outdoors Settlements.FROZEN_SHARE frozen and the rest idle of the day's kinds. Returns how many.
static func spawn_residents(sys: ZombieSystem, seed_value: int, key: int, want: int) -> int:
	var made := 0
	for sp: Dictionary in Settlements.resident_spots(seed_value, key):
		if made >= want:
			break
		var p: Vector2 = sp["pos"]
		var k := ZombieKinds.Kind.WALKER
		var st := ZombieKinds.State.IDLE
		if not bool(sp["in"]):
			if bool(sp.get("frozen", false)):
				k = ZombieKinds.Kind.FROZEN
				st = ZombieKinds.State.FROZEN
			else:
				k = ZombieKinds.pick(float(sp.get("u", 0.5)), WorldState.day_now(), false)
		var i := sys.spawn(k, Vector3(p.x, 0.0, p.y), float(sp["yaw"]), st, -1, key)
		if i >= 0:
			made += 1
	return made
