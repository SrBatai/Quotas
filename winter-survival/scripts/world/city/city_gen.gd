class_name CityGen
extends RefCounted
## Altavega city generator (C1, doc 09 §4.5 «Tubería recomendada» steps 1–2): reads the hand-authored district rules
## (data/world/city/districts.json) and writes the city as DATA (data/world/city/altavega_lots.json, city_version 1),
## the same bytes on every client and server — the game never generates the layout at run time (doc 09 §4.4
## «Determinismo»); only the dressing (jams, vehicles, loot) depends on the world seed. Offline tool:
##   godot --headless --path . -s tools/gen_city.gd [++ --check] [++ --out=path]
## Pure and deterministic: integer centimetres and centidegrees in the output, WorldConst.hash64 of the file seed for
## every choice (no RandomNumberGenerator), fixed iteration order, a canonical serialiser (sorted keys, one building
## per line); --check rebuilds in memory and compares the bytes with the committed file (CI).
##
## Districts (doc 09 §4.3 / §4.5; PoiRegistry rects):
##   las_torres   supermanzanas of 112 × 80 m between 20 m streets: 2–4 non-enterable podiums (CityProcedural) with
##                the A1 CC0 towers stacked by TowerAssembler (C0 families tower_a…e, 18–42 floors); the C0 superblock
##                LT-01 is kept as it was (fixed content); two blocks hold the hero towers (Torre Albo, Meridiano)
##   ensanche     a grid of 96 m manzanas cerradas with 12 m chaflanes and 18 m streets: 4 corner lots (chaflán
##                variant) + 3–4 frontage lots per side (15–24 m), 5–8 floors by block, shops in the bajos
##   casco_viejo  an organic street net (a jittered lattice, 6.5–8 m streets, main streets every 3 lines), lots of
##                6–12 m along each block edge (overlaps dropped), 3–4 floors, soportales on the plazas, the plaza
##                mayor around the cathedral pad (C2)
##   barriada     superblocks of 120 m in a park: 8–14-floor brick slabs (40–60 × 11 m) and point blocks
## + the paseos along the río Albo, the Gran Vía sidewalks, the street graph (nodes / edges: hordes L2, convoys,
## snowploughs), the zones (districts), the silhouettes spec (the real lots, for miradores and the menu), the camera
## zones (rooftop detection), the power (blackout + generator lots) and the stats.

const GEN_CITY_GEN := 0x43475631     # "CGV1": the generator's own hash stream (the file seed, not the world seed)
const FORMAT := "altavega_lots"
const CELL := 32.0                   # overlap grid (m)
## Building row fields (the output's `buildings.fields`).
const FIELDS := ["id", "fam", "var", "floors", "x", "z", "yaw", "pal", "flags", "district"]
const FLAG_ENT := 1
const FLAG_GEN := 2
const SEG_FIELDS := ["x0", "z0", "x1", "z1", "w", "kind"]
const SEG_ROAD := 0
const SEG_WALK := 1
const SEG_PLAZA := 2
const DISTRICT_IDS := ["casco_viejo", "ensanche", "barriada", "las_torres"]

var src: Dictionary = {}
var hf: HeightFunction
var seed_v: int = 0
var problems := PackedStringArray()
var stats: Dictionary = {}
var buildings: Array = []          # rows (FIELDS)
var segs: Array = []               # rows (SEG_FIELDS)
var podiums: Array = []
var towers: Array = []
var props: Array = []
var vehicles: Array = []
var rows: Array = []
var nodes: Array = []              # [x_cm, z_cm]
var edges: Array = []              # [a, b, width_cm, kind]
var _node_index: Dictionary = {}   # "x|z" (2 m cells) -> node index
var _raw_edges: Array = []         # [a, b, width, kind] before the split
var _edge_keys: Dictionary = {}
var _grid: Dictionary = {}         # cell key -> Array of [OBB corners (PackedVector2Array)]
var _reserved: Array[Rect2] = []
var _reserved_grow: Array[float] = []
var _next_id: Dictionary = {"building": 10000, "podium": 1000, "tower": 2000, "prop": 60000, "row": 6000, "vehicle": 4600}
var _district_of: Dictionary = {}  # district id -> index in DISTRICT_IDS


# ------------------------------------------------------------------ entry
## Builds the output dictionary from the district rules. `p_hf`: a HeightFunction (any seed; slope / water checks).
func run(p_src: Dictionary, p_hf: HeightFunction) -> Dictionary:
	src = p_src
	hf = p_hf
	seed_v = int(src.get("seed", 1))
	for i in DISTRICT_IDS.size():
		_district_of[DISTRICT_IDS[i]] = i
	for r in src.get("reserved", []):
		_reserved.append(_rect(r["rect"]))
		_reserved_grow.append(_cm(r.get("grow", 0)))
	var fixed: Dictionary = src.get("fixed", {})
	# fixed content first: its footprints block the generator
	for p in fixed.get("podiums", []):
		podiums.append(p)
		_occupy(_obb(_v2(p["pos"]), _v2(p["size"]) + Vector2(2, 2), float(p.get("yaw", 0.0))))
	for t in fixed.get("towers", []):
		towers.append(t)
	for v in fixed.get("vehicles", []):
		vehicles.append(v)
	for p in fixed.get("props", []):
		props.append(p)
	for r in fixed.get("rows", []):
		rows.append(r)
	for h in src.get("heroes", []):
		_occupy(_obb(_v2(h["pos"]), _v2(h["size"]) + Vector2(6, 6), float(h.get("yaw", 0.0))))
	for b in src.get("fixed_buildings", []):
		_add_building(str(b["fam"]), int(b["var"]), int(b["floors"]), _v2(b["pos"]), float(b.get("yaw", 0.0)), int(b.get("pal", 0)),
			int(b.get("flags", 0)), -1, true)
	for d in src.get("districts", []):
		match str(d["kind"]):
			"towers":
				_gen_towers(d)
			"grid":
				_gen_grid(d)
			"organic":
				_gen_organic(d)
			"slabs":
				_gen_slabs(d)
	for s in src.get("streets", []):
		_street_rec(s)
	return _assemble(fixed)


# ------------------------------------------------------------------ helpers
static func _cm(v) -> float:
	return float(v) / 100.0


static func _v2(a) -> Vector2:
	return Vector2(_cm(a[0]), _cm(a[1]))


static func _rect(a) -> Rect2:
	var p0 := Vector2(_cm(a[0]), _cm(a[1]))
	var p1 := Vector2(_cm(a[2]), _cm(a[3]))
	return Rect2(p0, p1 - p0).abs()


static func _icm(x: float) -> int:
	return int(round(x * 100.0))


func _u(a: int, b: int = 0, c: int = 0, d: int = 0) -> float:
	return WorldConst.unit(WorldConst.hash64(seed_v, GEN_CITY_GEN, a, b, WorldConst.hash64(c, d)))


func _pick_i(lo: int, hi: int, u: float) -> int:
	return lo + mini(int(floor(u * float(hi - lo + 1))), hi - lo)


## Corners of a rectangle `size` centred at `c`, turned by `yaw_deg` (the building frame: world = Basis(UP, yaw) · local).
static func _obb(c: Vector2, size: Vector2, yaw_deg: float) -> PackedVector2Array:
	var a := deg_to_rad(yaw_deg)
	var ax := Vector2(cos(a), -sin(a))     # local +x in world (x, z)
	var az := Vector2(sin(a), cos(a))      # local +z in world
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	return PackedVector2Array([c - ax * hx - az * hz, c + ax * hx - az * hz, c + ax * hx + az * hz, c - ax * hx + az * hz])


static func _bounds(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r


## Separating-axis test of two convex quads.
static func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for poly in [a, b]:
		var n: int = poly.size()
		for i in n:
			var e: Vector2 = poly[(i + 1) % n] - poly[i]
			var ax := Vector2(-e.y, e.x)
			var amin := INF
			var amax := -INF
			for q in a:
				var t := ax.dot(q)
				amin = minf(amin, t)
				amax = maxf(amax, t)
			var bmin := INF
			var bmax := -INF
			for q in b:
				var t := ax.dot(q)
				bmin = minf(bmin, t)
				bmax = maxf(bmax, t)
			if amax <= bmin + 0.01 or bmax <= amin + 0.01:
				return false
	return true


func _cells(r: Rect2) -> Array:
	var out: Array = []
	for cz in range(int(floor(r.position.y / CELL)), int(floor(r.end.y / CELL)) + 1):
		for cx in range(int(floor(r.position.x / CELL)), int(floor(r.end.x / CELL)) + 1):
			out.append(cx * 100000 + cz)
	return out


func _free(q: PackedVector2Array) -> bool:
	var r := _bounds(q)
	for rr in _reserved:
		# reserved rects are axis-aligned: an exact test against the quad
		if rr.intersects(r) and _overlap(q, PackedVector2Array([rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)])):
			return false
	for k in _cells(r):
		for other in _grid.get(k, []):
			if _overlap(q, other):
				return false
	return true


func _occupy(q: PackedVector2Array) -> void:
	for k in _cells(_bounds(q)):
		if not _grid.has(k):
			_grid[k] = []
		(_grid[k] as Array).append(q)


## Terrain height range (max − min) over a footprint (corners, edge midpoints, centre) and water.
func _terrain(q: PackedVector2Array) -> Vector3:
	var lo := INF
	var hi := -INF
	var wet := 0.0
	var pts: Array = []
	for i in q.size():
		pts.append(q[i])
		pts.append((q[i] + q[(i + 1) % q.size()]) * 0.5)
	pts.append((q[0] + q[2]) * 0.5)
	for p in pts:
		var h := hf.height_at(p.x, p.y)
		lo = minf(lo, h)
		hi = maxf(hi, h)
		if hf.is_w1_water(p.x, p.y):
			wet = 1.0
	return Vector3(hi - lo, wet, lo)


## Adds a building lot when its footprint is free, dry and flat enough for its family's skirt. Returns its id or -1.
func _add_building(fam: String, vi: int, floors: int, c: Vector2, yaw: float, pal: int, flags: int, district: int, force: bool = false) -> int:
	var sz := BuildingAssembler.size_of(fam, vi)
	var q := _obb(c, sz, yaw)
	# neighbours in a row touch: the free test shrinks the footprint a little
	if not force and not _free(_obb(c, sz - Vector2(0.3, 0.3), yaw)):
		stats["dropped_overlap"] = int(stats.get("dropped_overlap", 0)) + 1
		return -1
	var t := _terrain(q)
	if t.y > 0.0:
		stats["dropped_water"] = int(stats.get("dropped_water", 0)) + 1
		return -1
	var skirt := float(BuildingAssembler.spec(fam, vi)["skirt"])
	if t.x > skirt - 0.4:
		stats["dropped_slope"] = int(stats.get("dropped_slope", 0)) + 1
		return -1
	if (flags & FLAG_ENT) != 0 and t.x > 0.35:
		flags &= ~FLAG_ENT   # an enterable ground floor needs a level threshold
	var id := int(_next_id["building"])
	_next_id["building"] = id + 1
	_occupy(q)
	buildings.append([id, fam, vi, floors, _icm(c.x), _icm(c.y), int(round(wrapf(yaw, -180.0, 180.0) * 100.0)), pal, flags, district])
	return id


func _seg(a: Vector2, b: Vector2, w: float, kind: int) -> void:
	if a.distance_to(b) < 0.5:
		return
	segs.append([_icm(a.x), _icm(a.y), _icm(b.x), _icm(b.y), _icm(w), kind])


func _node(p: Vector2) -> int:
	var k := "%d|%d" % [int(round(p.x * 0.5)), int(round(p.y * 0.5))]
	if _node_index.has(k):
		return int(_node_index[k])
	nodes.append([_icm(p.x), _icm(p.y)])
	_node_index[k] = nodes.size() - 1
	return nodes.size() - 1


func _edge(a: Vector2, b: Vector2, w: float, kind: int) -> void:
	if a.distance_to(b) < 1.0:
		return
	_raw_edges.append([a, b, w, kind])


## Joins the small parts of the street graph to the largest one by their closest node pair (≤ 60 m: a crossing, a
## plaza, an alley between two districts' nets), until one part holds everything that can be joined.
func _join_components() -> void:
	for _round in 64:
		var comp := _components()
		var sizes := {}
		for c in comp:
			sizes[c] = int(sizes.get(c, 0)) + 1
		if sizes.size() <= 1:
			return
		var big := -1
		for c in sizes:
			if big < 0 or int(sizes[c]) > int(sizes[big]):
				big = c
		var joined := false
		for c in sizes:
			if c == big:
				continue
			var best := INF
			var pair := [-1, -1]
			for i in comp.size():
				if comp[i] != c:
					continue
				var a := Vector2(float(nodes[i][0]), float(nodes[i][1])) / 100.0
				for j in comp.size():
					if comp[j] != big:
						continue
					var d := a.distance_to(Vector2(float(nodes[j][0]), float(nodes[j][1])) / 100.0)
					if d < best:
						best = d
						pair = [i, j]
			if best <= 60.0:
				edges.append([mini(pair[0], pair[1]), maxi(pair[0], pair[1]), 400, 1])
				joined = true
		if not joined:
			return


func _components() -> PackedInt32Array:
	var parent := PackedInt32Array()
	parent.resize(nodes.size())
	for i in nodes.size():
		parent[i] = i
	for e in edges:
		var a := _root(parent, int(e[0]))
		var b := _root(parent, int(e[1]))
		if a != b:
			parent[a] = b
	var out := PackedInt32Array()
	out.resize(nodes.size())
	for i in nodes.size():
		out[i] = _root(parent, i)
	return out


static func _root(parent: PackedInt32Array, x: int) -> int:
	var r := x
	while parent[r] != r:
		r = parent[r]
	return r


## The street graph: every raw street edge split where another one crosses or ends on it (≤ 1.5 m), nodes snapped
## on a 2 m grid, duplicates dropped; O(E²) with E ≈ 500 (offline).
func _build_graph() -> void:
	var n := _raw_edges.size()
	for i in n:
		var e: Array = _raw_edges[i]
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var ts: Array = [0.0, 1.0]
		for j in n:
			if j == i:
				continue
			var f: Array = _raw_edges[j]
			var c: Vector2 = f[0]
			var d: Vector2 = f[1]
			var x: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
			if x != null:
				ts.append((a.distance_to(x as Vector2)) / maxf(a.distance_to(b), 0.001))
			for q in [c, d]:
				var cp := Geometry2D.get_closest_point_to_segment(q, a, b)
				if cp.distance_to(q) <= 1.5:
					ts.append(a.distance_to(cp) / maxf(a.distance_to(b), 0.001))
		ts.sort()
		var prev := a
		for t in ts:
			var p := a.lerp(b, clampf(float(t), 0.0, 1.0))
			if p.distance_to(prev) < 2.0:
				continue
			var ia := _node(prev)
			var ib := _node(p)
			if ia != ib:
				var key := "%d|%d" % [mini(ia, ib), maxi(ia, ib)]
				if not _edge_keys.has(key):
					_edge_keys[key] = true
					edges.append([mini(ia, ib), maxi(ia, ib), _icm(float(e[2])), int(e[3])])
			prev = p


## A street record of the input (`streets`: [x0, z0, x1, z1, road width, walk width, kind]): road + two sidewalks
## (+ a graph edge).
func _street_rec(s: Dictionary) -> void:
	var a := _v2(s["from"])
	var b := _v2(s["to"])
	var road := _cm(s.get("road", 0))
	var walk := _cm(s.get("walk", 0))
	_street(a, b, road, walk, str(s.get("kind", "road")) == "road")


## Road of width `road` along a→b with sidewalks of `walk` on both sides (painted), and its graph edge.
func _street(a: Vector2, b: Vector2, road: float, walk: float, is_road: bool = true) -> void:
	if road > 0.0:
		_seg(a, b, road, SEG_ROAD if is_road else SEG_WALK)
	if walk > 0.0:
		var d := (b - a).normalized()
		var o := Vector2(-d.y, d.x) * (road * 0.5 + walk * 0.5)
		_seg(a + o, b + o, walk, SEG_WALK)
		_seg(a - o, b - o, walk, SEG_WALK)
	_edge(a, b, road + 2.0 * walk, 0 if is_road else 1)


# ------------------------------------------------------------------ Las Torres (supermanzanas + podiums + A1 towers)
func _gen_towers(d: Dictionary) -> void:
	var di := int(_district_of.get(str(d["id"]), -1))
	var cols: Array = d["columns"]
	var rws: Array = d["rows"]
	var street := _cm(d.get("street", 2000))
	var fams: Array = d.get("families", ["tower_a", "tower_b", "tower_c", "tower_d", "tower_e"])
	var families: Dictionary = src.get("fixed", {}).get("families", {})
	var skip: Array[Rect2] = []
	for r in d.get("skip_blocks", []):
		skip.append(_rect(r))
	var bi := 0
	var n_pod := 0
	var n_tow := 0
	for ci in cols.size():
		for ri in rws.size():
			bi += 1
			var blk := Rect2(Vector2(_cm(cols[ci][0]), _cm(rws[ri][0])), Vector2(_cm(cols[ci][1]) - _cm(cols[ci][0]), _cm(rws[ri][1]) - _cm(rws[ri][0])))
			# the block's sidewalk ring (3 m) is painted for every block, built or not
			_ring_walk(blk, 3.0)
			var skipped := false
			for s in skip:
				if s.intersects(blk.grow(-1.0)):
					skipped = true
			if skipped:
				continue
			# podium layout: 4 quadrant podiums on a 112 m block, 2 stacked ones on a narrow block
			var slots: Array = []
			if blk.size.x >= 100.0:
				for sx: float in [-1.0, 1.0]:
					for sz: float in [-1.0, 1.0]:
						slots.append([blk.get_center() + Vector2(sx * 28.0, sz * 20.0), Vector2(50, 32)])
			else:
				for sz: float in [-1.0, 1.0]:
					slots.append([blk.get_center() + Vector2(0, sz * 20.0), Vector2(blk.size.x - 6.0, 32)])
			var styles: Array = d.get("styles", ["concrete", "glass", "brick"])
			for si in slots.size():
				var c: Vector2 = slots[si][0]
				var sz2: Vector2 = slots[si][1]
				if _u(bi, si, 1) < float(d.get("plaza", 0.12)):
					continue   # an open plaza instead of a podium
				var q := _obb(c, sz2, 0.0)
				if not _free(q):
					stats["dropped_podium_overlap"] = int(stats.get("dropped_podium_overlap", 0)) + 1
					continue
				var t := _terrain(q)
				if t.y > 0.0 or t.x > 2.5:
					stats["dropped_podium_terrain"] = int(stats.get("dropped_podium_terrain", 0)) + 1
					continue
				var pid := int(_next_id["podium"])
				_next_id["podium"] = pid + 1
				var pf := _pick_i(1, 3, _u(bi, si, 2))
				var p := {"id": pid, "pos": [_icm(c.x), _icm(c.y)], "size": [_icm(sz2.x), _icm(sz2.y)], "yaw": 0, "floors": pf, "ground_h": 430,
					"floor_h": 380, "style": str(styles[_pick_i(0, styles.size() - 1, _u(bi, si, 3))])}
				if _u(bi, si, 4) < float(d.get("generator", 0.06)):
					p["generator"] = true
				podiums.append(p)
				_occupy(_obb(c, sz2 + Vector2(2, 2), 0.0))
				n_pod += 1
				if _u(bi, si, 5) > float(d.get("tower_chance", 0.8)):
					continue
				var fam := str(fams[_pick_i(0, fams.size() - 1, _u(bi, si, 6))])
				var fd: Dictionary = families[fam]
				var eg: Array = d.get("extra_groups", [0, 4])
				var groups := int(fd["full_groups"]) + _pick_i(int(eg[0]), int(eg[1]), pow(_u(bi, si, 7), 1.3))
				var base_sz := _v2(fd["base"])
				var yaw := float(_pick_i(0, 3, _u(bi, si, 8)) * 90)
				var ext := base_sz if int(yaw) % 180 == 0 else Vector2(base_sz.y, base_sz.x)
				var room := (sz2 - ext) * 0.5 - Vector2(1.5, 1.5)
				var off := Vector2((_u(bi, si, 9) * 2.0 - 1.0) * maxf(room.x, 0.0), (_u(bi, si, 10) * 2.0 - 1.0) * maxf(room.y, 0.0))
				var tp := c + off
				var tid := int(_next_id["tower"])
				_next_id["tower"] = tid + 1
				var tw := {"id": tid, "family": fam, "groups": groups, "on": pid, "pos": [_icm(tp.x), _icm(tp.y)], "yaw": int(yaw)}
				if p.has("generator"):
					tw["generator"] = true
				towers.append(tw)
				n_tow += 1
	# the streets between the columns / rows (+ graph), from the rules
	var x0 := _cm(cols[0][0]) - street * 0.5
	var x1 := _cm(cols[cols.size() - 1][1]) + street * 0.5
	for ri in rws.size() - 1:
		var zc := (_cm(rws[ri][1]) + _cm(rws[ri + 1][0])) * 0.5
		if absf(zc - (-384.0)) < 25.0:
			continue   # the Gran Vía (macro road)
		_street(Vector2(x0, zc), Vector2(x1, zc), street - 6.0, 0.0)
	var z0 := _cm(rws[0][0]) - street * 0.5
	var z1 := _cm(rws[rws.size() - 1][1]) + street * 0.5
	for ci in cols.size() - 1:
		var xc := (_cm(cols[ci][1]) + _cm(cols[ci + 1][0])) * 0.5
		_street(Vector2(xc, z0), Vector2(xc, -406.0), street - 6.0, 0.0)
		_street(Vector2(xc, -362.0), Vector2(xc, z1), street - 6.0, 0.0)
	stats["las_torres"] = {"podiums": n_pod, "towers": n_tow}


## Sidewalk ring (w m wide) just outside a rect (painted, packed snow).
func _ring_walk(r: Rect2, w: float) -> void:
	var g := r.grow(w * 0.5)
	var c := [g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]
	for i in 4:
		_seg(c[i], c[(i + 1) % 4], w, SEG_WALK)


# ------------------------------------------------------------------ ensanche (manzanas cerradas con chaflán)
func _gen_grid(d: Dictionary) -> void:
	var di := int(_district_of.get(str(d["id"]), -1))
	var block := _cm(d.get("block", 9600))
	var street := _cm(d.get("street", 1800))
	var road := _cm(d.get("road", 1200))
	var ch := _cm(d.get("chaflan", 850))
	var pitch := block + street
	var excl: Array[Rect2] = []
	for e in d.get("exclude", []):
		excl.append(_rect(e))
	var gv_n := _cm(d.get("avenue_north", -40600))
	var gv_s := _cm(d.get("avenue_south", -36200))
	var widths := [15.0, 18.0, 21.0, 24.0]
	var fl: Array = d.get("floors", [5, 8])
	var ent_share := float(d.get("enterable", 0.3))
	var gen_share := float(d.get("generator", 0.03))
	var built := 0
	var lots := 0
	var bi := 0
	# a district may hold several grids: the main one (origin + pitch) and strips with explicit columns (the ensanche
	# north and south of Las Torres keeps Las Torres' columns and streets)
	for gd in d.get("grids", [d]):
		var rect := _rect(gd["rect"])
		var cols: Array = []   # [x0, x1] (m)
		if gd.has("columns"):
			for c in gd["columns"]:
				cols.append([_cm(c[0]), _cm(c[1])])
		else:
			var x := _cm(gd["origin_x"])
			while x + block <= rect.end.x + 0.01:
				cols.append([x, x + block])
				x += pitch
		var zs: Array = []
		var z := gv_n
		while z - block >= rect.position.y - 0.01:
			zs.append(z - block)
			z -= pitch
		z = gv_s
		while z + block <= rect.end.y + 0.01:
			zs.append(z)
			z += pitch
		zs.sort()
		for zi in zs.size():
			for xi in cols.size():
				bi += 1
				var bx0 := float(cols[xi][0])
				var bx1 := float(cols[xi][1])
				var blk := Rect2(Vector2(bx0, float(zs[zi])), Vector2(bx1 - bx0, block))
				var out := false
				for e in excl:
					if e.intersects(blk.grow(-0.5)):
						out = true
				if out:
					continue
				var reserved := false
				for ri in _reserved.size():
					if _reserved[ri].grow(_reserved_grow[ri]).intersects(blk.grow(-0.5)):
						reserved = true
						var rs: Dictionary = stats.get("reserved_blocks", {})
						rs[str(ri)] = int(rs.get(str(ri), 0)) + 1
						stats["reserved_blocks"] = rs
				# sidewalks around the block (with the chaflanes) are painted even for a reserved block (a C2 hero pad)
				_chamfer_walk(blk, ch, (street - road) * 0.5)
				if reserved:
					continue
				built += 1
				lots += _manzana(blk, bi, fl, widths, ent_share, gen_share, di)
		# streets: the grid lines between the columns / rows (roads + graph), clipped to the grid rect
		for xi in cols.size() - 1:
			var xc := (float(cols[xi][1]) + float(cols[xi + 1][0])) * 0.5
			_grid_line(Vector2(xc, rect.position.y), Vector2(xc, rect.end.y), road, excl, gv_n, gv_s, true)
		if not cols.is_empty():
			var xw := float(cols[0][0]) - street * 0.5
			_grid_line(Vector2(xw, rect.position.y), Vector2(xw, rect.end.y), road, excl, gv_n, gv_s, true)
			var xe := float(cols[cols.size() - 1][1]) + street * 0.5
			_grid_line(Vector2(xe, rect.position.y), Vector2(xe, rect.end.y), road, excl, gv_n, gv_s, true)
		var zl: Array = []
		for zi in zs.size():
			zl.append(float(zs[zi]) - street * 0.5)
		if not zs.is_empty():
			zl.append(float(zs[zs.size() - 1]) + block + street * 0.5)
		for zc in zl:
			if float(zc) > gv_n - street and float(zc) < gv_s + street:
				continue   # the Gran Vía
			_grid_line(Vector2(rect.position.x, float(zc)), Vector2(rect.end.x, float(zc)), road, excl, gv_n, gv_s, false)
		# the Gran Vía's sidewalks through this grid
		_seg(Vector2(rect.position.x, gv_n + 5.0), Vector2(rect.end.x, gv_n + 5.0), 10.0, SEG_WALK)
		_seg(Vector2(rect.position.x, gv_s - 5.0), Vector2(rect.end.x, gv_s - 5.0), 10.0, SEG_WALK)
	stats["ensanche"] = {"blocks": built, "lots": lots}


## One manzana cerrada: the four chaflán corner lots and the frontage lots of each side (widths from `widths`).
func _manzana(blk: Rect2, bi: int, fl: Array, widths: Array, ent_share: float, gen_share: float, di: int) -> int:
	var lots := 0
	var base_f := _pick_i(int(fl[0]), int(fl[1]), _u(bi, 11))
	# 4 corners (chaflán lots): SE yaw 0, NE 90, NW 180, SW −90; the lot centre half a lot inside both edges
	var corner := BuildingAssembler.size_of("ensanche", 4)
	var hc := corner.x * 0.5
	var cs := [[Vector2(blk.end.x - hc, blk.end.y - hc), 0.0], [Vector2(blk.end.x - hc, blk.position.y + hc), 90.0],
		[Vector2(blk.position.x + hc, blk.position.y + hc), 180.0], [Vector2(blk.position.x + hc, blk.end.y - hc), -90.0]]
	for k in 4:
		var f := clampi(base_f + (1 if _u(bi, 12, k) < 0.35 else 0), int(fl[0]), int(fl[1]))
		var flags := (FLAG_ENT if _u(bi, 13, k) < ent_share else 0) | (FLAG_GEN if _u(bi, 14, k) < gen_share else 0)
		if _add_building("ensanche", 4, f, cs[k][0], float(cs[k][1]), _pick_i(0, 4, _u(bi, 15, k)), flags, di) >= 0:
			lots += 1
	# the four sides between the corner lots, filled with 15–24 m lots
	var depth := BuildingAssembler.size_of("ensanche", 0).y
	var sides := [
		[Vector2(blk.end.x - corner.x, blk.end.y), Vector2(-1, 0), 0.0, blk.size.x],          # south side, front +z, runs west
		[Vector2(blk.end.x, blk.position.y + corner.x), Vector2(0, 1), 90.0, blk.size.y],       # east side, front +x, runs south
		[Vector2(blk.position.x + corner.x, blk.position.y), Vector2(1, 0), 180.0, blk.size.x], # north side, front −z, runs east
		[Vector2(blk.position.x, blk.end.y - corner.x), Vector2(0, -1), -90.0, blk.size.y],     # west side, front −x, runs north
	]
	for si in 4:
		var start: Vector2 = sides[si][0]
		var dir: Vector2 = sides[si][1]
		var yaw := float(sides[si][2])
		var run := float(sides[si][3]) - 2.0 * corner.x
		var to_c := (blk.get_center() - (start + dir * run * 0.5)).normalized()
		var inward := Vector2(roundf(to_c.x), roundf(to_c.y))
		var seq := _fill(run, widths, bi * 8 + si)
		var u := (run - _sum(seq)) * 0.5
		for li in seq.size():
			var w: float = seq[li]
			var c: Vector2 = start + dir * (u + w * 0.5) + inward * depth * 0.5
			u += w
			var vi := widths.find(w)
			var f := clampi(base_f + (-1 if _u(bi, 16 + si, li) < 0.25 else 0), int(fl[0]), int(fl[1]))
			var flags := (FLAG_ENT if _u(bi, 20 + si, li) < ent_share else 0) | (FLAG_GEN if _u(bi, 24 + si, li) < gen_share else 0)
			if _add_building("ensanche", vi, f, c, yaw, _pick_i(0, 4, _u(bi, 28 + si, li)), flags, di) >= 0:
				lots += 1
	return lots


## A straight grid street from a to b split around the exclusion rects and the Gran Vía corridor (vertical lines).
func _grid_line(a: Vector2, b: Vector2, road: float, excl: Array[Rect2], gv_n: float, gv_s: float, vertical: bool) -> void:
	var pieces: Array = [[a, b]]
	if vertical:
		pieces = [[a, Vector2(a.x, gv_n)], [Vector2(a.x, gv_s), b]]
	for pc in pieces:
		var p0: Vector2 = pc[0]
		var p1: Vector2 = pc[1]
		# clip against the exclusions (axis-aligned): keep the parts outside
		var parts: Array = [[p0, p1]]
		for e in excl:
			var next: Array = []
			for pr in parts:
				next.append_array(_clip_out(pr[0], pr[1], e.grow(-2.0)))
			parts = next
		for pr in parts:
			_street(pr[0], pr[1], road, 0.0)


## Parts of the axis-aligned segment a→b outside rect r.
static func _clip_out(a: Vector2, b: Vector2, r: Rect2) -> Array:
	var vertical := absf(a.x - b.x) < 0.01
	var fixed := a.x if vertical else a.y
	var lo := minf(a.y, b.y) if vertical else minf(a.x, b.x)
	var hi := maxf(a.y, b.y) if vertical else maxf(a.x, b.x)
	var inside_fixed := (fixed > r.position.x and fixed < r.end.x) if vertical else (fixed > r.position.y and fixed < r.end.y)
	var r0 := r.position.y if vertical else r.position.x
	var r1 := r.end.y if vertical else r.end.x
	if not inside_fixed or r1 <= lo or r0 >= hi:
		return [[a, b]]
	var out: Array = []
	if r0 > lo:
		out.append([Vector2(fixed, lo), Vector2(fixed, r0)] if vertical else [Vector2(lo, fixed), Vector2(r0, fixed)])
	if r1 < hi:
		out.append([Vector2(fixed, r1), Vector2(fixed, hi)] if vertical else [Vector2(r1, fixed), Vector2(hi, fixed)])
	return out


## Sidewalk around a manzana with chamfered corners (the chaflán legs `ch`), `w` wide outside the block edge.
func _chamfer_walk(blk: Rect2, ch: float, w: float) -> void:
	var g := blk.grow(w * 0.5)
	var c := ch + w * 0.2
	var pts := [Vector2(g.position.x + c, g.position.y), Vector2(g.end.x - c, g.position.y), Vector2(g.end.x, g.position.y + c),
		Vector2(g.end.x, g.end.y - c), Vector2(g.end.x - c, g.end.y), Vector2(g.position.x + c, g.end.y), Vector2(g.position.x, g.end.y - c),
		Vector2(g.position.x, g.position.y + c)]
	for i in pts.size():
		_seg(pts[i], pts[(i + 1) % pts.size()], w, SEG_WALK)


## A sequence of widths from `widths` whose sum is the largest ≤ run (≥ run − 3 m), picked by hash.
func _fill(run: float, widths: Array, salt: int) -> Array:
	var options: Array = []
	_fill_rec(run, widths, [], options)
	if options.is_empty():
		return [widths[0]]
	var best := -INF
	for o in options:
		best = maxf(best, _sum(o))
	var good: Array = []
	for o in options:
		if _sum(o) >= best - 0.01:
			good.append(o)
	return good[_pick_i(0, good.size() - 1, _u(salt, 31))]


func _fill_rec(left: float, widths: Array, cur: Array, out: Array) -> void:
	var any := false
	for w in widths:
		if float(w) <= left + 0.01:
			any = true
			var nxt := cur.duplicate()
			nxt.append(float(w))
			if out.size() < 400:
				_fill_rec(left - float(w), widths, nxt, out)
	if not any and not cur.is_empty():
		out.append(cur)


static func _sum(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += float(v)
	return t


# ------------------------------------------------------------------ casco viejo (organic)
func _gen_organic(d: Dictionary) -> void:
	var di := int(_district_of.get(str(d["id"]), -1))
	var rect := _rect(d["rect"])
	var sp := _v2(d.get("spacing", [5800, 5000]))
	var jit := _cm(d.get("jitter", 1100))
	var w_small := _cm((d.get("street", [650, 800]) as Array)[0])
	var w_main := _cm((d.get("street", [650, 800]) as Array)[1])
	var main_every := int(d.get("main_every", 3))
	var gv_n := _cm(d.get("avenue_north", -40600))
	var gv_s := _cm(d.get("avenue_south", -36200))
	var plazas: Array[Rect2] = []
	for p in d.get("plazas", []):
		plazas.append(_rect(p))
	var plaza_share := float(d.get("plaza_share", 0.05))
	var ent_share := float(d.get("enterable", 0.2))
	var gen_share := float(d.get("generator", 0.02))
	var arcade_share := float(d.get("arcade", 0.5))
	var fl: Array = d.get("floors", [3, 4])
	var n_lots := 0
	var n_blocks := 0
	# two lattices: north of the Gran Vía (rect.z0 … gv_n) and south of it (gv_s … rect.z1)
	for part in [[rect.position.y, gv_n], [gv_s, rect.end.y]]:
		var z0 := float(part[0])
		var z1 := float(part[1])
		var nx := maxi(1, int(round(rect.size.x / sp.x)))
		var nz := maxi(1, int(round((z1 - z0) / sp.y)))
		var dx := rect.size.x / float(nx)
		var dz := (z1 - z0) / float(nz)
		var pts: Array = []   # (nz + 1) rows × (nx + 1)
		for j in nz + 1:
			for i in nx + 1:
				var p := Vector2(rect.position.x + dx * float(i), z0 + dz * float(j))
				var jx := (_u(i, j, int(z0), 1) * 2.0 - 1.0) * jit
				var jz := (_u(i, j, int(z0), 2) * 2.0 - 1.0) * jit
				if i > 0 and i < nx:
					p.x += jx
				if j > 0 and j < nz:
					p.y += jz
				pts.append(p)
		var at := func(i: int, j: int) -> Vector2: return pts[j * (nx + 1) + i]
		# streets: the lattice edges (every `main_every` line a main street)
		for j in nz + 1:
			for i in nx:
				var main := j % main_every == 0 or j == 0 or j == nz
				var a: Vector2 = at.call(i, j)
				var b: Vector2 = at.call(i + 1, j)
				if (j == nz and absf(z1 - gv_n) < 0.1) or (j == 0 and absf(z0 - gv_s) < 0.1):
					_edge(a, b, 24.0, 0)   # the Gran Vía edge: graph only (the macro road paints it)
					continue
				_street(a, b, w_main if main else w_small, 0.0, main)
		for i in nx + 1:
			for j in nz:
				var main := i % main_every == 0 or i == 0 or i == nx
				var a: Vector2 = at.call(i, j)
				var b: Vector2 = at.call(i, j + 1)
				_street(a, b, w_main if main else w_small, 0.0, main)
		# blocks
		for j in nz:
			for i in nx:
				var q := PackedVector2Array([at.call(i, j), at.call(i + 1, j), at.call(i + 1, j + 1), at.call(i, j + 1)])
				var widths_e: Array = []
				for e in 4:
					var main: bool
					if e % 2 == 0:
						var jj := j if e == 0 else j + 1
						main = jj % main_every == 0 or jj == 0 or jj == nz
					else:
						var ii := i + 1 if e == 1 else i
						main = ii % main_every == 0 or ii == 0 or ii == nx
					widths_e.append((w_main if main else w_small) * 0.5 + 0.5)
				var inner := _inset_quad(q, widths_e)
				if inner.is_empty():
					continue
				var bb := _bounds(inner)
				var is_plaza := _u(i, j, int(z0), 7) < plaza_share
				for p in plazas:
					if p.has_point(bb.get_center()):
						is_plaza = true
				if is_plaza:
					_seg(bb.get_center() - Vector2(bb.size.x * 0.5 - 2.0, 0), bb.get_center() + Vector2(bb.size.x * 0.5 - 2.0, 0), bb.size.y - 4.0, SEG_PLAZA)
					continue
				n_blocks += 1
				n_lots += _block_lots(inner, i, j, int(z0), fl, ent_share, gen_share, arcade_share, di, plazas)
	stats["casco_viejo"] = {"blocks": n_blocks, "lots": n_lots}


## Quad inset by per-edge distances (edge e from q[e] to q[e+1]); [] when degenerate.
static func _inset_quad(q: PackedVector2Array, ins: Array) -> PackedVector2Array:
	var n := q.size()
	# orientation: make the lines move toward the centroid
	var c := Vector2.ZERO
	for p in q:
		c += p
	c /= float(n)
	var lines: Array = []
	for i in n:
		var a := q[i]
		var b := q[(i + 1) % n]
		var dd := (b - a).normalized()
		var nn := Vector2(-dd.y, dd.x)
		if nn.dot(c - a) < 0.0:
			nn = -nn
		lines.append([a + nn * float(ins[i]), dd])
	var out := PackedVector2Array()
	for i in n:
		var l0: Array = lines[(i - 1 + n) % n]
		var l1: Array = lines[i]
		var p0: Vector2 = l0[0]
		var d0: Vector2 = l0[1]
		var p1: Vector2 = l1[0]
		var d1: Vector2 = l1[1]
		var den := d0.x * d1.y - d0.y * d1.x
		if absf(den) < 1e-5:
			return PackedVector2Array()
		var tt := ((p1.x - p0.x) * d1.y - (p1.y - p0.y) * d1.x) / den
		out.append(p0 + d0 * tt)
	# degenerate (inverted or too small) blocks: no lots
	if signf(_area(out)) != signf(_area(q)):
		return PackedVector2Array()
	for i in n:
		if out[(i + 1) % n].distance_to(out[i]) < 12.0:
			return PackedVector2Array()
	return out


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return a * 0.5


## Lots along the four edges of a casco block (the inset quad): edges 0 / 2 run corner to corner, edges 1 / 3 leave
## the corners to them; widths 6–12 m, 11 m deep, fronts facing the street; overlaps dropped.
func _block_lots(q: PackedVector2Array, i: int, j: int, salt: int, fl: Array, ent_share: float, gen_share: float, arcade_share: float, di: int, plazas: Array[Rect2]) -> int:
	var made := 0
	var depth := BuildingAssembler.size_of("casco", 0).y
	var c := (q[0] + q[1] + q[2] + q[3]) * 0.25
	var widths := [6.0, 8.0, 10.0, 12.0]
	for e in 4:
		var a := q[e]
		var b := q[(e + 1) % 4]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var inward := Vector2(-dir.y, dir.x)
		if inward.dot(c - a) < 0.0:
			inward = -inward
		var t0 := 0.0 if e % 2 == 0 else depth + 0.4
		var t1 := length if e % 2 == 0 else length - depth - 0.4
		var yaw := rad_to_deg(atan2(-inward.x, -inward.y))   # the front (+z local) faces out of the block
		var near_plaza := false
		for p in plazas:
			if p.grow(14.0).has_point((a + b) * 0.5):
				near_plaza = true
		var u := t0
		var li := 0
		while u < t1 - 5.9:
			var left := t1 - u
			var w: float = widths[_pick_i(0, 3, _u(i * 131 + j, salt, e * 64 + li, 41))]
			if w > left:
				w = 6.0 if left < 8.0 else (8.0 if left < 10.0 else 10.0)
			var vi := widths.find(w)
			if near_plaza and w == 10.0 and _u(i, j, e * 64 + li, 42) < arcade_share:
				vi = 4
			var f := _pick_i(int(fl[0]), int(fl[1]), _u(i, j, e * 64 + li, 43))
			var flags := (FLAG_ENT if _u(i, j, e * 64 + li, 44) < ent_share else 0) | (FLAG_GEN if _u(i, j, e * 64 + li, 45) < gen_share else 0)
			# the whole footprint inside the block quad: at an acute corner a narrower house, or the same one a metre
			# along, before giving up (the corners of the old town stay built)
			var tries := 0
			while tries < 6:
				tries += 1
				var centre := a + dir * (u + w * 0.5) + inward * (depth * 0.5)
				var ob := _obb(centre, Vector2(w, depth), yaw)
				var inside := true
				for p in ob:
					if not Geometry2D.is_point_in_polygon(p, q):
						inside = false
				if inside:
					if _add_building("casco", vi, f, centre, yaw, _pick_i(0, 5, _u(i, j, e * 64 + li, 46)), flags, di) >= 0:
						made += 1
					break
				if w > 6.0:
					w -= 2.0
					vi = widths.find(w)
				elif u + w + 1.0 < t1:
					u += 1.0
				else:
					break
			u += w + (1.5 if _u(i, j, e * 64 + li, 47) < 0.12 else 0.0)   # now and then an alley gap
			li += 1
	return made


# ------------------------------------------------------------------ barriada (open blocks in a park)
func _gen_slabs(d: Dictionary) -> void:
	var di := int(_district_of.get(str(d["id"]), -1))
	var rect := _rect(d["rect"])
	var sup := _cm(d.get("super", 12000))
	var street := _cm(d.get("street", 1200))
	var road := _cm(d.get("road", 800))
	var fl: Array = d.get("floors", [8, 14])
	var ent_share := float(d.get("enterable", 0.1))
	var gen_share := float(d.get("generator", 0.04))
	var pitch := sup + street
	var nx := int(floor((rect.size.x + street) / pitch))
	var nz := int(floor((rect.size.y + street) / pitch))
	var ox := rect.position.x + (rect.size.x - (float(nx) * pitch - street)) * 0.5
	var oz := rect.position.y + (rect.size.y - (float(nz) * pitch - street)) * 0.5
	var n_slabs := 0
	for j in nz:
		for i in nx:
			var sb := Rect2(Vector2(ox + float(i) * pitch, oz + float(j) * pitch), Vector2(sup, sup))
			var pattern := _pick_i(0, 3, _u(i, j, 51))
			var items: Array = []   # [variant, centre, yaw]
			var cc := sb.get_center()
			match pattern:
				0:   # three long slabs along x, fronts facing south
					var vi := _pick_i(1, 2, _u(i, j, 52))
					items = [[vi, cc + Vector2(0, -38), 0.0], [vi, cc + Vector2(0, 0), 0.0], [vi, cc + Vector2(0, 38), 0.0]]
				1:   # three slabs along z (turned), fronts facing east / west
					var vi := _pick_i(1, 2, _u(i, j, 53))
					items = [[vi, cc + Vector2(-38, 0), -90.0], [vi, cc + Vector2(0, 0), 90.0], [vi, cc + Vector2(38, 0), 90.0]]
				2:   # an L of slabs around a garden and a point block
					items = [[2, cc + Vector2(0, -40), 0.0], [1, cc + Vector2(-40, 12), -90.0], [3, cc + Vector2(20, 22), 0.0]]
				3:   # a long slab and three point blocks
					items = [[2, cc + Vector2(0, -38), 0.0], [3, cc + Vector2(-36, 20), 0.0], [3, cc + Vector2(0, 26), 0.0], [3, cc + Vector2(36, 20), 0.0]]
			for k in items.size():
				var it: Array = items[k]
				var f := _pick_i(int(fl[0]), int(fl[1]), _u(i, j, 60 + k))
				if int(it[0]) == 3:
					f = maxi(f, 12)
				var flags := (FLAG_ENT if _u(i, j, 70 + k) < ent_share else 0) | (FLAG_GEN if _u(i, j, 80 + k) < gen_share else 0)
				var id := _add_building("bloque", int(it[0]), f, it[1], float(it[2]), _pick_i(0, 3, _u(i, j, 90 + k)), flags, di)
				if id >= 0:
					n_slabs += 1
					# a packed-snow apron around the slab (paths in the park)
					var sz := BuildingAssembler.size_of("bloque", int(it[0]))
					var ext := sz if absf(float(it[2])) < 1.0 or absf(absf(float(it[2])) - 180.0) < 1.0 else Vector2(sz.y, sz.x)
					_ring_walk(Rect2((it[1] as Vector2) - ext * 0.5, ext), 2.0)
			# the superblock's access road on its south and east sides (+ graph)
	for j in nz + 1:
		var zc := oz + float(j) * pitch - street * 0.5
		_street(Vector2(rect.position.x, zc), Vector2(rect.end.x, zc), road, 0.0)
	for i in nx + 1:
		var xc := ox + float(i) * pitch - street * 0.5
		_street(Vector2(xc, rect.position.y), Vector2(xc, rect.end.y), road, 0.0)
	stats["barriada"] = {"slabs": n_slabs, "superblocks": nx * nz}


# ------------------------------------------------------------------ output
func _assemble(fixed: Dictionary) -> Dictionary:
	for r in src.get("graph_roads", []):
		_edge(_v2(r["from"]), _v2(r["to"]), _cm(r.get("width", 2400)), 0)
	_build_graph()
	_join_components()
	var out := {}
	out["format"] = FORMAT
	out["city_version"] = int(src.get("city_version", 1))
	out["milestone"] = "C1"
	out["units"] = "cm (integers) for positions and sizes; yaw in degrees (items) or centidegrees (buildings rows); x east, z south, world coordinates"
	out["doc"] = "C1 «Altavega: núcleo urbano»: GENERATED by tools/gen_city.gd from data/world/city/districts.json (do not edit; regenerate). Read by CityLots (scripts/world/city/city_lots.gd): the ChunkJob takes the items whose centre falls in its chunk."
	for k in ["block", "families", "bridge", "jams", "models"]:
		if fixed.has(k):
			out[k] = fixed[k]
	out["podiums"] = podiums
	out["towers"] = towers
	out["vehicles"] = vehicles
	out["props"] = props
	out["rows"] = rows
	out["heroes"] = src.get("heroes", [])
	out["buildings"] = {"fields": FIELDS, "rows": buildings}
	out["streets"] = {"fields": SEG_FIELDS, "rows": segs, "kinds": ["road", "walk", "plaza"]}
	out["graph"] = {"nodes": nodes, "edges": edges}
	out["districts"] = src.get("zones", [])
	out["clear"] = src.get("clear", [])
	out["camera_zones"] = src.get("camera_zones", [])
	out["miradores"] = src.get("miradores", [])
	out["power"] = _power()
	out["silhouettes"] = src.get("silhouettes", {})
	out["dressing"] = src.get("dressing", {})   # street lamps / parked cars / sidewalk furniture per district (CityLots)
	var fam_n := {}
	var ent := 0
	for b in buildings:
		fam_n[str(b[1])] = int(fam_n.get(str(b[1]), 0)) + 1
		if int(b[8]) & FLAG_ENT != 0:
			ent += 1
	stats["buildings"] = buildings.size()
	stats["by_family"] = fam_n
	stats["enterable"] = ent
	stats["podiums"] = podiums.size()
	stats["towers"] = towers.size()
	stats["segments"] = segs.size()
	stats["graph"] = [nodes.size(), edges.size()]
	out["stats"] = stats
	return out


## Power of the city v1: the grid is down (blackout); generator lots (flag) and the listed rects are powered.
func _power() -> Dictionary:
	var p: Dictionary = (src.get("power", {}) as Dictionary).duplicate(true)
	var gens: Array = p.get("generators", []).duplicate()
	for b in buildings:
		if int(b[8]) & FLAG_GEN != 0:
			gens.append(int(b[0]))
	for pd in podiums:
		if bool(pd.get("generator", false)) and not gens.has(int(pd["id"])):
			gens.append(int(pd["id"]))
	gens.sort()
	p["generators"] = gens
	return p


# ------------------------------------------------------------------ canonical text
## Whole floats (what JSON parsing gives for every number of the input) become ints: `265200`, never `265200.0`.
static func ints(v: Variant) -> Variant:
	if v is float:
		var f: float = v
		if is_finite(f) and absf(f) < 9.0e15 and f == floorf(f):
			return int(f)
		return f
	if v is Array:
		var a: Array = []
		for e in v:
			a.append(ints(e))
		return a
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = ints(v[k])
		return d
	return v


## One JSON document with sorted keys, every top-level key on its own line and one building / street row per line
## (readable diffs; the same bytes on every platform).
static func serialize(p_out: Dictionary) -> String:
	var out: Dictionary = ints(p_out)
	var keys := out.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		var v: Variant = out[k]
		var txt := ""
		if k in ["buildings", "streets"] and v is Dictionary:
			var sub := PackedStringArray()
			var sk := (v as Dictionary).keys()
			sk.sort()
			for s in sk:
				if s == "rows":
					var lines := PackedStringArray()
					for r in v[s]:
						lines.append(JSON.stringify(r))
					sub.append("\"rows\": [\n  %s\n ]" % ",\n  ".join(lines))
				else:
					sub.append("%s: %s" % [JSON.stringify(s), JSON.stringify(v[s], "", true)])
			txt = "{\n " + ",\n ".join(sub) + "\n}"
		elif v is Array and (v as Array).size() > 8:
			var lines := PackedStringArray()
			for r in v:
				lines.append(JSON.stringify(r, "", true))
			txt = "[\n  " + ",\n  ".join(lines) + "\n ]"
		else:
			txt = JSON.stringify(v, "", true)
		parts.append("%s: %s" % [JSON.stringify(k), txt])
	return "{\n" + ",\n".join(parts) + "\n}\n"
