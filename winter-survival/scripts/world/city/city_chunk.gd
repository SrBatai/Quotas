class_name CityChunk
extends Node3D
## The city part of one streamed chunk (C0; ARQ v2 §9.7 «Diferido»: ChunkJob → CityBuilding.attach + CityHlod.build_for).
## The ChunkJob (worker) reads the chunk's items from CityLots and prepares everything that is pure data: the item
## list with heights, the per-(model, variant) MultiMesh buffers of cars and props, the collider boxes, the lamps and
## the bridge segment's mesh arrays (`plan()`). WorldChunk then calls step() inside the 2 ms streaming budget: one
## piece of work per step (the colliders; one building — its pieces, CityBuilding.attach and its own ColBody —; the
## bridge; one MultiMesh; the lamps; the chunk HLOD), each with its own cost estimate in the streamer (step kind
## "_step_city:<kind>"). Same data on the server (colliders and building roots only: no meshes, no CityBuilding).
## Colliders are CollisionShape3D boxes on layer world + placement blocker under nodes of group `nav_static`, so the
## server's NavBaker carves them; the buildings' own boxes live under their roots, so the cursor ray goes through a
## building the «corte urbano» cut (CityCut.is_hit_cut finds the root in group city_building).

const LAYER := 65                 # world (1) + placement_blocker (64), like the scatter solids
const SMALL_PROP := 1.0           # props lower than this cast no shadow (C31)
## (model|variant) -> Mesh for the MultiMeshes (art merged into ≤ 2 surfaces, or the procedural stand-in).
static var _group_meshes: Dictionary = {}
static var _podium_meshes: Dictionary = {}
static var _stairs: Dictionary = {}
static var stats: Dictionary = {"group_meshes": 0, "podiums": 0, "warm_usec": 0}

var key: int = 0
var visual: bool = true
var plan: Dictionary = {}
var buildings: Array[Node3D] = []
var hlod: MeshInstance3D
var _steps: Array = []            # [kind, arg]
var _i: int = 0
var _lamps_added: bool = false


# ------------------------------------------------------------------ worker side (pure data)
## Everything a chunk needs from its city items, computed in the ChunkJob worker. `items` from CityLots.chunk_items.
static func make_plan(items: Array, visual_on: bool) -> Dictionary:
	var groups := {}
	var group_order: Array = []
	var cols: Array = []           # [centre, size, basis] (world) of props and vehicles
	var lamps: Array = []          # [bulb, ground y, power]
	var buildings_out: Array = []
	var bridge: Array = []
	for e in items:
		var k := int(e["k"])
		var p: Vector2 = e["pos"]
		var y := float(e.get("y", 0.0))
		match k:
			CityLots.Kind.PODIUM, CityLots.Kind.TOWER:
				buildings_out.append(e)
			CityLots.Kind.BRIDGE:
				var seg := CityProcedural.bridge_segment(CityLots.bridge(), float(e["x0"]), float(e["x1"]), e["ends"])
				bridge.append(seg)
			_:
				var m := str(e["model"])
				var variant := str(e.get("variant", ""))
				var gk := "%s|%s" % [m, variant]
				if visual_on:
					if not groups.has(gk):
						groups[gk] = {"model": m, "variant": variant, "dir": str(e.get("dir", "props")), "rows": PackedFloat32Array(),
							"vehicle": k == CityLots.Kind.VEHICLE}
						group_order.append(gk)
					var row := ChunkJob.instance_row({"x": p.x, "y": y, "z": p.y, "yaw": deg_to_rad(float(e["yaw"])), "s": 1.0})
					var rows: PackedFloat32Array = groups[gk]["rows"]   # packed arrays are values: append, then store back
					rows.append_array(row)
					groups[gk]["rows"] = rows
				var md := CityLots.model_info(m)
				var sz := CityLots.model_size(m)
				var bas := Basis(Vector3.UP, deg_to_rad(float(e["yaw"])))
				if str(md.get("col", "box")) == "cylinder":
					cols.append([Vector3(p.x, y + sz.y * 0.5, p.y), Vector3(maxf(sz.x, 0.2), sz.y, maxf(sz.z, 0.2)), bas, "cyl"])
				else:
					cols.append([Vector3(p.x, y + sz.y * 0.5, p.y), sz, bas, "box"])
				if bool(e.get("lamp", false)) and md.has("bulb"):
					var b := Vector3(CityLots.cm(md["bulb"][0]), CityLots.cm(md["bulb"][1]), CityLots.cm(md["bulb"][2]))
					var bulb := Vector3(p.x, y, p.y) + bas * b
					var h := int(e["wid"])
					var pw := CityLots.power()
					var power := -1.0 if WorldConst.unit(WorldConst.hash64(h, 11)) < float(pw.get("flicker", 0.0)) else 1.0
					lamps.append([bulb, y, power])
	group_order.sort()
	return {"buildings": buildings_out, "groups": groups, "group_order": group_order, "cols": cols, "lamps": lamps, "bridge": bridge,
		"items": items.size()}


## Contact-AO occluders (terrain COLOR.a) of the city items that reach `rect` (buildings, the bridge's feet, cars).
static func occluders_for(items: Array) -> Array:
	var out: Array = []
	for e in items:
		var k := int(e["k"])
		var p: Vector2 = e["pos"]
		match k:
			CityLots.Kind.PODIUM:
				out.append({"id": "city_%d" % int(e["wid"]), "pos": p, "size": (e["size"] as Vector2) + Vector2(0.6, 0.6), "yaw": deg_to_rad(float(e["yaw"])),
					"strength": 0.5, "soft": 2.2})
			CityLots.Kind.VEHICLE:
				var sz := CityLots.model_size(str(e["model"]))
				out.append({"id": "city_%d" % int(e["wid"]), "pos": p, "size": Vector2(sz.x + 0.3, sz.z + 0.3), "yaw": deg_to_rad(float(e["yaw"])),
					"strength": 0.4, "soft": 1.2})
			CityLots.Kind.PROP:
				var s2 := CityLots.model_size(str(e["model"]))
				if s2.x * s2.z > 1.0:
					out.append({"id": "city_%d" % int(e["wid"]), "pos": p, "size": Vector2(s2.x, s2.z), "yaw": deg_to_rad(float(e["yaw"])),
						"strength": 0.3, "soft": 0.8})
	return out


# ------------------------------------------------------------------ main-thread assets (cached, shared)
## The MultiMesh mesh of a model (+ variant): the A1 art merged into one vertex-colour surface (the props' capsule
## material) + one glass surface, or the procedural stand-in. Cached; warm() builds them ahead of streaming.
static func group_mesh(model: String, variant: String, dir: String) -> Mesh:
	var gk := "%s|%s" % [model, variant]
	if _group_meshes.has(gk):
		return _group_meshes[gk]
	var id := "%s/%s" % [dir, model if variant == "" else "%s_%s" % [model, variant]]
	var mesh: Mesh = null
	if TowerAssembler.has_art(id):
		var root := (load(TowerAssembler.art_path(id)) as PackedScene).instantiate() as Node3D
		mesh = _merge(root)
		root.free()
	if mesh == null:
		var info := CityLots.model_info(model)
		mesh = CityProcedural.fallback_prop(model, CityLots.model_size(model), Color(str(info.get("colour", "#808080"))), dir == "vehicles")
		var capm := CityBuilding.capsule_material()
		for i in mesh.get_surface_count():
			(mesh as ArrayMesh).surface_set_material(i, capm)
	_group_meshes[gk] = mesh
	stats["group_meshes"] = int(stats["group_meshes"]) + 1
	return mesh


## Drops the cached meshes (tests: the no-art path of the Web build).
static func clear_cache() -> void:
	_group_meshes.clear()
	_podium_meshes.clear()


## Every MeshInstance3D of an art model (transforms baked) → surface 0: all vertex-colour surfaces (palette, emissive
## lamp heads: wrecks and dead lamps do not glow) with the capsule material; surface 1: glass (its own material).
static func _merge(root: Node3D) -> ArrayMesh:
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
		var node: Node = top[0]
		var xf: Transform3D = top[1]
		for c in node.get_children():
			if not (c is Node3D):
				continue
			var cxf := xf * (c as Node3D).transform
			if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
				var m := (c as MeshInstance3D).mesh
				for si in m.get_surface_count():
					var mat := m.surface_get_material(si)
					var nm := mat.resource_name.to_lower() if mat != null else ""
					if nm == "glass":
						glass.append_from(m, si, cxf)
						glass_mat = mat
						n_glass += 1
					else:
						solid.append_from(m, si, cxf)
						n_solid += 1
			stack.append([c, cxf])
	if n_solid == 0:
		return null
	var out := solid.commit()
	out.surface_set_material(0, CityBuilding.capsule_material())
	if n_glass > 0:
		glass.commit(out)
		out.surface_set_material(1, glass_mat)
	return out


## Podium pieces (CityProcedural.building), cached per podium id (the layout is the same in every world).
static func podium_pieces(p: Dictionary) -> Dictionary:
	var id := int(p["id"])
	if _podium_meshes.has(id):
		return _podium_meshes[id]
	var size: Vector2 = p["size"]
	var opening: Array = []
	var st: Dictionary = p.get("stair", {})
	if not st.is_empty():
		var top := CityLots.cm(st["top"])
		opening = [str(st["face"]), top - CityLots.LANDING, top]
	var b := CityProcedural.building(size.x, size.y, int(p["floors"]), float(p["ground_h"]), float(p["floor_h"]), str(p["style"]), id, -1, opening)
	if not st.is_empty():
		var rise := float(p["ground_h"]) + float(int(p["floors"]) - 1) * float(p["floor_h"])
		b["stair"] = CityProcedural.stair(str(st["face"]), size * 0.5, CityLots.cm(st["bottom"]), CityLots.cm(st["top"]), CityLots.cm(st["width"]), rise)
		b["opening"] = opening
	_podium_meshes[id] = b
	stats["podiums"] = int(stats["podiums"]) + 1
	return b


## Builds every city mesh the lot file needs (towers, podiums, cars, props) on the main thread, before streaming
## reaches the city (World.configure on a visual client; the menu backdrop). Returns the time spent (µs).
static func warm() -> int:
	var t0 := Time.get_ticks_usec()
	if not CityLots.is_loaded():
		return 0
	for t in CityLots.towers():
		var a := TowerAssembler.assembly(str(t["family"]), int(t["groups"]))
		# the city materials of each floor grid (one shared duplicate per grid; the first costs ~1–18 ms)
		CityBuilding.struct_material(float(a["ground_h"]), float(a["floor_h"]))
		CityBuilding.window_material(float(a["ground_h"]), float(a["floor_h"]))
	CityBuilding.capsule_material()
	CityBuilding.window_material(4.0, 3.6)   # silhouettes
	var d := CityLots.data()
	for p in d.get("podiums", []):
		podium_pieces({"id": int(p["id"]), "size": CityLots.v2(p["size"]), "floors": int(p["floors"]), "ground_h": CityLots.cm(p["ground_h"]),
			"floor_h": CityLots.cm(p["floor_h"]), "style": str(p.get("style", "concrete")), "stair": p.get("stair", {})})
		CityBuilding.struct_material(CityLots.cm(p["ground_h"]), CityLots.cm(p["floor_h"]))
		CityBuilding.window_material(CityLots.cm(p["ground_h"]), CityLots.cm(p["floor_h"]))
	for lst in ["props", "rows"]:
		for it in d.get(lst, []):
			var m := str(it["model"])
			group_mesh(m, "", str(CityLots.model_info(m).get("dir", "props")))
	for v in d.get("vehicles", []):
		group_mesh(str(v["model"]), str(v.get("variant", "snowed")), "vehicles")
	for j in d.get("jams", []):
		for m in j["models"]:
			for variant in j["variants"]:
				group_mesh(str(m), str(variant), "vehicles")
	var us := Time.get_ticks_usec() - t0
	stats["warm_usec"] = us
	return us


# ------------------------------------------------------------------ main thread: build in steps
func setup(p_plan: Dictionary, p_visual: bool, p_key: int) -> void:
	plan = p_plan
	visual = p_visual
	key = p_key
	name = "City"
	_steps.clear()
	if not (plan.get("cols", []) as Array).is_empty():
		_steps.append(["colliders", null])
	for b in plan.get("buildings", []):
		_steps.append(["building", b])
	for i in (plan.get("bridge", []) as Array).size():
		_steps.append(["bridge", i])
	if visual:
		for gk in plan.get("group_order", []):
			_steps.append(["multimesh", gk])
		if not (plan.get("lamps", []) as Array).is_empty():
			_steps.append(["lamps", null])
		if not (plan.get("buildings", []) as Array).is_empty():
			_steps.append(["hlod", null])
	_i = 0


func is_done() -> bool:
	return _i >= _steps.size()


## Kind of the next step (the streamer keeps one cost estimate per kind).
func next_kind() -> String:
	return str(_steps[_i][0]) if _i < _steps.size() else "done"


## Runs one step; true when the chunk's city is complete.
func step() -> bool:
	if _i >= _steps.size():
		return true
	var s: Array = _steps[_i]
	_i += 1
	match str(s[0]):
		"colliders":
			add_child(_collider_body("CityProps", plan["cols"]))
		"building":
			_building(s[1])
		"bridge":
			_bridge(int(s[1]))
		"multimesh":
			_multimesh(str(s[1]))
		"lamps":
			if CityLights.instance != null:
				CityLights.instance.add_lamps(key, plan["lamps"])
				_lamps_added = true
		"hlod":
			hlod = CityHlod.build_for(self)
	return _i >= _steps.size()


## Unloading (WorldChunk.begin_teardown): lamps out of CityLights, HLOD links cleared; the nodes are freed after.
func release() -> void:
	if _lamps_added and CityLights.instance != null:
		CityLights.instance.remove_lamps(key)
		_lamps_added = false
	if hlod != null and is_inside_tree():
		CityHlod.remove_from(self)
		hlod = null
	for b in buildings:
		if is_instance_valid(b):
			var cb := b.get_node_or_null("CityBuilding")
			if cb != null:
				CityCut.unregister(cb as CityBuilding)


static func _box_shape(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


## A StaticBody3D (not in the tree yet: Jolt builds its compound once when it enters) with one CollisionShape3D per box.
func _collider_body(n: String, boxes: Array, parent_xf: Transform3D = Transform3D.IDENTITY) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = n
	body.collision_layer = LAYER
	body.collision_mask = 0
	body.add_to_group("nav_static")
	var inv := parent_xf.affine_inverse()
	for b in boxes:
		var cs := CollisionShape3D.new()
		var size: Vector3 = b[1]
		if b.size() > 3 and str(b[3]) == "cyl":
			var cyl := CylinderShape3D.new()
			cyl.radius = maxf(size.x, size.z) * 0.5
			cyl.height = size.y
			cs.shape = cyl
		else:
			cs.shape = _box_shape(size)
		var bas: Basis = b[2] if b.size() > 2 else Basis.IDENTITY
		cs.transform = inv * Transform3D(bas, b[0])
		body.add_child(cs)
	return body


func _building(e: Dictionary) -> void:
	var p: Vector2 = e["pos"]
	var y := float(e["y"])
	var yaw := deg_to_rad(float(e["yaw"]))
	var root: Node3D
	var boxes: Array = []
	if int(e["k"]) == CityLots.Kind.TOWER:
		root = TowerAssembler.build(e) if visual else _bare_root("tower_%d" % int(e["id"]), e)
		for b in TowerAssembler.collider_boxes(e):
			boxes.append([b[0], b[1], Basis.IDENTITY])
	else:
		var pc := podium_pieces(e)
		root = _podium_root(e, pc) if visual else _bare_root("podium_%d" % int(e["id"]), e)
		var size: Vector2 = e["size"]
		var roof := float(pc["roof_level"])
		boxes.append([Vector3(0, (roof - CityProcedural.SKIRT) * 0.5, 0), Vector3(size.x, roof + CityProcedural.SKIRT, size.y), Basis.IDENTITY])
		# parapets (with the stair's gap), so nobody walks off the roof
		var hx := size.x * 0.5
		var hz := size.y * 0.5
		var op: Array = pc.get("opening", [])
		for f in [["n", Vector3(0, 0, -hz + 0.15), Vector3(size.x, 0, 0.3)], ["s", Vector3(0, 0, hz - 0.15), Vector3(size.x, 0, 0.3)],
				["w", Vector3(-hx + 0.15, 0, 0), Vector3(0.3, 0, size.y)], ["e", Vector3(hx - 0.15, 0, 0), Vector3(0.3, 0, size.y)]]:
			var c: Vector3 = f[1]
			var s: Vector3 = f[2]
			var par_y := roof + CityProcedural.PARAPET * 0.5
			if not op.is_empty() and str(op[0]) == str(f[0]):
				# two pieces around the gap [op1, op2] along the face's axis
				var along_z := str(f[0]) == "w" or str(f[0]) == "e"
				var lo := -(hz if along_z else hx)
				var hi := (hz if along_z else hx)
				for span in [[lo, float(op[1])], [float(op[2]), hi]]:
					var a := float(span[0])
					var bnd := float(span[1])
					if bnd - a < 0.05:
						continue
					var mid := (a + bnd) * 0.5
					var cc := Vector3(c.x, par_y, mid) if along_z else Vector3(mid, par_y, c.z)
					var ss := Vector3(0.3, CityProcedural.PARAPET, bnd - a) if along_z else Vector3(bnd - a, CityProcedural.PARAPET, 0.3)
					boxes.append([cc, ss, Basis.IDENTITY])
			else:
				boxes.append([Vector3(c.x, par_y, c.z), Vector3(maxf(s.x, 0.3), CityProcedural.PARAPET, maxf(s.z, 0.3)), Basis.IDENTITY])
		if pc.has("stair"):
			var sd: Dictionary = pc["stair"]
			for key_name in ["ramp", "landing", "rail"]:
				var r: Array = sd[key_name]
				boxes.append([r[0], r[1], r[2]])
	root.position = Vector3(p.x, y, p.y)
	root.rotation.y = yaw
	root.set_meta("wid", int(e["wid"]))
	root.add_child(_collider_body("ColBody", boxes))   # its own body (group nav_static): the cursor ray finds the root
	add_child(root)
	buildings.append(root)
	if visual:
		CityBuilding.attach(root)
		if int(e["k"]) == CityLots.Kind.PODIUM:
			var pc2 := podium_pieces(e)
			if pc2.has("stair"):
				var sm := MeshInstance3D.new()
				sm.name = "Stair_%d" % int(e["id"])
				sm.mesh = (pc2["stair"] as Dictionary)["mesh"]
				CityBuilding.apply_prop_materials(sm)
				sm.transform = root.transform
				add_child(sm)


func _bare_root(n: String, e: Dictionary) -> Node3D:
	var r := Node3D.new()
	r.name = n
	r.set_meta("kind", "tower" if int(e["k"]) == CityLots.Kind.TOWER else "podium")
	return r


func _podium_root(e: Dictionary, pc: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "podium_%d" % int(e["id"])
	root.set_meta("floor_h", float(e["floor_h"]))
	root.set_meta("ground_h", float(e["ground_h"]))
	root.set_meta("foundation", CityProcedural.FOUNDATION)
	root.set_meta("floors", int(e["floors"]))
	root.set_meta("generator", bool(e.get("generator", false)))
	root.set_meta("enterable", false)
	root.set_meta("kind", "podium")
	for n in ["Base", "Roof", "ShadowProxy"]:
		var mi := MeshInstance3D.new()
		mi.name = n
		mi.mesh = pc[n]
		root.add_child(mi)
	return root


func _bridge(i: int) -> void:
	var seg: Dictionary = plan["bridge"][i]
	var mesh := ArrayMesh.new()
	if visual:
		for part in [["arrays", Assets.get_shared_material()], ["iron", CityBuilding.capsule_material()]]:
			var arr: Array = seg[part[0]]
			if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] is PackedVector3Array and (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0:
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				mesh.surface_set_material(mesh.get_surface_count() - 1, part[1])
		if mesh.get_surface_count() > 0:
			var mi := MeshInstance3D.new()
			mi.name = "Bridge_%d" % i
			mi.mesh = mesh
			add_child(mi)
	var body := _collider_body("BridgeCol_%d" % i, seg["cols"])
	add_child(body)


func _multimesh(gk: String) -> void:
	var g: Dictionary = plan["groups"][gk]
	var rows: PackedFloat32Array = g["rows"]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = group_mesh(str(g["model"]), str(g["variant"]), str(g["dir"]))
	mm.instance_count = rows.size() / 12
	mm.buffer = rows
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "mm_%s" % gk.replace("|", "_")
	mmi.multimesh = mm
	var sz := CityLots.model_size(str(g["model"]))
	var small := sz.y < SMALL_PROP and sz.x * sz.z < 2.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if small else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mmi.visibility_range_end = 160.0 if not bool(g["vehicle"]) else 200.0
	mmi.visibility_range_end_margin = 10.0
	add_child(mmi)
