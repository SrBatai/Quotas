class_name CitySilhouettes
extends Node3D
## District silhouettes v0 (C0; doc 09 §4.6, PLAN v3.4 «miradores» and «menú»): one low-poly mesh per district of
## Altavega — the footprints of its blocks extruded to their height, merged, walls / roofs by vertex colour and the
## facades on the city window material (lit cells by night, per power) — plus the landmarks (Torre Albo, the
## cathedral, the telecom mast, the hospital, the stadium…) and a coarse far-terrain sheet so the skyline stands on
## ground beyond the streamed ring. 2 draw calls per district. The play camera never sees them (its far plane is
## 70–95 m and it looks 30° down): only the miradores and the main menu turn this layer on (`visible`).
## Generated from the rules of the lot file (`silhouettes`: grids, block sizes, floors, landmarks) with the lot
## file's own seed — the same skyline in every world — and heights from the HeightFunction on a 64 m grid. The
## geometry is built off the main thread (WorkerThreadPool) and uploaded when ready (`ready_meshes` signal). C1:
## districts of kind `lots` are the real generated lots (CityLots: rotated footprints to their tops, the podiums,
## the A1 towers and the hero towers), ≈ 3 000 boxes.

signal built()

const FLOOR_BAND := 1.0          # the ground floor band stays wall; the glass starts above it
const TERRAIN_DROP := 1.2        # the far-terrain sheet sits this far under the real terrain (never pokes through)

var hf: HeightFunction
var is_built: bool = false
var meshes: Array[MeshInstance3D] = []
var stats: Dictionary = {}
var _task: int = -1
var _result: Dictionary = {}
var _grid: Dictionary = {}


## Starts the build (worker thread when available). `p_hf` = the world's height function.
func build_async(p_hf: HeightFunction) -> void:
	hf = p_hf
	visible = false
	if WorldStreamer.threads_ok():
		_task = WorkerThreadPool.add_task(_build_data, false, "city silhouettes")
		set_process(true)
	else:
		_build_data()
		_upload()


## Synchronous build (tools, tests, the menu when there are no threads).
func build_now(p_hf: HeightFunction) -> void:
	hf = p_hf
	_build_data()
	_upload()


func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_upload()
		set_process(false)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


# ------------------------------------------------------------------ data (pure; worker thread)
func _build_data() -> void:
	var t0 := Time.get_ticks_usec()
	var spec := CityLots.silhouettes()
	var res := {"districts": [], "terrain": null}
	if spec.is_empty() or hf == null:
		_result = res
		return
	_grid = _terrain_grid(spec)
	var excl: Array[Rect2] = []
	for e in spec.get("exclude", []):
		excl.append(CityLots.rect_of(e))
	var marks: Array = spec.get("landmarks", [])
	var mark_rects: Array[Rect2] = []
	for m in marks:
		mark_rects.append(_landmark_rect(m))
	var seed_v := int(spec.get("seed", 1))
	var boxes_total := 0
	for d in spec.get("districts", []):
		var g := _Geo.new()
		var wall := Color(str(d.get("wall", "#707070")))
		var roof := Color(str(d.get("roof", "#E0E4EA")))
		var boxes: Array = []
		if str(d["kind"]) == "lots":
			# C1: the real lots of the generated district (rotated footprints extruded to their tops)
			var nb := _lots(g, str(d.get("district", d["id"])), wall, roof)
			boxes_total += nb
			(res["districts"] as Array).append({"id": str(d["id"]), "solid": g.solid(), "glass": g.glass(), "boxes": nb, "tris": g.tris})
			continue
		match str(d["kind"]):
			"towers":
				boxes = _towers(d, seed_v)
			"blocks":
				boxes = _blocks(d, seed_v)
			"old":
				boxes = _old(d, seed_v)
			"slabs":
				boxes = _slabs(d, seed_v)
		var n := 0
		for b in boxes:
			var r: Rect2 = b[0]
			if _hits(r, excl) or _hits(r, mark_rects):
				continue
			g.box(r, _base(r), float(b[1]), wall, roof, bool(b[2]))
			n += 1
		boxes_total += n
		(res["districts"] as Array).append({"id": str(d["id"]), "solid": g.solid(), "glass": g.glass(), "boxes": n, "tris": g.tris})
	var lm := _Geo.new()
	for m in marks:
		if _hits(_landmark_rect(m), excl):
			continue
		_landmark(lm, m)
	(res["districts"] as Array).append({"id": "landmarks", "solid": lm.solid(), "glass": lm.glass(), "boxes": marks.size(), "tris": lm.tris})
	res["terrain"] = _terrain_sheet()
	res["usec"] = Time.get_ticks_usec() - t0
	res["boxes"] = boxes_total
	_result = res


func _upload() -> void:
	var tris := 0
	for d in _result.get("districts", []):
		var mesh := ArrayMesh.new()
		var solid: Array = d["solid"]
		if not solid.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, solid)
			mesh.surface_set_material(mesh.get_surface_count() - 1, Assets.get_shared_material())
		var glass: Array = d["glass"]
		if not glass.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glass)
			mesh.surface_set_material(mesh.get_surface_count() - 1, CityBuilding.window_material(4.0, 3.6))
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Silhouette_%s" % str(d["id"])
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		meshes.append(mi)
		tris += int(d["tris"])
	var ter: Array = _result.get("terrain", [])
	if ter != null and not ter.is_empty():
		var tm := ArrayMesh.new()
		tm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ter)
		tm.surface_set_material(0, Assets.get_shared_material())
		var ti := MeshInstance3D.new()
		ti.name = "FarTerrain"
		ti.mesh = tm
		ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ti)
		meshes.append(ti)
	stats = {"meshes": meshes.size(), "tris": tris, "boxes": int(_result.get("boxes", 0)), "build_ms": float(_result.get("usec", 0)) / 1000.0}
	is_built = true
	_result = {}
	built.emit()


# ------------------------------------------------------------------ terrain (64 m grid, bilinear)
func _terrain_grid(spec: Dictionary) -> Dictionary:
	var ext := CityLots.rect_of(spec["extent"])
	var step := CityLots.cm(spec.get("terrain_step", 6400))
	var nx := int(ceil(ext.size.x / step)) + 1
	var nz := int(ceil(ext.size.y / step)) + 1
	var h := PackedFloat32Array()
	h.resize(nx * nz)
	for j in nz:
		for i in nx:
			h[j * nx + i] = hf.height_at(ext.position.x + float(i) * step, ext.position.y + float(j) * step)
	return {"x0": ext.position.x, "z0": ext.position.y, "step": step, "nx": nx, "nz": nz, "h": h}


func _h(x: float, z: float) -> float:
	var g := _grid
	var fx := clampf((x - float(g["x0"])) / float(g["step"]), 0.0, float(int(g["nx"]) - 1) - 0.001)
	var fz := clampf((z - float(g["z0"])) / float(g["step"]), 0.0, float(int(g["nz"]) - 1) - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var nx := int(g["nx"])
	var hh: PackedFloat32Array = g["h"]
	var k := j * nx + i
	return lerpf(lerpf(hh[k], hh[k + 1], tx), lerpf(hh[k + nx], hh[k + nx + 1], tx), tz)


## Base of a box: the lowest corner (the box is extended 1.5 m down so it never floats on a slope).
func _base(r: Rect2) -> float:
	var h := minf(minf(_h(r.position.x, r.position.y), _h(r.end.x, r.position.y)), minf(_h(r.end.x, r.end.y), _h(r.position.x, r.end.y)))
	return h - 1.5


func _terrain_sheet() -> Array:
	var g := _grid
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var nx := int(g["nx"])
	var nz := int(g["nz"])
	var hh: PackedFloat32Array = g["h"]
	var snow := CityProcedural.COL_SNOW.srgb_to_linear()
	for j in nz - 1:
		for i in nx - 1:
			var p := []
			for q in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var x := float(g["x0"]) + float(q[0]) * float(g["step"])
				var z := float(g["z0"]) + float(q[1]) * float(g["step"])
				p.append(Vector3(x, hh[int(q[1]) * nx + int(q[0])] - TERRAIN_DROP, z))
			for v in [p[0], p[1], p[2], p[0], p[2], p[3]]:
				st.set_color(Color(snow.r, snow.g, snow.b, 1.0))
				st.add_vertex(v)
	st.generate_normals()
	return st.commit_to_arrays()


# ------------------------------------------------------------------ district rules → [Rect2, height, glass]
func _rand(seed_v: int, a: int, b: int, c: int) -> float:
	return WorldConst.unit(WorldConst.hash64(seed_v, CityLots.GEN_CITY, a, b, c))


## Rows of blocks north and south of the district's avenue (z = origin.z, `avenue` wide) and columns from origin.x.
func _grid_blocks(d: Dictionary) -> Array:
	var rect := CityLots.rect_of(d["rect"])
	var o := CityLots.v2(d["origin"])
	var bs := CityLots.v2(d["block"])
	var street := CityLots.cm(d["street"])
	var half_av := CityLots.cm(d.get("avenue", 0)) * 0.5
	var out: Array = []
	var cols: Array = []
	var x := o.x
	while x + bs.x <= rect.end.x + 0.01:
		if x >= rect.position.x - 0.01:
			cols.append(x)
		x += bs.x + street
	var rows: Array = []
	var z1 := o.y - half_av
	while z1 - bs.y >= rect.position.y - 0.01:
		if z1 <= rect.end.y + 0.01:
			rows.append(z1 - bs.y)
		z1 -= bs.y + street
	var z0 := o.y + half_av
	while z0 + bs.y <= rect.end.y + 0.01:
		if z0 >= rect.position.y - 0.01:
			rows.append(z0)
		z0 += bs.y + street
	for zi in rows.size():
		for xi in cols.size():
			out.append(Rect2(Vector2(float(cols[xi]), float(rows[zi])), bs))
	return out


func _towers(d: Dictionary, seed_v: int) -> Array:
	var out: Array = []
	var fh := CityLots.cm(d.get("floor_h", 380))
	var fl: Array = d["floors"]
	var tw: Array = d["tower"]
	var tn: Array = d["towers"]
	var pf: Array = d["podium_floors"]
	var bi := 0
	for blk in _grid_blocks(d):
		var b: Rect2 = blk
		bi += 1
		var n := int(tn[0]) + int(_rand(seed_v, 1, bi, 0) * float(int(tn[1]) - int(tn[0]) + 1))
		# podium over the block (3 m setback), 1–3 floors
		var podf := int(pf[0]) + int(_rand(seed_v, 1, bi, 1) * float(int(pf[1]) - int(pf[0]) + 1))
		out.append([b.grow(-3.0), 4.3 + float(podf - 1) * fh, false])
		var slot := (b.size.x - 12.0) / float(n)
		for t in n:
			var w := CityLots.cm(tw[0]) + _rand(seed_v, 2, bi, t) * (CityLots.cm(tw[1]) - CityLots.cm(tw[0]))
			var dd := CityLots.cm(tw[0]) + _rand(seed_v, 3, bi, t) * (CityLots.cm(tw[1]) - CityLots.cm(tw[0]))
			w = minf(w, slot - 4.0)
			var u := _rand(seed_v, 4, bi, t)
			var floors := int(fl[0]) + int(pow(u, 1.6) * float(int(fl[1]) - int(fl[0]) + 1))
			var cx := b.position.x + 6.0 + slot * (float(t) + 0.5)
			var cz := b.position.y + 6.0 + dd * 0.5 + _rand(seed_v, 5, bi, t) * maxf(b.size.y - 12.0 - dd, 0.0)
			out.append([Rect2(cx - w * 0.5, cz - dd * 0.5, w, dd), 4.3 + float(floors - 1) * fh + 2.0, true])
	return out


func _blocks(d: Dictionary, seed_v: int) -> Array:
	var out: Array = []
	var fh := CityLots.cm(d.get("floor_h", 320))
	var fl: Array = d["floors"]
	var depth := CityLots.cm(d.get("depth", 1600))
	var bi := 0
	for blk in _grid_blocks(d):
		var b: Rect2 = blk
		bi += 1
		if _rand(seed_v, 6, bi, 0) < 0.06:
			continue   # a square / a gap
		for side in 4:
			var floors := int(fl[0]) + int(_rand(seed_v, 7, bi, side) * float(int(fl[1]) - int(fl[0]) + 1))
			var h := 4.0 + float(floors - 1) * fh + 1.0
			var r: Rect2
			match side:
				0:
					r = Rect2(b.position, Vector2(b.size.x, depth))
				1:
					r = Rect2(Vector2(b.position.x, b.end.y - depth), Vector2(b.size.x, depth))
				2:
					r = Rect2(Vector2(b.position.x, b.position.y + depth), Vector2(depth, b.size.y - 2.0 * depth))
				_:
					r = Rect2(Vector2(b.end.x - depth, b.position.y + depth), Vector2(depth, b.size.y - 2.0 * depth))
			out.append([r, h, true])
	return out


func _old(d: Dictionary, seed_v: int) -> Array:
	var out: Array = []
	var rect := CityLots.rect_of(d["rect"])
	var cell := CityLots.cm(d.get("cell", 2600))
	var fh := CityLots.cm(d.get("floor_h", 320))
	var fl: Array = d["floors"]
	var empty := float(d.get("empty", 0.15))
	var av_z := CityLots.cm((d.get("origin", [0, -38400]) as Array)[1])
	var half_av := CityLots.cm(d.get("avenue", 0)) * 0.5
	var nx := int(rect.size.x / cell)
	var nz := int(rect.size.y / cell)
	for j in nz:
		for i in nx:
			if _rand(seed_v, 8, i, j) < empty:
				continue
			var jx := (_rand(seed_v, 9, i, j) - 0.5) * cell * 0.25
			var jz := (_rand(seed_v, 10, i, j) - 0.5) * cell * 0.25
			var w := cell * (0.55 + 0.3 * _rand(seed_v, 11, i, j))
			var dd := cell * (0.55 + 0.3 * _rand(seed_v, 12, i, j))
			var c := rect.position + Vector2((float(i) + 0.5) * cell + jx, (float(j) + 0.5) * cell + jz)
			if half_av > 0.0 and absf(c.y - av_z) < half_av + dd * 0.5:
				continue
			var floors := int(fl[0]) + int(_rand(seed_v, 13, i, j) * float(int(fl[1]) - int(fl[0]) + 1))
			out.append([Rect2(c - Vector2(w, dd) * 0.5, Vector2(w, dd)), 3.6 + float(floors - 1) * fh + 1.5, true])
	return out


func _slabs(d: Dictionary, seed_v: int) -> Array:
	var out: Array = []
	var rect := CityLots.rect_of(d["rect"])
	var cell := CityLots.v2(d["cell"])
	var slab := CityLots.v2(d["slab"])
	var fh := CityLots.cm(d.get("floor_h", 290))
	var fl: Array = d["floors"]
	var nx := int(rect.size.x / cell.x)
	var nz := int(rect.size.y / cell.y)
	for j in nz:
		for i in nx:
			if _rand(seed_v, 14, i, j) < 0.12:
				continue
			var turned := _rand(seed_v, 15, i, j) < 0.35
			var s := Vector2(slab.y, slab.x) if turned else slab
			s.x = minf(s.x, cell.x - 6.0)
			s.y = minf(s.y, cell.y - 6.0)
			var c := rect.position + Vector2((float(i) + 0.5) * cell.x, (float(j) + 0.5) * cell.y)
			var floors := int(fl[0]) + int(_rand(seed_v, 16, i, j) * float(int(fl[1]) - int(fl[0]) + 1))
			out.append([Rect2(c - s * 0.5, s), 3.0 + float(floors - 1) * fh + 1.2, true])
	return out


## C1: every generated lot of a district as an oriented box to its top (+ the podiums, towers and heroes of Las Torres).
func _lots(g: _Geo, district: String, wall: Color, roof: Color) -> int:
	var di := CityGen.DISTRICT_IDS.find(district)
	var n := 0
	var tint := {"casco": Color("#B89A78"), "ensanche": Color("#A99C88"), "bloque": Color("#8E6252"), "caseta": Color("#7E806E")}
	for id in CityLots.building_ids():
		var b := CityLots.building(int(id))
		if int(b["district"]) != di:
			continue
		var q := CityLots.obb(b["pos"], b["size"], float(b["yaw"]))
		var fam := str(b["fam"])
		var top := BuildingAssembler.top(fam, int(b["var"]), int(b["floors"]))
		g.obox(q, _base(_bounds(q)), top + 1.5, tint.get(fam, wall), roof, fam != "caseta")
		n += 1
	if district == "las_torres":
		var fams := CityLots.families()
		for p in CityLots.podiums():
			var c := CityLots.v2(p["pos"])
			var sz := CityLots.v2(p["size"])
			var r := Rect2(c - sz * 0.5, sz)
			var pb := _base(r)
			g.box(r, pb, CityLots.podium_roof(p) + 2.5, Color("#7C848E"), roof, true)
			n += 1
		for t in CityLots.towers():
			var pod := CityLots.podium(int(t["on"]))
			if pod.is_empty():
				continue
			var fam: Dictionary = fams.get(str(t["family"]), {})
			var c := CityLots.v2(t["pos"])
			var ps := CityLots.v2(fam.get("proxy", [1500, 1500]))
			if int(t.get("yaw", 0)) % 180 != 0:
				ps = Vector2(ps.y, ps.x)
			var r := Rect2(c - ps * 0.5, ps)
			var pc := CityLots.v2(pod["pos"])
			var ps2 := CityLots.v2(pod["size"])
			var y0 := _base(Rect2(pc - ps2 * 0.5, ps2)) + 1.5 + CityLots.podium_roof(pod)
			g.box(r, y0, CityLots.cm(fam.get("roof_z", 6000)) + CityLots.tower_shift(t), Color("#56606E"), roof, true)
			n += 1
		for h in CityLots.heroes():
			var q := CityLots.obb(CityLots.v2(h["pos"]), CityLots.v2(h["size"]), float(h.get("yaw", 0.0)))
			var hh := HeroTower.level(int(h["floors"]), CityLots.cm(h.get("ground_h", 430)), CityLots.cm(h.get("floor_h", 380))) + HeroTower.PARAPET
			g.obox(q, _base(_bounds(q)), hh + 1.5, Color("#4E5968"), roof, true)
			if str(h.get("crown", "")) == "helipad":
				var c := CityLots.v2(h["pos"])
				g.box(Rect2(c - Vector2(0.6, 0.6), Vector2(1.2, 1.2)), _base(_bounds(q)) + hh + 1.5, 16.0, Color("#B04030"), Color("#B04030"), false)
			n += 1
	return n


static func _bounds(q: PackedVector2Array) -> Rect2:
	var r := Rect2(q[0], Vector2.ZERO)
	for p in q:
		r = r.expand(p)
	return r


static func _hits(r: Rect2, list: Array[Rect2]) -> bool:
	for e in list:
		if e.intersects(r):
			return true
	return false


# ------------------------------------------------------------------ landmarks
func _landmark_rect(m: Dictionary) -> Rect2:
	var p := CityLots.v2(m["pos"])
	var s := CityLots.v2(m.get("size", [4000, 4000])) if m.has("size") else Vector2(40, 40)
	if str(m["kind"]) == "cathedral":
		s = Vector2(90, 60)
	elif str(m["kind"]) == "mast":
		s = Vector2(24, 24)
	return Rect2(p - s * 0.5, s)


func _landmark(g: _Geo, m: Dictionary) -> void:
	var p := CityLots.v2(m["pos"])
	var kind := str(m["kind"])
	var base := _h(p.x, p.y) - 1.0
	var wall := Color(str(m.get("wall", "#6A7280")))
	var roof := Color("#DCE3EC")
	match kind:
		"tower":
			var s := CityLots.v2(m["size"])
			var h := 4.3 + float(int(m["floors"]) - 1) * CityLots.cm(m.get("floor_h", 380))
			g.box(Rect2(p - s * 0.5, s), base, h, wall, roof, true)
			# stepped crown, helipad deck and the mast
			g.box(Rect2(p - s * 0.36, s * 0.72), base + h, 7.0, wall.darkened(0.15), roof, true)
			g.box(Rect2(p - Vector2(11, 11), Vector2(22, 22)), base + h + 7.0, 0.6, Color("#3A3F48"), Color("#C8CED8"), false)
			g.box(Rect2(p - Vector2(0.6, 0.6), Vector2(1.2, 1.2)), base + h + 7.6, 22.0, Color("#B04030"), Color("#B04030"), false)
		"cathedral":
			var stone := Color("#9C8C74")
			g.box(Rect2(p + Vector2(-35, -12), Vector2(70, 24)), base, 22.0, stone, Color("#E6EAF0"), false)     # nave
			g.box(Rect2(p + Vector2(-8, -24), Vector2(22, 48)), base, 19.0, stone, Color("#E6EAF0"), false)      # transept
			g.box(Rect2(p + Vector2(-44, -7), Vector2(14, 14)), base, 50.0, stone, Color("#E6EAF0"), false)      # bell tower
			g.box(Rect2(p + Vector2(-41, -4), Vector2(8, 8)), base + 50.0, 14.0, stone.darkened(0.2), Color("#E6EAF0"), false)
			g.box(Rect2(p + Vector2(14, -9), Vector2(16, 18)), base, 16.0, stone, Color("#E6EAF0"), false)       # apse
		"mast":
			var h := CityLots.cm(m["height"])
			var concrete := Color("#B8B8B4")
			g.box(Rect2(p - Vector2(4, 4), Vector2(8, 8)), base, h * 0.78, concrete, concrete, false)
			g.box(Rect2(p - Vector2(9, 9), Vector2(18, 18)), base + h * 0.62, 9.0, concrete.darkened(0.2), roof, true)
			g.box(Rect2(p - Vector2(0.8, 0.8), Vector2(1.6, 1.6)), base + h * 0.78, h * 0.22, Color("#B04030"), Color("#B04030"), false)
		"hospital":
			var s := CityLots.v2(m["size"])
			var h := 4.3 + float(int(m["floors"]) - 1) * CityLots.cm(m.get("floor_h", 360))
			var wl := Color("#C8C4B8")
			g.box(Rect2(p + Vector2(-s.x * 0.5, -s.y * 0.5), Vector2(s.x, 20)), base, h, wl, roof, true)
			g.box(Rect2(p + Vector2(-s.x * 0.5, s.y * 0.5 - 20), Vector2(s.x, 20)), base, h, wl, roof, true)
			g.box(Rect2(p + Vector2(-12, -s.y * 0.5 + 20), Vector2(24, s.y - 40)), base, h + 4.0, wl, roof, true)
		"box":
			var s := CityLots.v2(m["size"])
			g.box(Rect2(p - s * 0.5, s), base, CityLots.cm(m["height"]), Color("#8E9298"), roof, true)
		"stadium":
			var s := CityLots.v2(m["size"])
			var h := CityLots.cm(m["height"])
			for k in 16:
				var a := TAU * float(k) / 16.0
				var c := p + Vector2(cos(a) * s.x * 0.44, sin(a) * s.y * 0.44)
				g.box(Rect2(c - Vector2(24, 24), Vector2(48, 48)), base, h * (0.8 + 0.2 * float(k % 2)), Color("#A8ACB2"), roof, false)
		"campus":
			var s := CityLots.v2(m["size"])
			var h := 4.0 + float(int(m["floors"]) - 1) * CityLots.cm(m.get("floor_h", 360))
			g.box(Rect2(p + Vector2(-s.x * 0.5, -s.y * 0.5), Vector2(s.x * 0.6, 22)), base, h, Color("#9A7E6A"), roof, true)
			g.box(Rect2(p + Vector2(-s.x * 0.5, s.y * 0.5 - 22), Vector2(s.x * 0.6, 22)), base, h, Color("#9A7E6A"), roof, true)
			g.box(Rect2(p + Vector2(s.x * 0.2, -s.y * 0.5), Vector2(28, s.y)), base, h + 3.6, Color("#9A7E6A"), roof, true)
		"dam":
			var s := CityLots.v2(m["size"])
			g.box(Rect2(p - s * 0.5, s), base - 8.0, CityLots.cm(m["height"]), Color("#B4B2AC"), roof, false)


## Box geometry accumulator: walls + roofs (vertex colours) and facade glass above the ground band.
class _Geo:
	var st := SurfaceTool.new()
	var gl := SurfaceTool.new()
	var tris: int = 0
	var _n_glass: int = 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		gl.begin(Mesh.PRIMITIVE_TRIANGLES)
		gl.set_smooth_group(-1)

	func box(r: Rect2, y0: float, h: float, wall: Color, roof: Color, glass: bool) -> void:
		var y1 := y0 + h
		var c := [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)]
		var wl := wall.srgb_to_linear()
		var rl := roof.srgb_to_linear()
		var band := minf(y0 + 1.5 + FLOOR_BAND + 3.0, y1)
		for k in 4:
			var a: Vector2 = c[k]
			var b: Vector2 = c[(k + 1) % 4]
			if glass and h > 8.0:
				_wall(st, a, b, y0, band, wl)
				_wall(gl, a, b, band, y1 - 0.8, Color(0.2, 0.25, 0.3))
				_wall(st, a, b, y1 - 0.8, y1, wl)
				_n_glass += 2
				tris += 6
			else:
				_wall(st, a, b, y0, y1, wl)
				tris += 2
		# roof (snow)
		_tri_quad(st, Vector3(c[0].x, y1, c[0].y), Vector3(c[3].x, y1, c[3].y), Vector3(c[2].x, y1, c[2].y), Vector3(c[1].x, y1, c[1].y), rl)
		tris += 2

	## An oriented box: the quad `q` (CityLots.obb order: NW, NE, SE, SW in the building frame) extruded from y0 by h.
	func obox(q: PackedVector2Array, y0: float, h: float, wall: Color, roof: Color, glass: bool) -> void:
		var y1 := y0 + h
		var wl := wall.srgb_to_linear()
		var rl := roof.srgb_to_linear()
		var band := minf(y0 + 1.5 + FLOOR_BAND + 3.0, y1)
		for k in 4:
			var a: Vector2 = q[k]
			var b: Vector2 = q[(k + 1) % 4]
			if glass and h > 8.0:
				_wall(st, a, b, y0, band, wl)
				_wall(gl, a, b, band, y1 - 0.8, Color(0.2, 0.25, 0.3))
				_wall(st, a, b, y1 - 0.8, y1, wl)
				_n_glass += 2
				tris += 6
			else:
				_wall(st, a, b, y0, y1, wl)
				tris += 2
		_tri_quad(st, Vector3(q[0].x, y1, q[0].y), Vector3(q[3].x, y1, q[3].y), Vector3(q[2].x, y1, q[2].y), Vector3(q[1].x, y1, q[1].y), rl)
		tris += 2

	## Outward wall a→b (the rect corners run NW → NE → SE → SW: the outside is to the left of a→b seen from above).
	func _wall(s: SurfaceTool, a: Vector2, b: Vector2, y0: float, y1: float, col: Color) -> void:
		_tri_quad(s, Vector3(a.x, y0, a.y), Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3(b.x, y0, b.y), col)

	## Quad a-b-c-d listed counter-clockwise seen from its visible side (Godot's front faces are clockwise).
	func _tri_quad(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		for v in [a, c, b, a, d, c]:
			s.set_color(Color(col.r, col.g, col.b, 1.0))
			s.add_vertex(v)

	func solid() -> Array:
		st.generate_normals()
		return st.commit_to_arrays()

	func glass() -> Array:
		if _n_glass == 0:
			return []
		gl.generate_normals()
		return gl.commit_to_arrays()
