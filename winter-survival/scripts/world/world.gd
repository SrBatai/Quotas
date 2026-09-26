class_name World
extends Node3D
## The open world (M3, ARQ v2 §8): a deterministic 3 × 3 km terrain streamed in 64 m chunks around the players
## (WorldStreamer) with the slice's hunter's clearing as a hand-placed POI at the centre (cabin, A-frame, truck,
## signpost, fences, pond: permanent nodes; its trees / rocks / bushes / pickups are the slice scatter, ported
## exactly, now in the chunks). Same scene on the server and the client: both build the height field and the
## scatter from the world seed (the pure client learns it during authentication), so only deltas travel. The
## dedicated server strips lights / sky / particles / footprints; the client disables the spawners and the
## weather scheduler (decisions are the server's). Emits Events.world_ready once the node tree exists (the
## pure client then connects; its chunks load around its player as soon as the seed arrived).

signal configured()

static var instance: World
static var _macro_cache: MacroMap
static var _hf_cache: Dictionary = {}
static var _clearing_cache: Dictionary = {}

@export var decorative_only: bool = false
@export var world_seed: int = 0

@onready var terrain: Terrain = $Terrain
@onready var streamer: WorldStreamer = $Streamer
@onready var cabin: Cabin = $Cabin
@onready var actors: Node3D = $Actors
@onready var footprints: Footprints = $Footprints

var is_ready: bool = false
var is_configured: bool = false
var seed_value: int = 0
var hf: HeightFunction
var menu_focus: Vector3 = Vector3(-3.0, 0.0, 1.0)
var _menu_camera: Camera3D
var _env_t: float = 0.0
var _spawn_ground: float = 0.0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null
	if WorldRegistry.materializer.is_valid() and WorldRegistry.materializer.get_object() == self:
		WorldRegistry.materializer = Callable()


func _ready() -> void:
	add_to_group("world")
	var server_side := Net.is_server and not decorative_only
	$WolfSpawner.enabled = server_side
	$DeerSpawner.enabled = server_side
	$Respawner.enabled = server_side
	$Weather.scheduler_enabled = server_side
	$RegionTracker.enabled = Net.has_client and not decorative_only
	if not decorative_only and not Net.has_client:
		# dedicated server: nothing to render (ARQ v2 §1.5)
		for n in ["Sun", "Moon", "Env", "DayNight", "Snowfall", "Footprints"]:
			var node := get_node_or_null(n)
			if node != null:
				remove_child(node)
				node.queue_free()
		footprints = null
	var s := world_seed if world_seed != 0 else Balance.TERRAIN_SEED
	if decorative_only:
		configure(s)
	elif Net.is_server:
		if Net.is_dedicated:
			s = int(Net.cfg_get("world", "seed", s))
		configure(s)
	elif Net.server_seed != 0:
		configure(Net.server_seed)
	else:
		# pure client: the seed arrives with the authentication nonce (before any spawn / RPC)
		Net.seed_received.connect(func(sv: int) -> void:
			if not is_configured and is_inside_tree():
				configure(sv), CONNECT_ONE_SHOT)
	call_deferred("_emit_ready")


func _emit_ready() -> void:
	is_ready = true
	Events.world_ready.emit()


## Builds the height field (cached per seed), places the clearing POI and starts streaming.
func configure(s: int) -> void:
	if is_configured:
		return
	seed_value = s
	var t0 := Time.get_ticks_usec()
	if _macro_cache == null:
		_macro_cache = MacroMap.load_default()
	if not _hf_cache.has(s):
		_hf_cache[s] = HeightFunction.create(s, _macro_cache)
	hf = _hf_cache[s]
	if not _clearing_cache.has(s):
		_clearing_cache[s] = ScatterGen.clearing_entries(s)
	terrain.setup(hf, streamer)
	_build_lake()
	_place_props(Regions.AFRAME_POS, Regions.TRUCK_POS)
	_spawn_ground = terrain.get_height(0, 0)
	var mode := WorldStreamer.Mode.OFFLINE
	if decorative_only:
		mode = WorldStreamer.Mode.DECORATIVE
	elif Net.is_dedicated:
		mode = WorldStreamer.Mode.SERVER
	elif Net.is_client:
		mode = WorldStreamer.Mode.CLIENT
	streamer.setup(mode, hf, _clearing_cache[s], _collect_occluders(), $Chunks)
	_warm_assets(mode)
	WorldRegistry.materializer = materialize_wid
	if decorative_only:
		_setup_menu_camera()
		streamer.focus_override = menu_focus
		streamer.ensure_loaded(menu_focus, 1)
	elif mode != WorldStreamer.Mode.CLIENT:
		streamer.ensure_loaded(get_spawn_point(), 1)
	is_configured = true
	print("[WORLD] seed %d configured in %d ms (%s, %d chunks loaded)" % [s, (Time.get_ticks_usec() - t0) / 1000,
		WorldStreamer.Mode.keys()[mode], streamer.loaded_keys().size()])
	configured.emit()


## Loads / builds every model the chunks instantiate once, up front: the first placeholder build or .glb load of a
## variant would otherwise land inside a streaming step (a hitch while walking).
func _warm_assets(mode: int) -> void:
	var t0 := Time.get_ticks_usec()
	if streamer.visual:
		for v in ScatterCatalog.VARIANTS:
			Assets.instancing_mesh(str(v["name"]))
	if mode != WorldStreamer.Mode.DECORATIVE:
		var models := ["firewood", "stone", "berry_bush", "stump"]
		for pad in PoiRegistry.PADS:
			if str(pad.get("model", "")) != "" and not models.has(str(pad["model"])):
				models.append(str(pad["model"]))
		for m in models:
			Assets.spawn_model(m).free()
	print("[WORLD] assets warmed in %d ms" % ((Time.get_ticks_usec() - t0) / 1000))


## Where the streamer looks when nobody is there yet.
func default_focus() -> Vector3:
	return menu_focus if decorative_only else get_spawn_point()


func get_height(x: float, z: float) -> float:
	return terrain.get_height(x, z)


func get_spawn_point() -> Vector3:
	return cabin.get_spawn_point()


func get_spawn_yaw() -> float:
	return cabin.get_spawn_yaw()


func region_at(x: float, z: float) -> String:
	return Regions.name_at(x, z)


## Synchronous chunk load around a point (spawn, teleport, a body over a hole). No-op before the seed is known.
func ensure_area(pos: Vector3, radius: int = 1) -> int:
	if not is_configured:
		return 0
	return streamer.ensure_loaded(pos, radius)


func has_collision_at(pos: Vector3) -> bool:
	return is_configured and streamer.has_collision_at(pos.x, pos.z)


# ------------------------------------------------------------------ scatter (MultiMesh trees by index)
## WorldRegistry resolver: the real node of a choppable scatter entry (materialized on demand).
func materialize_wid(wid: int) -> Node:
	var f := streamer.find_scatter(wid)
	if f.is_empty():
		return null
	return (f[0] as WorldChunk).materialize(int(f[1]))


## A replicated delta for an object that is not a live node: felled scatter trees (live = animate the fall).
## Returns true when a loaded scatter entry took it.
func apply_scatter_delta(wid: int, fields: Dictionary, live: bool) -> bool:
	if not is_configured:
		return false
	var f := streamer.find_scatter(wid)
	if f.is_empty():
		return false
	var c: WorldChunk = f[0]
	var i: int = f[1]
	if not bool(fields.get("felled", false)):
		return true   # hits only: a materialized tree reads them from NetWorld.delta_of
	if live and Net.has_client and c.is_available(i):
		var t := c.materialize(i)
		if t != null:
			t.apply_net_delta(fields)
			return true
	c.fell_static(i)
	return true


## Hover pick of a choppable scatter tree under the cursor ray (client). `ground` = where the ray met the world.
func pick_scatter(from: Vector3, dir: Vector3, ground: Vector3) -> ChoppableTree:
	if not is_configured:
		return null
	var max_t := from.distance_to(ground) + 0.5
	var dh := Vector2(dir.x, dir.z)
	var seen := {}
	var best: ChoppableTree = null
	var best_t := max_t
	for back in [0.0, 5.0, 10.0]:
		var p: Vector2 = Vector2(ground.x, ground.z) - dh.normalized() * float(back) if dh.length() > 0.001 else Vector2(ground.x, ground.z)
		var c := streamer.loaded_chunk_at(p.x, p.y)
		if c == null or seen.has(c.key):
			continue
		seen[c.key] = true
		var i := c.pick_choppable(from, dir, best_t)
		if i >= 0:
			var e: Dictionary = c.data.entries[i]
			var t_hit := from.distance_to(Vector3(float(e["x"]), float(e["y"]), float(e["z"])))
			if t_hit < best_t or best == null:
				best = c.materialize(i)
				best_t = t_hit
	return best


## Nearest available choppable entry to `pos` (variant prefix filter) in the loaded chunks: [chunk, index] or [].
func nearest_scatter(pos: Vector3, prefix: String = "", radius_chunks: int = 1) -> Array:
	var best: Array = []
	var best_d := INF
	for k in WorldConst.ring_keys(WorldConst.chunk_of(pos.x), WorldConst.chunk_of(pos.z), radius_chunks):
		var c: WorldChunk = streamer.chunks.get(k)
		if c == null or c.state != WorldChunk.State.LOADED:
			continue
		var i := c.nearest_choppable(pos, prefix)
		if i < 0:
			continue
		var d := Vector2(c.entry_position(i).x - pos.x, c.entry_position(i).z - pos.z).length()
		if d < best_d:
			best_d = d
			best = [c, i]
	return best


## Choppable scatter entries (trees + logs) available in the loaded chunks (tests).
func scatter_tree_count() -> int:
	var n := 0
	for k in streamer.chunks:
		var c: WorldChunk = streamer.chunks[k]
		for w in c.wid_index:
			if c.removed[c.wid_index[w]] == 0 or c.materialized.has(c.wid_index[w]):
				n += 1
	return n


# ------------------------------------------------------------------ replicated runtime objects (server calls)
## Server: a ground item that did not exist in the seeded world (wolf/deer drops, crafting overflow, dawn respawns).
func spawn_drop(item_id: StringName, model: String, pos: Vector3, amount: int = 1) -> Node3D:
	if not Net.is_server or DropSpawner.instance == null:
		return null
	return DropSpawner.instance.spawn_drop(item_id, model, pos, amount)


## Server: a placed structure (campfire; tent/box in P2).
func spawn_placed(kind: String, pos: Vector3, yaw: float) -> Node3D:
	if not Net.is_server or StructureSpawner.instance == null:
		return null
	return StructureSpawner.instance.spawn_structure(kind, pos, yaw)


# ------------------------------------------------------------------ the clearing POI (slice layout, unchanged)
func _build_lake() -> void:
	var lake := $Lake as MeshInstance3D
	var disc := CylinderMesh.new()
	disc.top_radius = terrain.lake_radius * 0.78
	disc.bottom_radius = terrain.lake_radius * 0.78
	disc.height = 0.06
	disc.radial_segments = 24
	disc.rings = 0
	disc.material = Assets.material("ice")
	lake.mesh = disc
	lake.position = Vector3(terrain.lake_center.x, terrain.lake_level + 0.02, terrain.lake_center.y)
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _place_props(aframe: Vector2, truck: Vector2) -> void:
	var h0 := terrain.get_height(0, 0)
	# v2 models face +Z (Vector3.MODEL_FRONT): the cabin's porch faces the camera with no rotation
	cabin.position = Vector3(0, h0, 0)
	cabin.rotation_degrees.y = 0.0
	var af := $AFrame as Node3D
	af.position = Vector3(aframe.x, terrain.get_height(aframe.x, aframe.y), aframe.y)
	var to_lake := terrain.lake_center - aframe
	af.rotation.y = atan2(to_lake.x, to_lake.y)  # +Z (front) toward the lake
	var tr := $Truck as Node3D
	tr.position = Vector3(truck.x, terrain.get_height(truck.x, truck.y), truck.y)
	tr.rotation_degrees.y = -25.0  # hood (+Z) points where the slice's 155° put it
	var sp := $Signpost as Node3D
	var spos := Regions.SIGNPOST_POS
	sp.position = Vector3(spos.x, terrain.get_height(spos.x, spos.y), spos.y)
	if sp.has_method("setup"):
		sp.setup(af.global_position, Vector3(terrain.lake_center.x, 0, terrain.lake_center.y))
	# fences: 6 segments behind/left of the house, 4 by the A-frame (screen-horizontal rows)
	var fence_scene: PackedScene = preload("res://scenes/world/fence.tscn")
	var right := Vector2(0.82, -0.57)
	var row_c := Vector2(-8.0, -11.5)
	for i in 6:
		var p := row_c + right * (float(i) - 2.5) * 2.0
		_add_fence(fence_scene, p, 35.0)
	var row2 := aframe + Vector2(-0.57, -0.82) * 6.0
	for i in 4:
		var p := row2 + right * (float(i) - 1.5) * 2.0
		_add_fence(fence_scene, p, 35.0)


## Contact-AO occluders of the clearing's fixed props (G1, doc 06 §3.8): buildings / truck as rects, signpost and
## fences; the scatter's own discs come with the chunk data (ScatterCatalog occluders).
func _collect_occluders() -> Array:
	var occ: Array = []
	var c := cabin.position
	occ.append({"id": "cabin", "pos": Vector2(c.x, c.z + 1.3), "size": Vector2(6.4, 8.0), "yaw": cabin.rotation.y, "strength": 0.50, "soft": 2.2})
	occ.append({"id": "cabin_porch", "pos": Vector2(c.x, c.z + 3.85), "size": Vector2(6.0, 2.9), "yaw": cabin.rotation.y, "strength": 0.45, "soft": 0.9})
	var af := $AFrame as Node3D
	occ.append({"id": "aframe", "pos": Vector2(af.position.x, af.position.z), "size": Vector2(6.4, 7.4), "yaw": af.rotation.y, "strength": 0.45, "soft": 1.8})
	var tr := $Truck as Node3D
	occ.append({"id": "truck", "pos": Vector2(tr.position.x, tr.position.z), "size": Vector2(2.2, 5.2), "yaw": tr.rotation.y, "strength": 0.45, "soft": 1.4})
	var sp := $Signpost as Node3D
	occ.append({"id": "signpost", "pos": Vector2(sp.position.x, sp.position.z), "r": 0.5, "strength": 0.4})
	for f in $Fences.get_children():
		var fp: Vector3 = (f as Node3D).position
		occ.append({"id": "fence_%d" % f.get_index(), "pos": Vector2(fp.x, fp.z), "size": Vector2(2.0, 0.3), "yaw": (f as Node3D).rotation.y, "strength": 0.3, "soft": 0.6})
	return occ


func _add_fence(scene: PackedScene, p: Vector2, yaw_deg: float) -> void:
	var f: Node3D = scene.instantiate()
	$Fences.add_child(f)
	f.position = Vector3(p.x, terrain.get_height(p.x, p.y), p.y)
	f.rotation_degrees.y = yaw_deg


func _setup_menu_camera() -> void:
	_menu_camera = Camera3D.new()
	_menu_camera.name = "MenuCamera"
	_menu_camera.fov = 34.0
	add_child(_menu_camera)
	var focus := Vector3(-3.0, terrain.get_height(0, 0) + 1.0, 1.0)
	var offset := Vector3(0.54, 0.62, 0.54).normalized() * 30.0
	_menu_camera.global_position = focus + offset
	_menu_camera.look_at(focus, Vector3.UP)
	_menu_camera.current = true


# ------------------------------------------------------------------ environment around the focus (client)
func _process(delta: float) -> void:
	if not Net.has_client or not is_configured:
		return
	_env_t -= delta
	if _env_t > 0.0:
		return
	_env_t = 0.5
	var dn := get_node_or_null("DayNight") as DayNight
	if dn == null:
		return
	var focus := default_focus()
	var rig := CameraRig.active()
	if rig != null:
		focus = rig.global_position
	# the fog is tuned for the clearing: follow the ground height, thicken toward the world border (PLAN C6)
	dn.fog_height_offset = terrain.get_height(focus.x, focus.z) - _spawn_ground
	var cheb := maxf(absf(focus.x), absf(focus.z))
	dn.fog_density_scale = 1.0 + 3.0 * HeightFunction.smooth(WorldConst.BORDER_START + 100.0, WorldConst.WALL, cheb)
