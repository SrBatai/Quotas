class_name WorldRegistry
## Stable object ids (`wid`) for RPCs (ARQ v2 §8.7, M1 version). The id is the hash of the node path relative
## to the World node: deterministic because the world is generated from the seed with deterministic names on
## both sides (Scatter names its children by index, spawned nodes carry the server's name). M3 replaces this by
## the 64-bit `hash64(seed, chunk, generator, index)`.

static var _by_wid: Dictionary = {}


static func reset() -> void:
	_by_wid.clear()


static func key_of(node: Node) -> String:
	var world := node.get_tree().get_first_node_in_group("world") if node.is_inside_tree() else null
	if world != null and world.is_ancestor_of(node):
		return String(world.get_path_to(node))
	return String(node.get_path())


static func register(node: Node) -> int:
	if node.has_meta("wid"):
		return int(node.get_meta("wid"))
	var key := key_of(node)
	var wid := key.hash()
	if _by_wid.has(wid) and _by_wid[wid] != node and is_instance_valid(_by_wid[wid]):
		push_warning("WorldRegistry: wid collision for %s" % key)
	_by_wid[wid] = node
	node.set_meta("wid", wid)
	node.tree_exited.connect(func() -> void:
		if _by_wid.get(wid) == node:
			_by_wid.erase(wid))
	return wid


static func wid_of(node: Node) -> int:
	if node == null:
		return 0
	if node.has_meta("wid"):
		return int(node.get_meta("wid"))
	return register(node)


static func get_object(wid: int) -> Node:
	var n: Variant = _by_wid.get(wid)
	if n is Node and is_instance_valid(n):
		return n
	return null
