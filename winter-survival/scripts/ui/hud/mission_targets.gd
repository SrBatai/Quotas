class_name MissionTargets
## Resolves the world targets of a mission step on the client (`Missions` anchors):
##   {"pos": Vector3}          an explicit position
##   "group:<group>"           the nodes of a scene group (the cabin's stove, the cabinet…)
##   "pickup:<item id>"        visible ground pickups of that item within MAX_RANGE
##   "zone:<location id>"      the centre of a named place (`Locations`)
## Only nodes within MAX_RANGE of `from` are returned (markers are drawn up to 300 m, §V.3).

const MAX_RANGE := 300.0
const MAX_RESULTS := 8


static func resolve(t: Dictionary, from: Vector3, tree: SceneTree) -> Array:
	var out: Array = []
	if t.has("pos"):
		out.append(t["pos"])
		return out
	var anchor := str(t.get("anchor", ""))
	var sep := anchor.find(":")
	if sep < 0 or tree == null:
		return out
	var kind := anchor.substr(0, sep)
	var arg := anchor.substr(sep + 1)
	match kind:
		"group":
			for n in tree.get_nodes_in_group(arg):
				if n is Node3D and (n as Node3D).is_visible_in_tree():
					_add(out, (n as Node3D).global_position, from)
		"pickup":
			for n in tree.get_nodes_in_group("pickup"):
				if n is Node3D and str(n.get("item_id")) == arg and bool(n.get("enabled")) and not n.is_queued_for_deletion():
					_add(out, (n as Node3D).global_position, from)
		"zone":
			var e := Locations.by_id(arg)
			if not e.is_empty():
				var shape: Dictionary = e["shape"]
				var c: Vector2 = shape["circle"][0] if shape.has("circle") else (shape["rect"][0] if shape.has("rect") else Vector2.ZERO)
				out.append(Vector3(c.x, from.y, c.y))
	return out


static func _add(out: Array, p: Vector3, from: Vector3) -> void:
	if out.size() < MAX_RESULTS * 4 and Vector2(p.x - from.x, p.z - from.z).length() <= MAX_RANGE:
		out.append(p)
