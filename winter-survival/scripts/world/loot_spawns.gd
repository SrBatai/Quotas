class_name LootSpawns
extends Node
## World placement of loot containers (M5, ARQ v2 §9.1 step 7 / §9.5). Runs on the server and on every client with
## the same result: when WorldStreamer finishes a chunk (`chunk_loaded`), each POI prop of that chunk (nodes with the
## `poi_model` meta: cabin_small, lookout_tower, campsite_remains today; the M6 town buildings through `attach`)
## is scanned for `Spawn_Container_<n>` (a container, extras `table`) and `Spawn_Loot_<n>` (a small loose-item pile,
## table `loose`) empties (ASSET_SPEC v2 M3.5). A LootContainer is added as a child of the POI node, so it lives and
## dies with the chunk; its wid = hash64(seed, GEN_LOOT, POI wid, spawn index), identical on every peer.
## The city comes later (C1): its building assembler calls `LootSpawns.attach(building, model, building_wid)` too.

static var instance: LootSpawns

var world: World
## Tests / stats: containers created so far (both kinds) and POI nodes already scanned.
var made: int = 0
var _done: Dictionary = {}   # POI node instance id -> true


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func setup(p_world: World) -> void:
	world = p_world
	if world.is_configured:
		_hook()
	else:
		world.configured.connect(_hook, CONNECT_ONE_SHOT)


func _hook() -> void:
	if world.streamer == null:
		return
	if not world.streamer.chunk_loaded.is_connected(_on_chunk_loaded):
		world.streamer.chunk_loaded.connect(_on_chunk_loaded)
	for k in world.streamer.loaded_keys():
		_on_chunk_loaded(k)


func _on_chunk_loaded(key: int) -> void:
	var c: WorldChunk = world.streamer.chunks.get(key)
	if c == null or c.objects == null:
		return
	for n in c.objects.get_children():
		if n.has_meta("poi_model") and not _done.has(n.get_instance_id()):
			_done[n.get_instance_id()] = true
			n.tree_exiting.connect(func() -> void: _done.erase(n.get_instance_id()), CONNECT_ONE_SHOT)
			var model: Node = n.get_child(0) if n.get_child_count() > 0 else null
			if model != null:
				made += attach(n as Node3D, model, int(n.get_meta("wid", 0)), world_seed())


func world_seed() -> int:
	return world.seed_value if world != null else 0


## Adds the containers of `model`'s spawn empties under `parent` (a POI / building node). Returns how many.
## M6b: `remap` = the building use's loot tables ({template table: table}, "*" = every table; a bar's shelves roll
## the bar table, a village shop's the shop table).
static func attach(parent: Node3D, model: Node, parent_wid: int, seed_v: int, remap: Dictionary = {}) -> int:
	var spawns: Array[Node3D] = []
	for s in model.find_children("Spawn_*", "Node3D", true, false):
		var nm := String(s.name)
		if nm.begins_with("Spawn_Container_") or nm.begins_with("Spawn_Loot_"):
			spawns.append(s as Node3D)
	spawns.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name) < String(b.name))
	var n := 0
	for i in spawns.size():
		var s := spawns[i]
		var loose := String(s.name).begins_with("Spawn_Loot_")
		var extras: Dictionary = s.get_meta("extras", {}) if s.has_meta("extras") else {}
		var table := StringName(str(extras.get("table", "loose" if loose else "campsite")))
		if not remap.is_empty() and not loose:
			table = StringName(str(remap.get(String(table), remap.get("*", String(table)))))
		var c := LootContainer.new()
		c.setup(WorldConst.hash64(seed_v, Loot.GEN_LOOT, parent_wid, i + 1), table, loose)
		var xf := parent.global_transform.affine_inverse() * s.global_transform if parent.is_inside_tree() and s.is_inside_tree() \
			else _relative(parent, s)
		c.transform = Transform3D(Basis(Vector3.UP, xf.basis.get_euler().y), xf.origin)
		parent.add_child(c)
		n += 1
	return n


## Transform of `node` relative to `ancestor` (both may be outside the tree).
static func _relative(ancestor: Node, node: Node3D) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p != null and p != ancestor:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
