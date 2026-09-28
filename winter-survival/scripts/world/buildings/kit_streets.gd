class_name KitStreets
extends Node
## World placement of the kit streets (M6a; ARQ v2 §9.9), like LootSpawns for the POI containers: one node per game
## (server and client flavours), hooked to WorldStreamer.chunk_loaded. When the chunk that contains a street's centre
## finishes loading, a KitStreet is built under that chunk's `objects` node (so it unloads with it); deterministic
## wids (street / building / door / container) make every peer build the same street without replicating a node.
## The street data files live in res://data/buildings/streets/ (M6a: calle_mayor = the test street of Santa María
## del Puerto, on the W1 reserved pad `santa_maria_del_puerto`, whose flat ground and clear scatter already exist).

const DIR := "res://data/buildings/streets/"

static var instance: KitStreets

var world: World
var streets: Array[Dictionary] = []
var live: Dictionary = {}       # street id -> KitStreet
## Tests / stats.
var built: int = 0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func load_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	var files: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			files.append(f)
		f = dir.get_next()
	files.sort()
	for fn in files:
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + fn))
		if v is Dictionary:
			out.append(v)
	return out


static func by_id(id: String) -> Dictionary:
	for s in load_all():
		if str(s.get("id", "")) == id:
			return s
	return {}


static func centre_of(s: Dictionary) -> Vector3:
	var c: Array = s.get("center", [0.0, 0.0])
	return Vector3(float(c[0]), 0.0, float(c[1]))


func setup(p_world: World) -> void:
	world = p_world
	streets = load_all()
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
	for s in streets:
		var id := str(s.get("id", ""))
		if live.has(id) and is_instance_valid(live[id]):
			continue
		if WorldConst.key_of(centre_of(s)) != key:
			continue
		var c: WorldChunk = world.streamer.chunks.get(key)
		if c == null or c.objects == null:
			continue
		spawn(c.objects, s)


## Builds street `s` under `parent` (a chunk's objects node, or a test root). Returns the KitStreet.
func spawn(parent: Node3D, s: Dictionary) -> KitStreet:
	var id := str(s.get("id", ""))
	var centre := centre_of(s)
	var st := KitStreet.new()
	st.setup(s, world.seed_value if world != null else 0, world.get_height(centre.x, centre.z) if world != null else 0.0)
	parent.add_child(st)
	live[id] = st
	built += 1
	st.tree_exiting.connect(func() -> void:
		if live.get(id) == st:
			live.erase(id), CONNECT_ONE_SHOT)
	return st


static func street(id: String) -> KitStreet:
	if instance == null:
		return null
	var st: Variant = instance.live.get(id)
	return st if st is KitStreet and is_instance_valid(st) else null
