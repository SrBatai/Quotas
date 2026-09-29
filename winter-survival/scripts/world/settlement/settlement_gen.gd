class_name SettlementGen
extends RefCounted
## Procedural village generator (M6b; ARQ v2 §9.1 steps 2, 4–6, PLAN §7 M6b): a pure function of the world seed and a
## site definition (res://data/buildings/settlements/<id>.json), identical on the server and every client (integer
## hashes: WorldConst.hash64 / unit; no Dictionary iteration order; fixed loops). Output = a plan (Dictionary):
##   streets    a main street leaving the access road + 1–2 branches (the lane toward a hand-made POI is one of them),
##              as road records for HeightFunction.add_road (asphalt beds, profile pinned to the road they join);
##   lots       OBB lots of 400–900 m² along both sides of every street (frontage 17–26 m), rejected when they meet a
##              street, the access road, another lot, a keep-out rect, the site bounds or the region circle;
##   buildings  land use 80/10/5/5 (houses / shops / services / empty, ARQ §9.1 aldea): the reserved uses (bar, shop,
##              garage) on the most central lots that fit, then houses by weighted templates that fit the lot, a
##              target of 15–20 buildings (the rest stay empty lots), ≥ enterable_min enterable (45 % of the houses,
##              every shop / service; the others keep their doors locked); each building faces its street, stands
##              on a level pad (HeightFunction.add_pad) at the height of the street in front of it;
##   items      street dressing: lamps, power poles (+ wires), mailboxes, fences, hydrants, benches, bins, a dumpster
##              (loot), a bus stop, barricades, the village sign, street name plates, a stop sign, and 3–5 abandoned
##              cars (A1 wrecks with a loot container);
##   residents  zombies per building by use (+ the street share per chunk), read by PopulationTable / Manager.
## Compass angles in the data: 0 = north (−Z), 90 = east (+X). Building yaw (degrees) is the KitBuilding rotation.y:
## its front (+Z of the model) looks at the street.

const GEN := 0x53455454            # "SETT"
const TEMPLATES_DIR := "res://data/buildings/templates/"
## Porch (2 m) + steps in front of a template that has one.
const PORCH := 3.0
const PAD_MARGIN := 2.5
const PAD_BLEND := 5.0

static var _tpl_cache: Dictionary = {}


# ------------------------------------------------------------------ deterministic stream
class Rng:
	extends RefCounted
	var a: int = 0
	var b: int = 0
	var k: int = 0

	func _init(p_a: int, p_b: int) -> void:
		a = p_a
		b = p_b

	func f() -> float:
		k += 1
		return WorldConst.unit(WorldConst.hash64(a, SettlementGen.GEN, b, k))

	func rng(lo: float, hi: float) -> float:
		return lo + (hi - lo) * f()

	func ri(lo: int, hi: int) -> int:
		return mini(lo + int(f() * float(hi - lo + 1)), hi)

	func pick_w(weights: Array) -> int:
		var tot := 0.0
		for w in weights:
			tot += float(w)
		var x := f() * tot
		for i in weights.size():
			x -= float(weights[i])
			if x < 0.0:
				return i
		return weights.size() - 1


# ------------------------------------------------------------------ templates (data/buildings/templates/<id>.json)
static func template(id: String) -> Dictionary:
	if not _tpl_cache.has(id):
		var d: Dictionary = {}
		var path := TEMPLATES_DIR + id + ".json"
		if FileAccess.file_exists(path):
			var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if v is Dictionary:
				d = v
		_tpl_cache[id] = d
	return _tpl_cache[id]


## Vector3(W, D, porch depth in front) of a template (zero when unknown).
static func footprint(id: String) -> Vector3:
	var t := template(id)
	if t.is_empty():
		return Vector3.ZERO
	var fp: Array = t.get("footprint", [8, 10])
	return Vector3(float(fp[0]), float(fp[1]), PORCH if t.has("porch") else 0.6)


static func styles_of(id: String) -> Array:
	return template(id).get("style", ["wood_blue"])


# ------------------------------------------------------------------ geometry helpers
static func v2(a: Variant) -> Vector2:
	var arr: Array = a
	return Vector2(float(arr[0]), float(arr[1]))


## Unit vector of a compass angle (radians; 0 = north = −Z, π/2 = east = +X).
static func compass(a: float) -> Vector2:
	return Vector2(sin(a), -cos(a))


static func poly_length(pts: PackedVector2Array) -> float:
	var t := 0.0
	for i in pts.size() - 1:
		t += pts[i].distance_to(pts[i + 1])
	return t


## [point, unit tangent] at arc length s.
static func point_at(pts: PackedVector2Array, s: float) -> Array:
	var acc := 0.0
	for i in pts.size() - 1:
		var l := pts[i].distance_to(pts[i + 1])
		if acc + l >= s or i == pts.size() - 2:
			var t := (pts[i + 1] - pts[i]) / maxf(l, 0.001)
			return [pts[i].lerp(pts[i + 1], clampf((s - acc) / maxf(l, 0.001), 0.0, 1.0)), t]
		acc += l
	return [pts[pts.size() - 1], Vector2.UP]


## Yaw (radians, about +Y) that turns a model's +Z onto the world direction `d` (x, z).
static func yaw_to(d: Vector2) -> float:
	return atan2(d.x, d.y)


## Yaw (radians) that lays a model's +X (a fence / barrier section) along the world direction `d` (x, z).
static func along(d: Vector2) -> float:
	return atan2(-d.y, d.x)


static func obb(c: Vector2, u: Vector2, h: Vector2) -> Dictionary:
	return {"c": c, "u": u.normalized(), "h": h}


static func _proj(o: Dictionary, axis: Vector2) -> float:
	var u: Vector2 = o["u"]
	var v := Vector2(-u.y, u.x)
	var h: Vector2 = o["h"]
	return absf(u.dot(axis)) * h.x + absf(v.dot(axis)) * h.y


## True when two OBBs overlap (separating axis test), grown by `margin`.
static func obb_overlap(a: Dictionary, b: Dictionary, margin: float = 0.0) -> bool:
	var d: Vector2 = (b["c"] as Vector2) - (a["c"] as Vector2)
	var ua: Vector2 = a["u"]
	var ub: Vector2 = b["u"]
	for axis in [ua, Vector2(-ua.y, ua.x), ub, Vector2(-ub.y, ub.x)]:
		if absf(d.dot(axis)) > _proj(a, axis) + _proj(b, axis) + margin:
			return false
	return true


static func obb_corners(o: Dictionary) -> Array[Vector2]:
	var c: Vector2 = o["c"]
	var u: Vector2 = o["u"]
	var v := Vector2(-u.y, u.x)
	var h: Vector2 = o["h"]
	return [c + u * h.x + v * h.y, c - u * h.x + v * h.y, c - u * h.x - v * h.y, c + u * h.x - v * h.y]


static func obb_has(o: Dictionary, p: Vector2, margin: float = 0.0) -> bool:
	var d := p - (o["c"] as Vector2)
	var u: Vector2 = o["u"]
	var h: Vector2 = o["h"]
	return absf(d.dot(u)) <= h.x + margin and absf(d.dot(Vector2(-u.y, u.x))) <= h.y + margin


## The corridor of a polyline as OBBs (one per segment), half width `hw`.
static func corridor(pts: PackedVector2Array, hw: float) -> Array:
	var out: Array = []
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var l := a.distance_to(b)
		if l < 0.01:
			continue
		out.append(obb((a + b) * 0.5, (b - a) / l, Vector2(l * 0.5 + hw, hw)))
	return out


static func seg_distance(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p))
	return best


## Arc length of the point of `pts` nearest to `p`.
static func project_s(pts: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var out := 0.0
	var acc := 0.0
	for i in pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
		var d := q.distance_to(p)
		if d < best:
			best = d
			out = acc + pts[i].distance_to(q)
		acc += pts[i].distance_to(pts[i + 1])
	return out


# ------------------------------------------------------------------ the generator
## `avoid`: [[PackedVector2Array points, half width]] of the existing roads the lots must keep off (the access road).
static func generate(seed_v: int, d: Dictionary, avoid: Array) -> Dictionary:
	# a layout short of the minimum building count (a tight bend, a short street) is drawn again from the next
	# stream of the same seed; the first one that reaches it wins (deterministic)
	var nb: Array = d.get("buildings", [15, 20])
	var best: Dictionary = {}
	for attempt in 6:
		var p := _generate(seed_v, d, avoid, attempt)
		p["attempt"] = attempt
		if best.is_empty() or (p["buildings"] as Array).size() > (best["buildings"] as Array).size():
			best = p
		if (p["buildings"] as Array).size() >= int(nb[0]):
			return p
	return best


static func _generate(seed_v: int, d: Dictionary, avoid: Array, attempt: int) -> Dictionary:
	var site := str(d.get("id", "site"))
	var r := Rng.new(seed_v, site.hash() + attempt * 7919)
	var bounds := Rect2(v2([d["bounds"][0], d["bounds"][1]]), v2([d["bounds"][2], d["bounds"][3]]))
	var circ: Array = d.get("circle", [])
	var streets: Array = []
	# ---- 1. main street: from the access road, compass heading + bend
	var m: Dictionary = d["main"]
	var from := v2(m["from"])
	var dr: Array = m["dir"]
	var heading := deg_to_rad(r.rng(float(dr[0]), float(dr[1])))
	var ln: Array = m["length"]
	var L := r.rng(float(ln[0]), float(ln[1]))
	var bend := deg_to_rad(float(m.get("bend", 6.0)))
	var mp := PackedVector2Array([from])
	for k in 3:
		heading += r.rng(-bend, bend) * (0.5 if k == 0 else 1.0)
		mp.append(mp[mp.size() - 1] + compass(heading) * (L / 3.0))
	streets.append({"id": "%s_main" % site, "name": str(m.get("name", "Calle Mayor")), "kind": "road", "width": float(m.get("width", 6.0)),
		"shoulder": float(m.get("shoulder", 3.0)), "points": mp, "pin_start": true, "lots": "both", "main": true})
	# ---- 2. branches (a lane toward a fixed point, or a side street off the main street)
	var used_s: Array[float] = []
	for bspec: Dictionary in d.get("branches", []):
		if bspec.has("chance") and r.f() >= float(bspec["chance"]):
			continue
		var at: Array = bspec.get("at", [0.3, 0.7])
		var bp := PackedVector2Array()
		if bspec.has("to"):
			var to := v2(bspec["to"])
			var s_best := 0.0
			var d_best := INF
			var s := float(at[0]) * L
			while s <= float(at[1]) * L:
				var pa: Vector2 = point_at(mp, s)[0]
				var dd := pa.distance_to(to)
				if dd < d_best:
					d_best = dd
					s_best = s
				s += 2.0
			s_best += r.rng(-4.0, 4.0)
			var a0: Vector2 = point_at(mp, s_best)[0]
			var mid := (a0 + to) * 0.5
			var nrm := (to - a0).normalized().orthogonal()
			bp = PackedVector2Array([a0, mid + nrm * r.rng(-3.0, 3.0), to])
			used_s.append(s_best)
		else:
			var ok := false
			for tries in 6:
				var s := r.rng(float(at[0]), float(at[1])) * L
				var clash := false
				for u in used_s:
					if absf(u - s) < 30.0:
						clash = true
				if clash:
					continue
				var pt: Array = point_at(mp, s)
				var tan: Vector2 = pt[1]
				var want := Vector2(-1, 0) if str(bspec.get("side", "west")) == "west" else Vector2(1, 0)
				var nn := Vector2(tan.y, -tan.x)
				if nn.dot(want) < 0.0:
					nn = -nn
				var hdg := atan2(nn.x, -nn.y) + deg_to_rad(r.rng(-float(bspec.get("dir_jitter", 15.0)), float(bspec.get("dir_jitter", 15.0))))
				var bl: Array = bspec.get("length", [50, 80])
				var blen := r.rng(float(bl[0]), float(bl[1]))
				var a0: Vector2 = pt[0]
				var h2 := hdg + deg_to_rad(r.rng(-6.0, 6.0))
				var p1 := a0 + compass(hdg) * (blen * 0.5)
				var p2 := p1 + compass(h2) * (blen * 0.5)
				if not bounds.grow(-6.0).has_point(p2):
					continue
				bp = PackedVector2Array([a0, p1, p2])
				used_s.append(s)
				ok = true
				break
			if not ok:
				continue
		streets.append({"id": "%s_b%d" % [site, streets.size()], "name": str(bspec.get("name", "")), "kind": "road",
			"width": float(bspec.get("width", 5.0)), "shoulder": float(bspec.get("shoulder", 3.0)), "points": bp, "pin_start": true,
			"lots": str(bspec.get("lots", "both")), "main": false, "to": bspec.has("to")})
	# ---- 3. lots along both sides of every street
	var lp: Dictionary = d.get("lots", {})
	var area: Array = lp.get("area", [400, 900])
	var front: Array = lp.get("front", [17, 26])
	var depth: Array = lp.get("depth", [24, 32])
	var gap: Array = lp.get("gap", [1.0, 4.0])
	var corridors: Array = []            # [street index, obb]
	for si in streets.size():
		var st: Dictionary = streets[si]
		for o in corridor(st["points"], float(st["width"]) * 0.5):
			corridors.append([si, o])
	var avoid_c: Array = []
	for a in avoid:
		for o in corridor(a[0], float(a[1]) + float(d.get("avoid_margin", 10.0))):
			avoid_c.append(o)
	var keep: Array = []
	for kr in d.get("keepout", []):
		var kc := Vector2(float(kr[0]) + float(kr[2]) * 0.5, float(kr[1]) + float(kr[3]) * 0.5)
		keep.append(obb(kc, Vector2.RIGHT, Vector2(float(kr[2]) * 0.5, float(kr[3]) * 0.5)))
	var lots: Array = []
	for si in streets.size():
		var st: Dictionary = streets[si]
		var pts: PackedVector2Array = st["points"]
		var hw := float(st["width"]) * 0.5
		var sl := poly_length(pts)
		for sdv in [1.0, -1.0]:
			var sd := float(sdv)
			var which := str(st.get("lots", "both"))
			if which != "both":
				var t0: Vector2 = point_at(pts, sl * 0.5)[1]
				var nn := Vector2(t0.y, -t0.x) * sd
				var want := {"north": Vector2(0, -1), "south": Vector2(0, 1), "east": Vector2(1, 0), "west": Vector2(-1, 0)}.get(which, Vector2.ZERO) as Vector2
				if nn.dot(want) <= 0.0:
					continue
			var s := float(lp.get("start_gap", 9.0)) + (0.0 if bool(st.get("main", false)) else 6.0)
			var s_end := sl - float(lp.get("end_gap", 4.0))
			while s < s_end - float(front[0]):
				var w := r.rng(float(front[0]), float(front[1]))
				if s + w > s_end:
					w = s_end - s
				var mid := s + w * 0.5
				var pt: Array = point_at(pts, mid)
				var tan: Vector2 = pt[1]
				var n := Vector2(tan.y, -tan.x) * sd
				var dep := clampf(r.rng(float(depth[0]), float(depth[1])), float(area[0]) / w, float(area[1]) / w)
				var o := obb((pt[0] as Vector2) + n * (hw + 0.5 + dep * 0.5), tan, Vector2(w * 0.5, dep * 0.5))
				if w >= float(front[0]) - 0.01 and _lot_ok(o, si, corridors, streets, avoid_c, keep, lots, bounds, circ):
					lots.append({"street": si, "side": sd, "s": mid, "w": w, "dep": dep, "obb": o, "p": pt[0], "t": tan, "n": n, "hw": hw})
					s += w + r.rng(float(gap[0]), float(gap[1]))
				else:
					s += 3.0
	# ---- 4. land use: reserved first (most central lots that fit), then houses up to the target, the rest empty
	var core: Vector2 = point_at(mp, L * 0.45)[0]
	var order: Array = []
	for i in lots.size():
		var lot: Dictionary = lots[i]
		var cd := (lot["p"] as Vector2).distance_to(core) + (0.0 if int(lot["street"]) == 0 else 25.0)
		order.append([cd, i])
	order.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]) or (float(x[0]) == float(y[0]) and int(x[1]) < int(y[1])))
	var nb: Array = d.get("buildings", [15, 20])
	var n_target := r.ri(int(nb[0]), int(nb[1]))
	var taken := {}
	var buildings: Array = []
	for res: Dictionary in d.get("reserved", []):
		var tid := str(res["template"])
		if footprint(tid) == Vector3.ZERO:
			continue
		for pass_i in 2:
			var placed := false
			for oi in order:
				var li := int(oi[1])
				if taken.has(li):
					continue
				var lot: Dictionary = lots[li]
				if pass_i == 0 and int(lot["street"]) != 0:
					continue
				if not _fits(lot, tid, lp):
					continue
				taken[li] = true
				buildings.append(_place(lot, li, tid, str(res.get("style", "")), str(res["use"]), res, true, r, lp, seed_v))
				placed = true
				break
			if placed:
				break
	var hw_list: Array = d.get("houses", [])
	var empty_p := float(d.get("empty", 0.05))
	for oi in order:
		var li := int(oi[1])
		if taken.has(li) or buildings.size() >= n_target:
			continue
		var lot: Dictionary = lots[li]
		if r.f() < empty_p:
			continue
		var choices: Array = []
		var weights: Array = []
		for hs: Dictionary in hw_list:
			var tid := str(hs["template"])
			if footprint(tid) != Vector3.ZERO and _fits(lot, tid, lp):
				choices.append(tid)
				weights.append(float(hs.get("w", 1.0)))
		if choices.is_empty():
			continue
		var tid2 := str(choices[r.pick_w(weights)])
		taken[li] = true
		var enter := r.f() < float(d.get("enterable_house", 0.45))
		buildings.append(_place(lot, li, tid2, "", "house", {}, enter, r, lp, seed_v))
	# at least `enterable_min` enterable: open the most central locked houses
	var n_enter := 0
	for b in buildings:
		if bool(b["enterable"]):
			n_enter += 1
	for b in buildings:
		if n_enter >= int(d.get("enterable_min", 6)):
			break
		if not bool(b["enterable"]):
			b["enterable"] = true
			n_enter += 1
	# house numbers: per street, odd on one side, even on the other, in order along the street
	for si in streets.size():
		for sdv in [1.0, -1.0]:
			var sd := float(sdv)
			var mine: Array = []
			for b in buildings:
				if int(b["street"]) == si and float(b["side"]) == sd:
					mine.append(b)
			mine.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["s"]) < float(y["s"]))
			for k in mine.size():
				(mine[k] as Dictionary)["number"] = (2 * k + 1) if sd > 0.0 else (2 * k + 2)
	# residents by use (zombies inside; locked houses fewer)
	var rz: Dictionary = d.get("residents", {})
	for b in buildings:
		var key := str(b["use"])
		if key == "house" and not bool(b["enterable"]):
			key = "house_locked"
		var rr: Array = rz.get(key, [1, 2])
		b["residents"] = r.ri(int(rr[0]), int(rr[1]))
	# ---- 5. street dressing
	var items: Array = []
	_dress(d, r, streets, lots, buildings, items, avoid)
	var pads: Array = []
	for b in buildings:
		pads.append(b["pad"])
	return {"id": site, "name": str(d.get("name", site)), "kind": str(d.get("kind", "village")), "streets": streets, "lots": lots,
		"buildings": buildings, "items": items, "pads": pads, "bounds": bounds, "outdoor": rz.get("street", [1, 2]),
		"zone": str(d.get("zone", site)), "core": core}


static func _lot_ok(o: Dictionary, si: int, corridors: Array, streets: Array, avoid_c: Array, keep: Array, lots: Array, bounds: Rect2, circ: Array) -> bool:
	for c in obb_corners(o):
		if not bounds.has_point(c):
			return false
		if circ.size() >= 3 and c.distance_to(Vector2(float(circ[0]), float(circ[1]))) > float(circ[2]) - 4.0:
			return false
	for cc in corridors:
		# own street: the lot starts 0.5 m past the bed (its bends are tested too); other streets keep 2.5 m
		if obb_overlap(o, cc[1], 0.0 if int(cc[0]) == si else 2.5):
			return false
	for a in avoid_c:
		if obb_overlap(o, a):
			return false
	for k in keep:
		if obb_overlap(o, k):
			return false
	for l in lots:
		if obb_overlap(o, l["obb"], 0.4):
			return false
	return true


## True when template `tid` (+ porch, side yards, setback, back yard) fits the lot.
static func _fits(lot: Dictionary, tid: String, lp: Dictionary) -> bool:
	var fp := footprint(tid)
	var sy := float(lp.get("side_yard", 3.6))
	var sb: Array = lp.get("setback", [0.8, 2.4])
	var need_d := float(lp.get("sidewalk", 1.6)) + float(sb[0]) + fp.z + fp.y + float(lp.get("backyard", 3.0))
	return float(lot["w"]) >= fp.x + 2.0 * sy and float(lot["dep"]) >= need_d


## The building record of a lot: position (front toward the street), style, pad, loot table remap.
static func _place(lot: Dictionary, li: int, tid: String, style: String, use: String, spec: Dictionary, enter: bool, r: Rng, lp: Dictionary, _seed_v: int) -> Dictionary:
	var fp := footprint(tid)
	var hw := float(lot["hw"])
	var sb: Array = lp.get("setback", [0.8, 2.4])
	var sy := float(lp.get("side_yard", 3.6))
	var max_sb := float(lot["dep"]) - float(lp.get("sidewalk", 1.6)) - fp.z - fp.y - float(lp.get("backyard", 3.0))
	var setback := minf(r.rng(float(sb[0]), float(sb[1])), maxf(max_sb, float(sb[0])))
	var front := hw + 0.5 + float(lp.get("sidewalk", 1.6)) + setback
	var dist_c := front + fp.z + fp.y * 0.5
	var slack := maxf(0.0, (float(lot["w"]) - fp.x - 2.0 * sy) * 0.5)
	var lateral := r.rng(-1.0, 1.0) * slack
	var p: Vector2 = lot["p"]
	var t: Vector2 = lot["t"]
	var n: Vector2 = lot["n"]
	var pos := p + n * dist_c + t * lateral
	var yaw := rad_to_deg(yaw_to(-n))
	if style == "":
		var sts := styles_of(tid)
		style = str(sts[r.ri(0, sts.size() - 1)])
	var back := dist_c + fp.y * 0.5 + PAD_MARGIN
	var near := hw + 0.2
	var pad_c := p + t * lateral + n * ((near + back) * 0.5)
	var pad := {"c": pad_c, "half": Vector2(fp.x * 0.5 + PAD_MARGIN, (back - near) * 0.5), "rot": atan2(t.y, t.x), "blend": PAD_BLEND, "h_at": p}
	return {"template": tid, "style": style, "pos": pos, "yaw": yaw, "use": use, "number": 0, "shop": str(spec.get("shop", "")),
		"enterable": enter, "alarm": bool(spec.get("alarm", false)), "tables": spec.get("tables", {}), "residents": 0,
		"size": Vector2(fp.x, fp.y), "porch": fp.z, "street": int(lot["street"]), "side": float(lot["side"]), "s": float(lot["s"]),
		"lot": li, "lateral": lateral, "front": front, "pad": pad, "p": p, "t": t, "n": n,
		"obb": obb(pos - n * (fp.z * 0.5), t, Vector2(fp.x * 0.5, fp.y * 0.5 + fp.z * 0.5))}


# ------------------------------------------------------------------ street dressing
static func _item(items: Array, kind: String, model: String, pos: Vector2, yaw_rad: float, extra: Dictionary = {}) -> void:
	var e := {"k": kind, "model": model, "pos": pos, "yaw": rad_to_deg(yaw_rad)}
	e.merge(extra, true)
	items.append(e)


## Free spot for a small prop: not inside a building (+ its porch / front path), not on a street bed.
static func _free(p: Vector2, buildings: Array, streets: Array, items: Array, clear: float = 1.0) -> bool:
	for b in buildings:
		if obb_has(b["obb"], p, clear + 0.6):
			return false
		# the path from the sidewalk to the front door
		var fp: Vector2 = b["p"] + (b["t"] as Vector2) * float(b["lateral"])
		var door := (b["pos"] as Vector2) - (b["n"] as Vector2) * (float((b["size"] as Vector2).y) * 0.5)
		if Geometry2D.get_closest_point_to_segment(p, fp, door).distance_to(p) < 1.3 + clear * 0.5:
			return false
	for st in streets:
		if seg_distance(p, st["points"]) < float(st["width"]) * 0.5 + 0.3:
			return false
	for it in items:
		if (it["pos"] as Vector2).distance_to(p) < clear:
			return false
	return true


static func _dress(d: Dictionary, r: Rng, streets: Array, lots: Array, buildings: Array, items: Array, avoid: Array) -> void:
	var pr: Dictionary = d.get("props", {})
	var sg: Dictionary = d.get("signs", {})
	var pw: Dictionary = sg.get("lamp_power", {"on": 0.7, "flicker": 0.15})
	# lamps along every street, alternating sides; power poles along the main street (+ the wires between them)
	for si in streets.size():
		var st: Dictionary = streets[si]
		var pts: PackedVector2Array = st["points"]
		var hw := float(st["width"]) * 0.5
		var sl := poly_length(pts)
		var sp: Array = pr.get("lamp_spacing", [26, 32])
		var s := 8.0 + r.rng(0.0, 6.0)
		var side := 1.0 if r.f() < 0.5 else -1.0
		while s < sl - 3.0:
			var pt: Array = point_at(pts, s)
			var t: Vector2 = pt[1]
			var n := Vector2(t.y, -t.x) * side
			var pos: Vector2 = (pt[0] as Vector2) + n * (hw + 1.0)
			if _free(pos, buildings, streets, items, 1.2):
				var u := r.f()
				var power := 1.0 if u < float(pw.get("on", 0.7)) else (-1.0 if u < float(pw.get("on", 0.7)) + float(pw.get("flicker", 0.15)) else 0.0)
				_item(items, "lamp", str(pr.get("lamp", "props/village/lamp_post")), pos, yaw_to(-n), {"power": power})
				side = -side
			s += r.rng(float(sp[0]), float(sp[1]))
		if bool(st.get("main", false)) and pr.has("pole"):
			var ps: Array = pr.get("pole_spacing", [30, 36])
			var s2 := 5.0
			var prev := -1
			while s2 < sl + 20.0:
				var pt2: Array = point_at(pts, minf(s2, sl - 1.0))
				var t2: Vector2 = pt2[1]
				var n2 := Vector2(t2.y, -t2.x) * -1.0
				var pos2: Vector2 = (pt2[0] as Vector2) + n2 * (hw + 2.4)
				if _free(pos2, buildings, streets, items, 1.0):
					_item(items, "pole", str(pr["pole"]), pos2, yaw_to(-n2) + r.rng(-0.05, 0.05))
					if prev >= 0:
						(items[prev] as Dictionary)["wire_to"] = items.size() - 1
					prev = items.size() - 1
				if s2 >= sl - 1.0:
					break
				s2 += r.rng(float(ps[0]), float(ps[1]))
	# per building: mailbox, front fence (houses), shop / bar / garage dressing
	var fences: Array = pr.get("fences", [])
	for b in buildings:
		var p: Vector2 = b["p"]
		var t: Vector2 = b["t"]
		var n: Vector2 = b["n"]
		var hw2 := float((streets[int(b["street"])] as Dictionary)["width"]) * 0.5
		var lat := float(b["lateral"])
		var W := float((b["size"] as Vector2).x)
		var lot: Dictionary = lots[int(b["lot"])]
		var use := str(b["use"])
		if use == "house":
			var mb := p + t * (lat + W * 0.5 + 0.2) + n * (hw2 + 1.3)
			if pr.has("mailbox") and _free(mb, buildings, streets, items, 0.8):
				_item(items, "prop", str(pr["mailbox"]), mb, yaw_to(-n))
			if not fences.is_empty() and r.f() < float(pr.get("fence_chance", 0.5)):
				var fm := str(fences[r.ri(0, fences.size() - 1)])
				var half := float(lot["w"]) * 0.5 - 0.8
				var u0 := -half
				while u0 + 2.0 <= half:
					var uc := u0 + 1.0
					if absf(uc - lat) > 1.6:
						var fpos := p + t * uc + n * (hw2 + 2.0)
						if _free(fpos, buildings, streets, [], 0.3):
							_item(items, "fence", fm, fpos, along(t))
					u0 += 2.0
		elif use in ["shop", "bar"]:
			var sides := [1.0, -1.0]
			var bench_pos := p + t * (lat + (W * 0.5 + 1.4) * float(sides[r.ri(0, 1)])) + n * (hw2 + 1.6)
			if pr.has("bench") and _free(bench_pos, buildings, streets, items, 0.8):
				_item(items, "prop", str(pr["bench"]), bench_pos, yaw_to(-n))
			var bin_pos := p + t * (lat - (W * 0.5 + 0.6)) + n * (hw2 + 1.4)
			if pr.has("trash_can") and _free(bin_pos, buildings, streets, items, 0.6):
				_item(items, "prop", str(pr["trash_can"]), bin_pos, yaw_to(-n))
			var dpos := (b["pos"] as Vector2) + t * (W * 0.5 + 2.2) + n * 1.0
			if pr.has("dumpster") and _free(dpos, buildings, streets, items, 1.0):
				_item(items, "container", str(pr["dumpster"]), dpos, yaw_to(-t), {"table": "dumpster"})
			if use == "shop" and pr.has("cart"):
				var cpos := p + t * (lat + W * 0.5 + 0.4) + n * (hw2 + 2.8)
				if _free(cpos, buildings, streets, items, 0.8):
					_item(items, "prop", str(pr["cart"]), cpos, yaw_to(-n) + r.rng(-0.6, 0.6))
			var back := (b["pos"] as Vector2) + n * (float((b["size"] as Vector2).y) * 0.5 + 1.4)
			for k in 3:
				var cp := back + t * (-2.0 + 2.0 * float(k)) + n * r.rng(-0.2, 0.3)
				var model := str(pr.get("crate", "")) if k != 1 else str(pr.get("pallet", ""))
				if model != "" and _free(cp, buildings, streets, items, 0.7):
					_item(items, "prop", model, cp, r.rng(0.0, TAU))
		elif use == "garage":
			for k in 2:
				var tp := (b["pos"] as Vector2) + t * ((W * 0.5 + 1.2) * (1.0 if k == 0 else -1.0)) - n * (float((b["size"] as Vector2).y) * 0.5 - 1.0)
				if pr.has("tires") and _free(tp, buildings, streets, items, 0.8):
					_item(items, "prop", str(pr["tires"]), tp, r.rng(0.0, TAU))
			for k in 3:
				var bp2 := (b["pos"] as Vector2) + t * (W * 0.5 + 1.0) + n * (-1.0 + 1.0 * float(k))
				if pr.has("barrel") and _free(bp2, buildings, streets, items, 0.6):
					_item(items, "prop", str(pr["barrel"]), bp2, r.rng(0.0, TAU))
			# a wreck on the forecourt, nose to the door
			var cm: Array = (d.get("cars", {}) as Dictionary).get("models", ["pickup"])
			var carp := p + t * lat + n * (hw2 + 2.6)
			if _free(carp, buildings, [], items, 2.0):
				_item(items, "car", "city/vehicles/%s_%s" % ["pickup" if cm.has("pickup") else str(cm[0]), "doors"], carp, yaw_to(n) + r.rng(-0.15, 0.15),
					{"table": str((d.get("cars", {}) as Dictionary).get("table", "car"))})
	# the main street's start: village sign (S-500, crossed out behind), stop sign, a bus stop on the access road
	var main: Dictionary = streets[0]
	var mpts: PackedVector2Array = main["points"]
	var mhw := float(main["width"]) * 0.5
	var p0: Array = point_at(mpts, 14.0)
	var t0: Vector2 = p0[1]
	var n0 := Vector2(t0.y, -t0.x)
	if sg.has("entry"):
		_item(items, "sign", "signs/sign_road", (p0[0] as Vector2) + n0 * (mhw + 2.4), yaw_to(-t0), {"text": str(sg["entry"]), "back": "strike"})
	var ps0: Array = point_at(mpts, 5.0)
	var ts: Vector2 = ps0[1]
	if pr.has("stop"):
		_item(items, "prop", str(pr["stop"]), (ps0[0] as Vector2) - Vector2(ts.y, -ts.x) * (mhw + 1.2), yaw_to(ts))
	_item(items, "sign", "signs/sign_street", (point_at(mpts, 10.0)[0] as Vector2) - n0 * (mhw + 2.0), deg_to_rad(45.0),
		{"text": str(main["name"]), "back": str(main["name"])})
	if pr.has("bus_stop") and not avoid.is_empty():
		var ap: PackedVector2Array = avoid[0][0]
		var ahw := float(avoid[0][1])
		var sj := project_s(ap, mpts[0])
		var q: Array = point_at(ap, sj + 16.0)
		var qt: Vector2 = q[1]
		var qn := Vector2(qt.y, -qt.x)
		if qn.dot(mpts[1] - mpts[0]) < 0.0:
			qn = -qn
		_item(items, "prop", str(pr["bus_stop"]), (q[0] as Vector2) + qn * (ahw + 3.2), yaw_to(-qn))
	# street name plates at the branch junctions (both faces), barricades across the far ends
	var barr: Array = pr.get("barricades", [])
	for si in range(1, streets.size()):
		var st: Dictionary = streets[si]
		var pts: PackedVector2Array = st["points"]
		var hw := float(st["width"]) * 0.5
		var q0: Array = point_at(pts, mhw + 3.0)
		var bt: Vector2 = q0[1]
		var bn := Vector2(bt.y, -bt.x)
		var spos: Vector2 = (q0[0] as Vector2) + bn * (hw + 1.6)
		if _free(spos, buildings, streets, items, 1.0):
			_item(items, "sign", "signs/sign_street", spos, deg_to_rad(45.0), {"text": str(st["name"]), "back": str(st["name"])})
		if not bool(st.get("to", false)) and not barr.is_empty():
			var sl := poly_length(pts)
			var e: Array = point_at(pts, sl - 1.5)
			var et: Vector2 = e[1]
			var en := Vector2(et.y, -et.x)
			for k in 3:
				var bpos: Vector2 = (e[0] as Vector2) + en * (-hw + 0.9 + (2.0 * hw - 1.8) * float(k) / 2.0)
				_item(items, "prop", str(barr[r.ri(0, barr.size() - 1)]), bpos, along(en) + r.rng(-0.25, 0.25))
	# the main street's far end: sandbags + a jersey barrier (someone held the north road)
	if not barr.is_empty():
		var sl0 := poly_length(mpts)
		var e0: Array = point_at(mpts, sl0 - 2.0)
		var et0: Vector2 = e0[1]
		var en0 := Vector2(et0.y, -et0.x)
		for k in 3:
			var model := str(barr[1 + (k % (barr.size() - 1))]) if barr.size() > 1 else str(barr[0])
			_item(items, "prop", model, (e0[0] as Vector2) + en0 * (-2.0 + 2.0 * float(k)), along(en0) + r.rng(-0.2, 0.2))
	# hydrants along the main street
	for k in int(pr.get("hydrants", 0)):
		var hs := poly_length(mpts) * (0.3 + 0.4 * float(k)) + r.rng(-6.0, 6.0)
		var hp: Array = point_at(mpts, hs)
		var ht: Vector2 = hp[1]
		var hn := Vector2(ht.y, -ht.x)
		var hpos: Vector2 = (hp[0] as Vector2) + hn * (mhw + 0.9)
		if pr.has("hydrant") and _free(hpos, buildings, streets, items, 1.0):
			_item(items, "prop", str(pr["hydrant"]), hpos, yaw_to(-hn))
	# abandoned cars at the curb (A1 wrecks + a loot container at their Loot anchor)
	var cars: Dictionary = d.get("cars", {})
	if not cars.is_empty():
		var cc: Array = cars.get("count", [3, 5])
		var want := r.ri(int(cc[0]), int(cc[1]))
		var models: Array = cars.get("models", ["sedan"])
		var variants: Array = cars.get("variants", ["snowed"])
		var tries := 0
		var made := 0
		while made < want and tries < want * 12:
			tries += 1
			var si := r.ri(0, streets.size() - 1)
			var st: Dictionary = streets[si]
			var pts: PackedVector2Array = st["points"]
			var sl := poly_length(pts)
			var s := r.rng(10.0, sl - 6.0)
			var pt: Array = point_at(pts, s)
			var t: Vector2 = pt[1]
			var sd := 1.0 if r.f() < 0.5 else -1.0
			var n := Vector2(t.y, -t.x) * sd
			var pos: Vector2 = (pt[0] as Vector2) + n * (float(st["width"]) * 0.5 - 1.0)
			var ok := true
			for it in items:
				var dd := (it["pos"] as Vector2).distance_to(pos)
				if (str(it["k"]) == "car" and dd < 9.0) or dd < 2.4:
					ok = false
			for st2 in streets:
				if st2 != st and seg_distance(pos, st2["points"]) < float(st2["width"]) * 0.5 + 5.0:
					ok = false
			if not ok:
				continue
			var fwd := t if r.f() < 0.5 else -t
			var model := "city/vehicles/%s_%s" % [str(models[r.ri(0, models.size() - 1)]), str(variants[r.ri(0, variants.size() - 1)])]
			_item(items, "car", model, pos, yaw_to(fwd) + r.rng(-0.12, 0.12), {"table": str(cars.get("table", "car"))})
			made += 1
