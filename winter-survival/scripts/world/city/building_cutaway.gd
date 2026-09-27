class_name BuildingCutaway
extends Node
## Client cutaway for buildings with the v2 cut-group structure (ASSET_SPEC v2 §8.4 / M3.5: `Floor<k>`,
## `Walls<k>_{N,S,E,W}` + `_Stub`, `Interior<k>`, `Roof`, `Door_n` / `Window_n` with extras `cut_group`). Stubs are
## hidden while the full walls show; when the local player stands inside floor k's footprint the roof (and the
## floors above) hide and every wall of floor k that faces the camera is swapped for its stub together with the
## doors / windows of its group. Shared by the forest POIs (PoiCutaway, `HideMode.VISIBLE`: `visible = false`,
## exactly the M3 behaviour) and the enterable parts of city buildings (CityBuilding, `HideMode.SHADOW`: hidden
## groups keep casting their shadow, so the interior stays dark: doc 09 §3.1 layer E — a roof that neither draws
## nor casts would light the room with sun).

enum HideMode { VISIBLE, SHADOW }

const DIR_NORMAL := {"N": Vector3(0, 0, -1), "S": Vector3(0, 0, 1), "E": Vector3(1, 0, 0), "W": Vector3(-1, 0, 0)}
const META_CAST := &"_cut_cast"

signal floor_changed(floor: int)

var hide_mode: int = HideMode.VISIBLE
var active_floor: int = -1
## Seconds between two polls of the local player's position.
var poll_period: float = 0.2
## Tests / bench: the player to follow instead of GameFlow.local_player().
var player_override: Node3D
var _model: Node3D
var _walls: Array[Dictionary] = []      # {floor, node, stub, normal, openings: Array[Node3D]}
var _roof: Node3D
var _floor_z: Dictionary = {}           # floor index -> walkable height (model space)
var _above: Dictionary = {}             # floor index -> nodes of the floors above (Floor/Interior/Walls of k+1…)
var _foot := AABB()
var _hidden: Dictionary = {}            # Node3D -> true while cut away
var _t: float = 0.0


static func _extras(n: Node) -> Dictionary:
	var e: Variant = n.get_meta("extras", {})
	return e if e is Dictionary else {}


## True when `model` has at least one `Walls*` cut group as a direct child.
static func has_cut_groups(model: Node) -> bool:
	for c in model.get_children():
		if String(c.name).begins_with("Walls"):
			return true
	return false


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
			if hide_mode == HideMode.SHADOW:
				for gi in _geometries(c):
					gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # the full wall keeps casting
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


func _player() -> Node3D:
	if player_override != null:
		return player_override if is_instance_valid(player_override) else null
	return GameFlow.local_player() as Node3D


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or _model == null or not _model.is_inside_tree():
		return
	_t = poll_period
	var lp := _player()
	var inside := floor_at(lp.global_position) if lp != null else -1
	if inside != active_floor:
		active_floor = inside
		_apply(inside)
		floor_changed.emit(inside)


## Floor (cut-group index) whose footprint and height band contain the world point `p`, or -1.
func floor_at(p_world: Vector3) -> int:
	if _model == null or not _model.is_inside_tree():
		return -1
	var p := _model.global_transform.affine_inverse() * p_world
	var inside := -1
	if p.x > _foot.position.x + 0.1 and p.x < _foot.end.x - 0.1 and p.z > _foot.position.z + 0.1 and p.z < _foot.end.z - 0.1:
		for fl in _floor_z:
			var z: float = _floor_z[fl]
			if p.y > z - 0.6 and p.y < z + 2.8 and _has_walls(int(fl)):
				inside = int(fl)
	return inside


func _has_walls(fl: int) -> bool:
	for w in _walls:
		if int(w["floor"]) == fl:
			return true
	return false


## Re-applies the cut for floor `fl` (-1 = outside: everything shown). Called on floor change and camera yaw.
func apply_floor(fl: int) -> void:
	active_floor = fl
	_apply(fl)


func _apply(fl: int) -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var to_cam := Vector3.BACK
	if cam != null:
		to_cam = cam.global_position - _model.global_position
		to_cam.y = 0.0
		to_cam = (_model.global_basis.inverse() * to_cam.normalized()) if to_cam.length() > 0.01 else Vector3.BACK
	if _roof != null:
		_show(_roof, fl < 0)
	for k in _above:
		for n in _above[k]:
			_show(n as Node3D, true)
	if fl >= 0 and _above.has(fl):
		for n in _above[fl]:
			_show(n as Node3D, false)
	for w in _walls:
		var cut: bool = fl >= 0 and int(w["floor"]) == fl and (w["normal"] as Vector3).dot(to_cam) > 0.15
		var shown: bool = not cut and not (fl >= 0 and int(w["floor"]) > fl)
		_show(w["node"] as Node3D, shown)
		if w["stub"] != null:
			(w["stub"] as Node3D).visible = cut
		for o in w["openings"]:
			_show(o as Node3D, shown)


## Shows / cuts one group. VISIBLE: `visible`. SHADOW: drawn normally, or (cut) SHADOWS_ONLY where the geometry
## cast a shadow and invisible where it did not (a proxy casts for it); the original setting is restored after.
func _show(n: Node3D, shown: bool) -> void:
	if n == null:
		return
	_hidden[n] = not shown
	if hide_mode == HideMode.VISIBLE:
		n.visible = shown
		return
	n.visible = true
	for gi in _geometries(n):
		if not gi.has_meta(META_CAST):
			gi.set_meta(META_CAST, gi.cast_shadow)
		var orig: int = int(gi.get_meta(META_CAST))
		if shown:
			gi.cast_shadow = orig as GeometryInstance3D.ShadowCastingSetting
			gi.visible = true
		elif orig == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			gi.visible = false
		else:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			gi.visible = true


## True while `n` (a cut group or opening) is cut away (hidden or shadow-only).
func is_cut_away(n: Node) -> bool:
	return bool(_hidden.get(n, false))


func is_group_cut(group: String) -> bool:
	for w in _walls:
		if String((w["node"] as Node).name) == group:
			return is_cut_away(w["node"])
	return false


static func _geometries(root: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if root is GeometryInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_geometries(c))
	return out
