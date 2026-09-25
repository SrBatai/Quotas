class_name StructureSpawner
extends MultiplayerSpawner
## /root/Game/PlacedSpawner: structures placed by players (campfire; tent / box in P2) spawned by the server
## under World/Placed and replicated by this spawner (ARQ v2 §6.4 "Estructura colocada"). The placement is
## recorded in the ChunkDelta `structures` table; the structure's own fields (lit, fuel) travel as object deltas.

const CAMPFIRE_SCENE := preload("res://scenes/world/campfire.tscn")

static var instance: StructureSpawner

var _counter: int = 0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	spawn_function = _spawn_node


func placed_root() -> Node:
	return get_node_or_null(spawn_path)


## Server: spawns a replicated placed structure. Returns the node (null on a client).
func spawn_structure(kind: String, pos: Vector3, yaw: float, restore_name: String = "") -> Node3D:
	if not Net.is_server:
		return null
	var node_name := restore_name
	if node_name == "":
		_counter += 1
		node_name = "%s_%d" % [kind, _counter]
	else:
		_counter = maxi(_counter, int(node_name.get_slice("_", node_name.get_slice_count("_") - 1)))
	var data := {"name": node_name, "kind": kind, "x": pos.x, "y": pos.y, "z": pos.z, "yaw": yaw}
	var node: Node3D
	if multiplayer.multiplayer_peer == null or multiplayer.get_peers().is_empty():
		node = _spawn_node(data)
		placed_root().add_child(node)
	else:
		node = spawn(data)
	if NetWorld.instance != null:
		NetWorld.instance.register_structure(WorldRegistry.wid_of(node), data)
	return node


## spawn_function (server and clients).
func _spawn_node(data: Variant) -> Node:
	var d: Dictionary = data
	var node: Node3D
	if str(d["kind"]) == "campfire":
		node = CAMPFIRE_SCENE.instantiate()
	else:
		node = Node3D.new()
		node.add_child(Assets.spawn_model(str(d["kind"])))
	node.name = str(d["name"])
	node.position = Vector3(float(d["x"]), float(d["y"]), float(d["z"]))
	node.rotation.y = float(d.get("yaw", 0.0))
	return node


## Server: restores the structures of a loaded chunk delta (their object fields are applied by NetWorld).
func restore(entries: Dictionary) -> void:
	for wid in entries:
		var e: Dictionary = entries[wid]
		var root := placed_root()
		if root != null and root.get_node_or_null(str(e.get("name", ""))) != null:
			continue
		spawn_structure(str(e.get("kind", "campfire")), Vector3(float(e.get("x", 0.0)), float(e.get("y", 0.0)), float(e.get("z", 0.0))),
			float(e.get("yaw", 0.0)), str(e.get("name", "")))
