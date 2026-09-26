class_name WorldRegistry
## Stable object ids (`wid`) for RPCs (ARQ v2 §8.7). Two id spaces:
##  - procedural objects of the streamed world (scatter trees, pickups, berry bushes, POI props): the 63-bit
##    `WorldConst.hash64(seed, generator, cell / index, …)`, set as the node's "wid" meta by the chunk that
##    creates it (identical on every peer, independent of node paths and of which chunks are loaded);
##  - hand-placed nodes (the clearing POI: cabin, stove, cabinet…) and spawner-replicated ones (drops, placed
##    structures): the hash of the node path relative to the World node (deterministic names on both sides).
## `get_object(wid)` only returns live nodes; `resolve(wid)` also materializes a choppable scatter entry of a
## loaded chunk (the MultiMesh tree becomes a real ChoppableTree only when it is needed: request, event).

static var _by_wid: Dictionary = {}
## World.materialize_wid while a world is configured.
static var materializer: Callable = Callable()


static func reset() -> void:
	_by_wid.clear()


static func key_of(node: Node) -> String:
	var world := node.get_tree().get_first_node_in_group("world") if node.is_inside_tree() else null
	if world != null and world.is_ancestor_of(node):
		return String(world.get_path_to(node))
	return String(node.get_path())


static func register(node: Node) -> int:
	var wid: int
	if node.has_meta("wid"):
		wid = int(node.get_meta("wid"))
		if _by_wid.get(wid) == node:
			return wid
	else:
		wid = key_of(node).hash()
		node.set_meta("wid", wid)
	if _by_wid.has(wid) and _by_wid[wid] != node and is_instance_valid(_by_wid[wid]):
		push_warning("WorldRegistry: wid collision for %s" % key_of(node))
	_by_wid[wid] = node
	node.tree_exited.connect(func() -> void:
		if _by_wid.get(wid) == node:
			_by_wid.erase(wid), CONNECT_ONE_SHOT)
	return wid


## Drops a node's id at once. A chunk being unloaded frees its nodes over several frames and they stay valid until
## then: a reload of the same chunk in the meantime must get the ids (hidden, inert nodes must not answer requests).
static func unregister(node: Node) -> void:
	if node.has_meta("wid"):
		var wid := int(node.get_meta("wid"))
		if _by_wid.get(wid) == node:
			_by_wid.erase(wid)


static func wid_of(node: Node) -> int:
	if node == null:
		return 0
	if node.has_meta("wid"):
		var wid := int(node.get_meta("wid"))
		if not _by_wid.has(wid) and node.is_inside_tree():
			register(node)
		return wid
	return register(node)


static func get_object(wid: int) -> Node:
	var n: Variant = _by_wid.get(wid)
	if n is Node and is_instance_valid(n):
		return n
	return null


## Live node, or the materialized scatter entry of a loaded chunk (server requests, live events).
static func resolve(wid: int) -> Node:
	var n := get_object(wid)
	if n != null:
		return n
	if materializer.is_valid():
		return materializer.call(wid)
	return null
