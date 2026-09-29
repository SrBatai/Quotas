class_name SettlementChunk
extends Node3D
## The M6b site pieces of one streamed chunk (Settlements.items_in_chunk), built by SettlementSpawner over a few
## frames (≤ FRAME_BUDGET_USEC of work per frame, a building alone in its frame). Every piece becomes a direct child
## of the chunk's `objects` node (this node's parent), so the chunk teardown frees them one by one:
##   * one StaticBody3D with the collision boxes / cylinders of every prop, fence, lamp, pole, car and dumpster
##     (layer world + placement blocker, group `nav_static`: the server's NavBaker carves them);
##   * clients with a display: one MultiMeshInstance3D per prop model (the art merged into one surface with the
##     corte urbano capsule material, like the city's props), the car wrecks (A1, `city/vehicles/<model>_<variant>`),
##     the diegetic signs (SignText), the power-line wires (one mesh) and the lamps (VillageLights: light pools and
##     bulb halos everywhere, a few real lights near the camera in Forward+);
##   * KitBuildings of the site buildings (template × style, number / shop sign, locked doors when not enterable,
##     the alarm of shops, loot tables by use), cars' and dumpsters' loot containers (hidden: the prop is the look);
##   * server: the chunk's navmesh is marked dirty once the buildings stand.

const LAYER := 65
const FRAME_BUDGET_USEC := 2500
const VILLAGE_MANIFEST := "res://assets/models/props/village/manifest.json"
const CITY_MANIFEST := "res://assets/models/city/manifest.json"
const WIRE_COLOR := Color(0.13, 0.14, 0.16)
const WIRE_SAG := 0.55
## Props lower than this cast no shadow (C31 / ASSET_SPEC §14).
const SMALL_PROP := 1.0

static var _meshes: Dictionary = {}
## One budget for all the site chunks of a frame (several chunks load together at vehicle speed): ≤ FRAME_BUDGET_USEC
## of work and at most one building per frame, whatever the number of chunks building.
static var _budget_frame: int = -1
static var _budget_used: int = 0
static var _budget_building: bool = false
## Work done since the last take_usec() (perf walk m6b: the village's share of each frame).
static var _acc_usec: int = 0
static var usec_max: int = 0
## Slowest step of each kind so far, µs (perf walk report).
static var step_max: Dictionary = {}
static var _village: Dictionary = {}
static var _city: Dictionary = {}
static var _manifests_loaded: bool = false

var key: int = 0
var items: Array = []
var seed_v: int = 0
var world: World
var spawner: SettlementSpawner
var buildings: Array[KitBuilding] = []
var containers: Array[LootContainer] = []
var pieces: Array[Node] = []
var done: bool = false
var visual: bool = true
var _steps: Array = []            # [kind, arg]
var _i: int = 0
var _lamps: Array = []
var _lamps_added: bool = false


func setup(p_key: int, p_items: Array, p_seed: int, p_world: World, p_spawner: SettlementSpawner) -> void:
	key = p_key
	items = p_items
	seed_v = p_seed
	world = p_world
	spawner = p_spawner
	visual = KitBuilding.visual()
	name = "Settlement_%d_%d" % [WorldConst.key_cx(key), WorldConst.key_cz(key)]
	_steps.clear()
	var groups := {}
	var group_order: Array = []
	var has_col := false
	for i in items.size():
		var e: Dictionary = items[i]
		match str(e["k"]):
			"building":
				_steps.append(["building", i])
			"car":
				_steps.append(["car", i])
				has_col = true
			"sign":
				if visual:
					_steps.append(["sign", i])
			_:
				has_col = true
				var m := str(e["model"])
				if not groups.has(m):
					groups[m] = []
					group_order.append(m)
				(groups[m] as Array).append(i)
				if str(e["k"]) == "container":
					_steps.append(["container", i])
				if str(e["k"]) == "lamp":
					_lamps.append(i)
	if has_col:
		_steps.push_front(["cols", null])
	if visual:
		group_order.sort()
		for m in group_order:
			_steps.append(["mm", [m, groups[m]]])
		_steps.append(["wires", null])
		if not _lamps.is_empty():
			_steps.append(["lamps", null])
	_steps.append(["nav", null])


func _ready() -> void:
	add_to_group("settlement_chunk")


func _process(_delta: float) -> void:
	if done:
		set_process(false)
		return
	var f := Engine.get_process_frames()
	if f != _budget_frame:
		_budget_frame = f
		_budget_used = 0
		_budget_building = false
	if _budget_building or _budget_used >= FRAME_BUDGET_USEC:
		return
	var t0 := Time.get_ticks_usec()
	var n := 0
	# tools (perf walk --cpu, WorldStreamer.sched_probe): the stats count work time, not the run-queue wait of the
	# main thread (preempted by other processes on a shared box); the budget itself runs on wall time
	var probe := WorldStreamer.sched_probe
	var work := 0
	while not done and _budget_used + Time.get_ticks_usec() - t0 < FRAME_BUDGET_USEC:
		var kind := _next_kind()
		var heavy := kind == "building"
		if heavy and (n > 0 or _budget_used > 0):
			break
		var ts := Time.get_ticks_usec()
		var w0 := SchedProbe.wait_ns() if probe else 0
		_step()
		var du := Time.get_ticks_usec() - ts
		if probe:
			du = maxi(du - int((SchedProbe.wait_ns() - w0) / 1000), 0)
		work += du
		if du > int(step_max.get(kind, 0)):
			step_max[kind] = du
		n += 1
		if heavy:
			_budget_building = true
			break
	_budget_used += Time.get_ticks_usec() - t0
	_acc_usec += work
	usec_max = maxi(usec_max, work)


## The site chunks' work since the previous call, µs (perf walk: called once a frame).
static func take_usec() -> int:
	var u := _acc_usec
	_acc_usec = 0
	return u


## Builds everything now (tests, screenshots).
func build_all() -> void:
	while not done:
		_step()


func _next_kind() -> String:
	return str(_steps[_i][0]) if _i < _steps.size() else "done"


func _holder() -> Node3D:
	var p := get_parent() as Node3D
	return p if p != null else self


func _add(n: Node) -> void:
	_holder().add_child(n)
	pieces.append(n)


func _h(p: Vector2) -> float:
	return world.get_height(p.x, p.y) if world != null and world.is_configured else 0.0


func _step() -> void:
	if _i >= _steps.size():
		_finish()
		return
	var s: Array = _steps[_i]
	_i += 1
	match str(s[0]):
		"cols":
			_colliders()
		"building":
			_building(items[int(s[1])])
		"car":
			_car(items[int(s[1])])
		"container":
			_container(items[int(s[1])])
		"sign":
			_sign(items[int(s[1])])
		"mm":
			_multimesh(str(s[1][0]), s[1][1])
		"wires":
			_wires()
		"lamps":
			_add_lamps()
		"nav":
			_nav()
	if _i >= _steps.size():
		_finish()


func _finish() -> void:
	if done:
		return
	done = true
	set_process(false)
	if OS.is_stdout_verbose():
		print("[SETTLEMENT] chunk (%d, %d): %d buildings, %d items" % [WorldConst.key_cx(key), WorldConst.key_cz(key), buildings.size(), items.size() - buildings.size()])


## The chunk unloads (SettlementSpawner): doors / containers leave the registry at once, the lamps leave the lights.
func release() -> void:
	if _lamps_added and spawner != null and spawner.lights != null:
		spawner.lights.remove_lamps(key)
		_lamps_added = false
	for b in buildings:
		if is_instance_valid(b):
			for d in b.doors:
				WorldRegistry.unregister(d)
			for c in b.find_children("loot_*", "LootContainer", true, false):
				WorldRegistry.unregister(c)
	for c in containers:
		if is_instance_valid(c):
			WorldRegistry.unregister(c)


func _exit_tree() -> void:
	release()


# ------------------------------------------------------------------ model data (manifests of the art)
static func _load_manifests() -> void:
	if _manifests_loaded:
		return
	_manifests_loaded = true
	for pair in [[VILLAGE_MANIFEST, "v"], [CITY_MANIFEST, "c"]]:
		if FileAccess.file_exists(str(pair[0])):
			var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(pair[0])))
			if v is Dictionary:
				if str(pair[1]) == "v":
					_village = v
				else:
					_city = (v as Dictionary).get("assets", {})


static func _v3(a: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## {col: "box" | "cylinder" | "", center, size (Vector3), anchors {name: Vector3}, height} of a model path
## ("props/village/<id>", "city/props/<id>", "city/vehicles/<id>"), from the art manifests (model space, +Z front).
static func info(model: String) -> Dictionary:
	_load_manifests()
	var id := model.get_file()
	var out := {"col": "", "center": Vector3.ZERO, "size": Vector3.ZERO, "anchors": {}, "height": 1.0, "cols": []}
	var rec: Dictionary = {}
	if model.begins_with("city/"):
		rec = _city.get(id, {})
		if model.begins_with("city/vehicles/"):
			var sz: Array = (rec.get("build", {}) as Dictionary).get("size_m", [1.8, 4.5, 1.5])
			out["col"] = "box"
			out["size"] = Vector3(float(sz[0]), float(sz[2]), float(sz[1]))
			out["center"] = Vector3(0.0, float(sz[2]) * 0.5, 0.0)
			out["height"] = float(sz[2])
			var an := {}
			for nn in (rec.get("nodes", {}) as Dictionary):
				var nd: Dictionary = rec["nodes"][nn]
				if nd.has("anchor"):
					an[str(nn)] = _v3(nd["anchor"])
			out["anchors"] = an
			return out
		var cd: Dictionary = rec.get("col", {})
		rec = {"col": cd.get("col", ""), "col_center": cd.get("col_center", []), "col_size": cd.get("col_size", []), "anchors": rec.get("anchors", {})}
	else:
		rec = _village.get(id, {})
	var col := str(rec.get("col", ""))
	var cs: Array = rec.get("col_size", [])
	out["col"] = col
	out["center"] = _v3(rec.get("col_center", []))
	if col == "cylinder" and cs.size() >= 2:
		out["size"] = Vector3(float(cs[0]), float(cs[1]), float(cs[0]))
	elif cs.size() >= 3:
		out["size"] = Vector3(float(cs[0]), float(cs[1]), float(cs[2]))
	out["height"] = float(rec.get("height", (out["center"] as Vector3).y + (out["size"] as Vector3).y * 0.5))
	var an2 := {}
	for a in (rec.get("anchors", {}) as Dictionary):
		an2[str(a)] = _v3(rec["anchors"][a])
	out["anchors"] = an2
	# several boxes (the canopy's columns, the bus stop's walls, the saw line and its roof posts): they replace `col`
	var cols: Array = []
	for c in rec.get("cols", []):
		cols.append([_v3(c[0]), _v3(c[1])])
	out["cols"] = cols
	return out


## One mesh per model for the MultiMeshes and the wrecks: every MeshInstance3D of the art merged (transforms baked)
## into surface 0 with the capsule material of the corte urbano (+ surface 1: glass). Cached (main thread).
static func mesh_of(model: String) -> Mesh:
	if _meshes.has(model):
		return _meshes[model]
	var root := Assets.spawn_model(model)
	var solid := SurfaceTool.new()
	solid.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass_mat: Material = null
	var n_solid := 0
	var n_glass := 0
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		for c in (top[0] as Node).get_children():
			if not (c is Node3D) or c is StaticBody3D or c is CollisionShape3D:
				continue
			var cxf: Transform3D = (top[1] as Transform3D) * (c as Node3D).transform
			if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and (c as MeshInstance3D).visible:
				var m := (c as MeshInstance3D).mesh
				for si in m.get_surface_count():
					var mat := m.surface_get_material(si)
					if mat != null and mat.resource_name.to_lower() == "glass":
						glass.append_from(m, si, cxf)
						glass_mat = mat
						n_glass += 1
					else:
						solid.append_from(m, si, cxf)
						n_solid += 1
			stack.append([c, cxf])
	root.free()
	var out: ArrayMesh
	if n_solid == 0:
		out = ArrayMesh.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 1.0, 0.5)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(bm, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
		st.commit(out)
	else:
		out = solid.commit()
	out.surface_set_material(0, CityBuilding.capsule_material())
	if n_glass > 0:
		glass.commit(out)
		out.surface_set_material(1, glass_mat)
	_meshes[model] = out
	return out


## Warms the meshes of every model a seed's sites use (main thread, before streaming reaches them).
static func warm(seed_value: int) -> int:
	var t0 := Time.get_ticks_usec()
	for m in Settlements.models(seed_value):
		var s := str(m)
		if s.begins_with("buildings/") or s.begins_with("signs/"):
			Assets.spawn_model(s).free()
		else:
			mesh_of(s)
	return Time.get_ticks_usec() - t0


static func _xf(e: Dictionary, y: float) -> Transform3D:
	var p: Vector2 = e["pos"]
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(e["yaw"]))), Vector3(p.x, y, p.y))


# ------------------------------------------------------------------ steps
func _colliders() -> void:
	var body := StaticBody3D.new()
	body.name = "SettlementProps_%d_%d" % [WorldConst.key_cx(key), WorldConst.key_cz(key)]
	body.collision_layer = LAYER
	body.collision_mask = 0
	body.add_to_group("nav_static")
	for e: Dictionary in items:
		var k := str(e["k"])
		if k == "building" or k == "sign":
			continue
		var inf := info(str(e["model"]))
		var col := str(inf["col"])
		var size: Vector3 = inf["size"]
		var xf := _xf(e, _h(e["pos"]))
		if not (inf["cols"] as Array).is_empty():
			for c in inf["cols"]:
				var bs := CollisionShape3D.new()
				var bb := BoxShape3D.new()
				bb.size = Vector3(maxf((c[1] as Vector3).x, 0.1), maxf((c[1] as Vector3).y, 0.1), maxf((c[1] as Vector3).z, 0.1))
				bs.shape = bb
				bs.transform = xf * Transform3D(Basis.IDENTITY, c[0])
				body.add_child(bs)
			continue
		if col == "" or size.x <= 0.0:
			continue
		var cs := CollisionShape3D.new()
		if col == "cylinder":
			var cy := CylinderShape3D.new()
			cy.radius = maxf(size.x * 0.5, 0.06)
			cy.height = size.y
			cs.shape = cy
		else:
			var bx := BoxShape3D.new()
			bx.size = Vector3(maxf(size.x, 0.1), maxf(size.y, 0.1), maxf(size.z, 0.1))
			cs.shape = bx
		cs.transform = xf * Transform3D(Basis.IDENTITY, inf["center"])
		body.add_child(cs)
	if body.get_child_count() > 0:
		_add(body)
	else:
		body.free()


func _building(e: Dictionary) -> void:
	var b := KitBuilding.new()
	b.setup(str(e["template"]), str(e["style"]), int(e["wid"]), seed_v, int(e.get("number", 0)), str(e.get("shop", "")))
	b.opts = {"use": str(e["use"]), "locked": not bool(e.get("enterable", true)), "alarm": bool(e.get("alarm", false)),
		"tables": e.get("tables", {})}
	b.set_meta("site", str(e["site"]))
	b.set_meta("index", int(e["index"]))
	b.set_meta("use", str(e["use"]))
	b.transform = _xf(e, _h(e["pos"]))
	_add(b)
	buildings.append(b)
	if spawner != null:
		spawner.buildings_built += 1


func _loot(at: Transform3D, wid: int, table: String) -> LootContainer:
	var c := LootContainer.new()
	c.setup(WorldConst.hash64(seed_v, Loot.GEN_LOOT, wid, 1), StringName(table), false)
	c.hidden_model = true
	c.transform = at
	_add(c)
	containers.append(c)
	return c


func _car(e: Dictionary) -> void:
	var y := _h(e["pos"])
	var xf := _xf(e, y)
	var model := str(e["model"])
	if visual:
		var mi := MeshInstance3D.new()
		mi.name = "Wreck_%x" % (int(e["wid"]) & 0xFFFFFF)
		mi.mesh = mesh_of(model)
		mi.transform = xf
		mi.visibility_range_end = 90.0
		_add(mi)
	var an: Dictionary = info(model)["anchors"]
	var lp: Vector3 = an.get("Loot", Vector3(0.0, 0.8, -2.0))
	# the container sits at the boot, on the ground behind it (the player reaches it from outside the car)
	var at := xf * Transform3D(Basis.IDENTITY, Vector3(lp.x, 0.0, lp.z - 0.55))
	_loot(at, int(e["wid"]), str(e.get("table", "car")))


func _container(e: Dictionary) -> void:
	var y := _h(e["pos"])
	var xf := _xf(e, y)
	var an: Dictionary = info(str(e["model"]))["anchors"]
	var lp: Vector3 = an.get("Loot", Vector3(0.0, 0.0, 0.9))
	_loot(xf * Transform3D(Basis.IDENTITY, Vector3(lp.x, 0.0, lp.z)), int(e["wid"]), str(e.get("table", "dumpster")))


func _sign(e: Dictionary) -> void:
	var xf := _xf(e, _h(e["pos"]))
	var n := SignText.place(_holder(), str(e["model"]), xf, str(e.get("text", "")), str(e.get("back", "")))
	pieces.append(n)


func _multimesh(model: String, idx: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh_of(model)
	mm.instance_count = idx.size()
	for j in idx.size():
		var e: Dictionary = items[int(idx[j])]
		mm.set_instance_transform(j, _xf(e, _h(e["pos"])))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Props_%s" % model.get_file()
	mmi.multimesh = mm
	var h := float(info(model)["height"])
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if h >= SMALL_PROP else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 85.0 if h >= 2.0 else 65.0
	_add(mmi)


## Power lines: two sagging wires per span between the cross-arm ends (anchors WireA / WireB) of consecutive poles.
func _wires() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for e: Dictionary in items:
		if str(e["k"]) != "pole" or not e.has("wire_to"):
			continue
		var pl: Dictionary = Settlements.site(seed_v, str(e["site"]))
		var to: Dictionary = (pl["items"] as Array)[int(e["wire_to"])]
		var an_a: Dictionary = info(str(e["model"]))["anchors"]
		var an_b: Dictionary = info(str(to["model"]))["anchors"]
		var xa := _xf(e, _h(e["pos"]))
		var xb := _xf(to, _h(to["pos"]))
		for wn in ["WireA", "WireB"]:
			var a: Vector3 = xa * (an_a.get(wn, Vector3(0.0, 7.2, 0.0)) as Vector3)
			var b: Vector3 = xb * (an_b.get(wn, Vector3(0.0, 7.2, 0.0)) as Vector3)
			_wire(st, a, b)
			n += 1
	if n == 0:
		return
	var mesh := st.commit()
	mesh.surface_set_material(0, Assets.get_shared_material())
	var mi := MeshInstance3D.new()
	mi.name = "Wires_%d_%d" % [WorldConst.key_cx(key), WorldConst.key_cz(key)]
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 85.0
	_add(mi)


static func _wire(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var segs := 8
	var lin := WIRE_COLOR.srgb_to_linear()
	lin.a = 1.0
	var d := b - a
	var side := Vector3(-d.z, 0.0, d.x).normalized() * 0.02
	var up := Vector3(0.0, 0.025, 0.0)
	for k in segs:
		var t0 := float(k) / float(segs)
		var t1 := float(k + 1) / float(segs)
		var p0 := a.lerp(b, t0) - Vector3(0.0, WIRE_SAG * 4.0 * t0 * (1.0 - t0), 0.0)
		var p1 := a.lerp(b, t1) - Vector3(0.0, WIRE_SAG * 4.0 * t1 * (1.0 - t1), 0.0)
		for off in [side, up]:
			var o: Vector3 = off
			var q := [p0 - o, p1 - o, p1 + o, p0 + o]
			for i in [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]:
				st.set_color(lin)
				st.set_normal(Vector3.UP)
				st.add_vertex(q[i])


func _add_lamps() -> void:
	if spawner == null or spawner.lights == null:
		return
	var list: Array = []
	for i in _lamps:
		var e: Dictionary = items[int(i)]
		var y := _h(e["pos"])
		var xf := _xf(e, y)
		var an: Dictionary = info(str(e["model"]))["anchors"]
		var bulb: Vector3 = xf * (an.get("LightAnchor", Vector3(0.0, 4.6, 1.2)) as Vector3)
		list.append([bulb, y, float(e.get("power", 1.0))])
	spawner.lights.add_lamps(key, list)
	_lamps_added = true


func _nav() -> void:
	if not Net.is_server or NavBaker.instance == null:
		return
	var keys := {key: true}
	for b in buildings:
		var p := b.global_position if b.is_inside_tree() else b.position
		for dx in [-12.0, 12.0]:
			for dz in [-12.0, 12.0]:
				keys[WorldConst.key_of(p + Vector3(dx, 0.0, dz))] = true
	for k in keys:
		NavBaker.instance.mark_dirty_key(int(k))
