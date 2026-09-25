class_name DropSpawner
extends MultiplayerSpawner
## /root/Game/DropSpawner: ground items that did not exist in the seeded world (wolf/deer drops, crafting
## overflow, dawn respawns) are spawned by the server under World/Drops and replicated by this spawner
## (ARQ v2 §6.4 "Drops", M2 spawner version of DROP_ADD/DROP_REMOVE). Each drop is recorded in its ChunkDelta
## (`drops` table) so a save restores it.

const PICKUP_SCENE := preload("res://scenes/world/pickup.tscn")

static var instance: DropSpawner

var _counter: int = 0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	spawn_function = _spawn_node


func drops_root() -> Node:
	return get_node_or_null(spawn_path)


## Server: spawns a replicated ground item. Returns the node (null on a client).
func spawn_drop(item_id: StringName, model: String, pos: Vector3, amount: int = 1, restore_name: String = "") -> Node3D:
	if not Net.is_server:
		return null
	var drop_name := restore_name
	if drop_name == "":
		_counter += 1
		drop_name = "drop_%d" % _counter
	else:
		_counter = maxi(_counter, int(drop_name.trim_prefix("drop_")))
	var data := {"name": drop_name, "item": String(item_id), "model": model,
		"x": pos.x, "y": pos.y, "z": pos.z, "amount": amount, "yaw": randf() * TAU}
	var node: Node3D
	if multiplayer.multiplayer_peer == null or multiplayer.get_peers().is_empty():
		node = _spawn_node(data)
		drops_root().add_child(node)
	else:
		node = spawn(data)
	if NetWorld.instance != null:
		NetWorld.instance.register_drop(WorldRegistry.wid_of(node), data)
	return node


## spawn_function (server and clients).
func _spawn_node(data: Variant) -> Node:
	var d: Dictionary = data
	var p: Pickup = PICKUP_SCENE.instantiate()
	p.name = str(d["name"])
	p.item_id = StringName(str(d["item"]))
	p.model = str(d["model"])
	p.amount = int(d.get("amount", 1))
	p.position = Vector3(float(d["x"]), float(d["y"]), float(d["z"]))
	p.rotation.y = float(d.get("yaw", 0.0))
	return p


## Server: restores the drops of a loaded chunk delta.
func restore(entries: Dictionary) -> void:
	for wid in entries:
		var e: Dictionary = entries[wid]
		var root := drops_root()
		if root != null and root.get_node_or_null(str(e.get("name", ""))) != null:
			continue
		spawn_drop(StringName(str(e.get("item", "madera"))), str(e.get("model", "firewood")),
			Vector3(float(e.get("x", 0.0)), float(e.get("y", 0.0)), float(e.get("z", 0.0))), int(e.get("amount", 1)),
			str(e.get("name", "")))
