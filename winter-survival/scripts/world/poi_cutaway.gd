class_name PoiCutaway
extends Node
## Client cutaway for buildings with the v2 cut-group structure (ASSET_SPEC v2 §8.4 / M3.5: `Floor<k>`,
## `Walls<k>_{N,S,E,W}` + `_Stub`, `Interior<k>`, `Roof`, `Door_n` / `Window_n` with extras `cut_group`), used by
## the M3 forest POIs (cabin_small, lookout_tower) until M6a's CutawayManager. Stubs are hidden while the full walls
## show; when the local player stands inside floor k's footprint the roof (and the floors above) hide and every
## wall of floor k that faces the camera is swapped for its stub together with the doors / windows of its group.

const DIR_NORMAL := {"N": Vector3(0, 0, -1), "S": Vector3(0, 0, 1), "E": Vector3(1, 0, 0), "W": Vector3(-1, 0, 0)}

var active_floor: int = -1
var _model: Node3D
var _walls: Array[Dictionary] = []      # {floor, node, stub, normal, openings: Array[Node3D]}
var _roof: Node3D
var _floor_z: Dictionary = {}           # floor index -> walkable height (model space)
var _above: Dictionary = {}             # floor index -> nodes of the floors above (Floor/Interior/Walls of k+1…)
var _foot := AABB()
var _t: float = 0.0


## Returns null when the model has no cut groups.
static func attach(host: Node3D, model: Node3D) -> PoiCutaway:
	var has_walls := false
	for c in model.get_children():
		if String(c.name).begins_with("Walls"):
			has_walls = true
			break
	if not has_walls:
		return null
	var cut := PoiCutaway.new()
	cut.name = "Cutaway"
	host.add_child(cut)
	cut.setup(model)
	return cut


static func _extras(n: Node) -> Dictionary:
	var e: Variant = n.get_meta("extras", {})
	return e if e is Dictionary else {}


func setup(model: Node3D) -> void:
	_model = model
	var by_group := {}
	var stubs := {}
	var openings := {}
	var nodes_by_floor := {}
	for c in model.get_children():
		if not (c is Node3D):
			continue
		var n := String(c.name)
		var ex := _extras(c)
		var fl := int(ex.get("floor", 0))
		if n == "Roof":
			_roof = c
		elif n.begins_with("Floor"):
			_floor_z[fl] = float(ex.get("floor_z", 0.0))
			_add_floor_node(nodes_by_floor, fl, c)
		elif n.begins_with("Interior"):
			_add_floor_node(nodes_by_floor, fl, c)
		elif n.begins_with("Walls") and n.ends_with("_Stub"):
			stubs[n.trim_suffix("_Stub")] = c
			(c as Node3D).visible = false
		elif n.begins_with("Walls"):
			by_group[n] = {"floor": fl, "node": c, "normal": DIR_NORMAL.get(n.get_slice("_", 1), Vector3.ZERO), "openings": []}
			_add_floor_node(nodes_by_floor, fl, c)
			if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
				var bb := (c as Node3D).transform * (c as MeshInstance3D).get_aabb()
				_foot = bb if _foot.size == Vector3.ZERO else _foot.merge(bb)
		elif n.begins_with("Door_") or n.begins_with("Window_"):
			var g := str(ex.get("cut_group", ""))
			if not openings.has(g):
				openings[g] = []
			(openings[g] as Array).append(c)
	for g in by_group:
		var w: Dictionary = by_group[g]
		w["stub"] = stubs.get(g)
		w["openings"] = openings.get(g, [])
		_walls.append(w)
	for fl in nodes_by_floor:
		var above: Array = []
		for other in nodes_by_floor:
			if int(other) > int(fl):
				above.append_array(nodes_by_floor[other])
		_above[fl] = above
	Events.camera_yaw_changed.connect(func(_y: float) -> void:
		if active_floor >= 0:
			_apply(active_floor))


func _add_floor_node(d: Dictionary, fl: int, n: Node) -> void:
	if not d.has(fl):
		d[fl] = []
	(d[fl] as Array).append(n)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or _model == null or not _model.is_inside_tree():
		return
	_t = 0.2
	var lp := GameFlow.local_player() as Node3D
	var inside := -1
	if lp != null:
		var p := _model.global_transform.affine_inverse() * lp.global_position
		if p.x > _foot.position.x + 0.1 and p.x < _foot.end.x - 0.1 and p.z > _foot.position.z + 0.1 and p.z < _foot.end.z - 0.1:
			for fl in _floor_z:
				var z: float = _floor_z[fl]
				if p.y > z - 0.6 and p.y < z + 2.8 and _has_walls(int(fl)):
					inside = int(fl)
	if inside != active_floor:
		active_floor = inside
		_apply(inside)


func _has_walls(fl: int) -> bool:
	for w in _walls:
		if int(w["floor"]) == fl:
			return true
	return false


func _apply(fl: int) -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var to_cam := Vector3.BACK
	if cam != null:
		to_cam = cam.global_position - _model.global_position
		to_cam.y = 0.0
		to_cam = (_model.global_basis.inverse() * to_cam.normalized()) if to_cam.length() > 0.01 else Vector3.BACK
	if _roof != null:
		_roof.visible = fl < 0
	for k in _above:
		for n in _above[k]:
			(n as Node3D).visible = true
	if fl >= 0 and _above.has(fl):
		for n in _above[fl]:
			(n as Node3D).visible = false
	for w in _walls:
		var cut: bool = fl >= 0 and int(w["floor"]) == fl and (w["normal"] as Vector3).dot(to_cam) > 0.15
		(w["node"] as Node3D).visible = not cut and not (fl >= 0 and int(w["floor"]) > fl)
		if w["stub"] != null:
			(w["stub"] as Node3D).visible = cut
		for o in w["openings"]:
			(o as Node3D).visible = (w["node"] as Node3D).visible


func is_group_cut(group: String) -> bool:
	for w in _walls:
		if String((w["node"] as Node).name) == group:
			return not (w["node"] as Node3D).visible
	return false
