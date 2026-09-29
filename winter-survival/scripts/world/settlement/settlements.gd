class_name Settlements
extends RefCounted
## The M6b places of the valley (PLAN §7 M6b, ARQ v2 §9.1 / §9.5 / «§9.11»): the procedural village La Herrería
## (SettlementGen, res://data/buildings/settlements/<id>.json) and the hand-made POIs (res://data/buildings/pois/
## <id>.json: aserradero, gasolinera_norte, granja_molino), as one plan per site and world seed. Pure and
## deterministic (the same bytes on the server and every client): HeightFunction._setup calls stamp() (main thread)
## — the village streets become road beds (HeightFunction.add_road: asphalt mask, smoothed profile pinned to the road
## they join, the scatter keeps off them) and every building lot / POI yard an oriented level pad (add_pad) — so the
## terrain, the chunk hashes and the scatter follow; afterwards everything here is read-only (safe from the chunk
## workers). SettlementSpawner builds the per-chunk items (buildings, props, lamps, cars…) under the streamed chunks;
## PopulationTable / PopulationManager read the residents by land use (resident_target / spawn_residents).
##
## Plan (per site): id, name, kind (village | poi), streets [road records], buildings [{template, style, pos (world
## x, z), yaw (deg), use, number, shop, enterable, alarm, tables, residents, size, porch, wid, key, site}], items
## [{k: prop | lamp | pole | fence | sign | car | container, model, pos, yaw, wid, key, …}], pads, bounds (Rect2),
## outdoor [min, max] street residents per chunk, zone (LocationInfo data of a POI).

const SETTLEMENTS_DIR := "res://data/buildings/settlements/"
const POIS_DIR := "res://data/buildings/pois/"
const MACRO_ROADS := "res://data/world/macro_roads.json"
const GEN_ITEM := 0x53495445          # "SITE"
const GEN_RES := 0x52455344           # "RESD"
const GEN_BUILDING := 0x424C4447      # "BLDG" = KitBuilding.GEN_BUILDING (no dependency on the node classes: the
                                      # HeightFunction loads this script in tools / workers without the autoloads)
## Share of the outdoor residents standing frozen (the minefield, like PopulationManager.FROZEN_SHARE).
const FROZEN_SHARE := 0.4
## At most this many residents per chunk (the 96² table's cap, PopulationTable.UNBUILT_CAP; GDD aldea 3–8, a sawmill
## chunk may hold more): the indoor sleepers are kept first.
const MAX_PER_CHUNK := 12

## Tests: false = no stamps / no items (a world without the M6b places).
static var enabled: bool = true
static var _defs: Array = []          # [{"def": Dictionary, "proc": bool}]
static var _defs_loaded: bool = false
static var _plans: Dictionary = {}    # seed -> Array[Dictionary]
static var _chunks: Dictionary = {}   # seed -> {chunk key -> Array[Dictionary] (buildings + items)}
static var _res: Dictionary = {}      # seed -> {chunk key -> {"target": int, "spots": Array}}
static var _macro_roads: Dictionary = {}
static var _lock := Mutex.new()


# ------------------------------------------------------------------ data
static func defs() -> Array:
	if not _defs_loaded:
		_defs_loaded = true
		for pair in [[SETTLEMENTS_DIR, true], [POIS_DIR, false]]:
			for f in _json_files(str(pair[0])):
				var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(pair[0]) + f))
				if v is Dictionary:
					_defs.append({"def": v, "proc": bool(pair[1])})
	return _defs


static func _json_files(dir_path: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			files.append(f)
		f = dir.get_next()
	files.sort()
	return files


## [[PackedVector2Array, half width]] of the macro roads named in `ids` (data/world/macro_roads.json).
static func _avoid(ids: Array) -> Array:
	if _macro_roads.is_empty():
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(MACRO_ROADS))
		if v is Dictionary:
			for r in (v as Dictionary).get("roads", []):
				var pts := PackedVector2Array()
				for q in r["points"]:
					pts.append(Vector2(float(q[0]), float(q[1])))
				_macro_roads[str(r["id"])] = [pts, float(r["width"]) * 0.5]
	var out: Array = []
	for id in ids:
		if _macro_roads.has(str(id)):
			out.append(_macro_roads[str(id)])
	return out


## Test hook: forget the plans (and reload the data files).
static func reset() -> void:
	_lock.lock()
	_plans.clear()
	_chunks.clear()
	_res.clear()
	_defs.clear()
	_defs_loaded = false
	SettlementGen._tpl_cache.clear()
	_lock.unlock()


# ------------------------------------------------------------------ plans
## Every site's plan for a world seed (built once, cached; the first call must be on the main thread —
## HeightFunction.create does it).
static func plans(seed_v: int) -> Array:
	if not enabled:
		return []
	_lock.lock()
	if not _plans.has(seed_v):
		var out: Array = []
		for e in defs():
			var d: Dictionary = e["def"]
			var p: Dictionary = SettlementGen.generate(seed_v, d, _avoid(d.get("avoid_roads", []))) if bool(e["proc"]) else _poi_plan(d)
			_finish(seed_v, p)
			out.append(p)
		_plans[seed_v] = out
		_index(seed_v, out)
	var res: Array = _plans[seed_v]
	_lock.unlock()
	return res


static func site(seed_v: int, id: String) -> Dictionary:
	for p in plans(seed_v):
		if str(p["id"]) == id:
			return p
	return {}


## A hand-made POI's data in its local frame → the plan format (world x, z).
static func _poi_plan(d: Dictionary) -> Dictionary:
	var c := SettlementGen.v2(d["center"])
	var psi := deg_to_rad(float(d.get("yaw", 0.0)))
	var to_w := func(a: Variant) -> Vector2:
		var l := SettlementGen.v2(a)
		return c + Vector2(l.x * cos(psi) + l.y * sin(psi), -l.x * sin(psi) + l.y * cos(psi))
	var buildings: Array = []
	for b: Dictionary in d.get("buildings", []):
		var fp := SettlementGen.footprint(str(b["template"]))
		var yaw := float(b.get("yaw", 0.0)) + rad_to_deg(psi)
		var pos: Vector2 = to_w.call(b["pos"])
		var fwd := Vector2(sin(deg_to_rad(yaw)), cos(deg_to_rad(yaw)))
		var right := Vector2(fwd.y, -fwd.x)
		buildings.append({"template": str(b["template"]), "style": str(b.get("style", SettlementGen.styles_of(str(b["template"]))[0])),
			"pos": pos, "yaw": yaw, "use": str(b.get("use", "poi")), "number": int(b.get("number", 0)), "shop": str(b.get("shop", "")),
			"enterable": bool(b.get("enterable", true)), "alarm": bool(b.get("alarm", false)), "tables": b.get("tables", {}),
			"residents": int(b.get("residents", 1)), "size": Vector2(fp.x, fp.y), "porch": fp.z, "street": -1,
			"obb": SettlementGen.obb(pos + fwd * (fp.z * 0.5), right, Vector2(fp.x * 0.5, fp.y * 0.5 + fp.z * 0.5)), "fwd": fwd})
	var items: Array = []
	for it: Dictionary in d.get("items", []):
		if it.has("run"):
			var run: Array = it["run"]
			var a: Vector2 = to_w.call(run[0])
			var bq: Vector2 = to_w.call(run[1])
			var l := a.distance_to(bq)
			var dir := (bq - a) / maxf(l, 0.001)
			var n := int(floor(l / 2.0))
			for k in n:
				var e := {"k": str(it["k"]), "model": str(it["model"]), "pos": a + dir * (1.0 + 2.0 * float(k)), "yaw": rad_to_deg(SettlementGen.along(dir))}
				items.append(e)
			continue
		var e2 := it.duplicate()
		e2["pos"] = to_w.call(it["pos"])
		e2["yaw"] = float(it.get("yaw", 0.0)) + rad_to_deg(psi)
		items.append(e2)
	var pads: Array = []
	for pd: Dictionary in d.get("pads", []):
		pads.append({"c": to_w.call(pd["c"]), "half": SettlementGen.v2(pd["half"]), "rot": deg_to_rad(float(pd.get("rot", 0.0))) - psi,
			"blend": float(pd.get("blend", 8.0)), "h_at": SettlementGen.v2(pd["h_at"])})
	var bnd: Array = d.get("bounds", [c.x - 50.0, c.y - 50.0, 100.0, 100.0])
	return {"id": str(d["id"]), "name": str(d.get("name", d["id"])), "kind": "poi", "streets": [], "lots": [], "buildings": buildings,
		"items": items, "pads": pads, "bounds": Rect2(float(bnd[0]), float(bnd[1]), float(bnd[2]), float(bnd[3])),
		"outdoor": d.get("outdoor", [1, 2]), "zone": d.get("zone", {}), "center": c}


## wids, chunk keys and the model paths of every building / item of a plan.
static func _finish(seed_v: int, p: Dictionary) -> void:
	var sid := str(p["id"])
	var bl: Array = p["buildings"]
	for i in bl.size():
		var b: Dictionary = bl[i]
		b["wid"] = WorldConst.hash64(seed_v, GEN_BUILDING, sid.hash(), i + 1)   # = KitBuilding.wid_for(seed, site, i)
		b["site"] = sid
		b["index"] = i
		var pos: Vector2 = b["pos"]
		b["key"] = WorldConst.key(WorldConst.chunk_of(pos.x), WorldConst.chunk_of(pos.y))
		b["k"] = "building"
	var it: Array = p["items"]
	for i in it.size():
		var e: Dictionary = it[i]
		e["wid"] = WorldConst.hash64(seed_v, GEN_ITEM, sid.hash(), i + 1)
		e["site"] = sid
		e["index"] = i
		var pos2: Vector2 = e["pos"]
		e["key"] = WorldConst.key(WorldConst.chunk_of(pos2.x), WorldConst.chunk_of(pos2.y))


## Per chunk: the buildings + items, and the residents (target, spots).
static func _index(seed_v: int, pl: Array) -> void:
	var by: Dictionary = {}
	var res: Dictionary = {}
	for p: Dictionary in pl:
		for b: Dictionary in p["buildings"]:
			var k := int(b["key"])
			if not by.has(k):
				by[k] = []
			(by[k] as Array).append(b)
		for e: Dictionary in p["items"]:
			var k2 := int(e["key"])
			if not by.has(k2):
				by[k2] = []
			(by[k2] as Array).append(e)
		# residents: every chunk a site touches (its buildings, its streets, its POI yard)
		var keys := {}
		for b: Dictionary in p["buildings"]:
			keys[int(b["key"])] = true
		for st: Dictionary in p["streets"]:
			var pts: PackedVector2Array = st["points"]
			var sl := SettlementGen.poly_length(pts)
			var s := 0.0
			while s <= sl:
				var q: Vector2 = SettlementGen.point_at(pts, s)[0]
				keys[WorldConst.key(WorldConst.chunk_of(q.x), WorldConst.chunk_of(q.y))] = true
				s += 8.0
		if str(p["kind"]) == "poi":
			for pd: Dictionary in p["pads"]:
				var pc: Vector2 = pd["c"]
				keys[WorldConst.key(WorldConst.chunk_of(pc.x), WorldConst.chunk_of(pc.y))] = true
		var klist := keys.keys()
		klist.sort()
		var outdoor: Array = p.get("outdoor", [1, 2])
		for k in klist:
			if not res.has(k):
				res[k] = {"target": 0, "spots": [], "outdoor": 0, "sites": []}
			var r: Dictionary = res[k]
			(r["sites"] as Array).append(str(p["id"]))
			var cx := WorldConst.key_cx(int(k))
			var cz := WorldConst.key_cz(int(k))
			var u := WorldConst.rand01(seed_v, GEN_RES, cx, cz, str(p["id"]).hash() & 0xFFFF)
			r["outdoor"] = int(r["outdoor"]) + int(outdoor[0]) + int(u * float(int(outdoor[1]) - int(outdoor[0]) + 1))
		for b: Dictionary in p["buildings"]:
			var r2: Dictionary = res[int(b["key"])]
			for sp in _indoor_spots(seed_v, b):
				(r2["spots"] as Array).append(sp)
	# the outdoor spots after the indoor ones (sleepers first): along the streets / in the yards of the chunk
	for k in res:
		var r3: Dictionary = res[k]
		var n_out := int(r3["outdoor"])
		var spots: Array = r3["spots"]
		spots.append_array(_outdoor_spots(seed_v, int(k), n_out, pl))
		if spots.size() > MAX_PER_CHUNK:
			spots.resize(MAX_PER_CHUNK)
		r3["target"] = spots.size()
	_chunks[seed_v] = by
	_res[seed_v] = res


## Zombie spots inside a building (floor 0): the template's Spawn_Zombie points first, then hashed interior points.
static func _indoor_spots(seed_v: int, b: Dictionary) -> Array:
	var out: Array = []
	var n := int(b.get("residents", 0))
	if n <= 0:
		return out
	var tpl := SettlementGen.template(str(b["template"]))
	var size: Vector2 = b["size"]
	var pos: Vector2 = b["pos"]
	var yaw := deg_to_rad(float(b["yaw"]))
	var local: Array = []
	for sp: Dictionary in tpl.get("spawns", []):
		if str(sp["kind"]) == "Zombie" and int(sp.get("floor", 0)) == 0:
			var q: Array = sp["pos"]
			# template metres from the SW corner (Blender x, y; front = −Y) → model local (x, z) with the front at +Z
			local.append(Vector2(float(q[0]) - size.x * 0.5, size.y * 0.5 - float(q[1])))
	var wid := int(b["wid"])
	var k := 0
	while local.size() < n:
		k += 1
		var ux := WorldConst.unit(WorldConst.hash64(wid, GEN_RES, k, 1))
		var uz := WorldConst.unit(WorldConst.hash64(wid, GEN_RES, k, 2))
		local.append(Vector2((ux - 0.5) * (size.x - 2.4), (uz - 0.5) * (size.y - 2.4)))
	for i in n:
		var l: Vector2 = local[i]
		var w := pos + Vector2(l.x * cos(yaw) + l.y * sin(yaw), -l.x * sin(yaw) + l.y * cos(yaw))
		out.append({"pos": w, "yaw": WorldConst.unit(WorldConst.hash64(wid, GEN_RES, i, 3)) * TAU, "in": true, "wid": wid, "floor": 0})
	return out


## Outdoor spots of a chunk: on / beside the site streets, or in a POI yard, never inside a building.
static func _outdoor_spots(seed_v: int, key: int, n: int, pl: Array) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	var rect := WorldConst.chunk_rect(WorldConst.key_cx(key), WorldConst.key_cz(key)).grow(-2.0)
	var cands: Array = []           # [a, b] segments of site streets inside the chunk, or yard pad obbs
	for p: Dictionary in pl:
		for st: Dictionary in p["streets"]:
			var pts: PackedVector2Array = st["points"]
			for i in pts.size() - 1:
				cands.append(["seg", pts[i], pts[i + 1], float(st["width"]) * 0.5])
		if str(p["kind"]) == "poi":
			for pd: Dictionary in p["pads"]:
				cands.append(["pad", pd])
	var attempt := 0
	while out.size() < n and attempt < n * 40:
		attempt += 1
		var h := WorldConst.hash64(seed_v, GEN_RES, key, attempt, 7)
		var c: Array = cands[int(h % maxi(cands.size(), 1))] if not cands.is_empty() else []
		var p := rect.get_center()
		var u1 := WorldConst.unit(WorldConst.hash64(h, 1))
		var u2 := WorldConst.unit(WorldConst.hash64(h, 2))
		if not c.is_empty() and str(c[0]) == "seg":
			var a: Vector2 = c[1]
			var b: Vector2 = c[2]
			var t := (b - a).normalized()
			p = a.lerp(b, u1) + Vector2(t.y, -t.x) * (u2 * 2.0 - 1.0) * (float(c[3]) + 3.0)
		elif not c.is_empty():
			var pd: Dictionary = c[1]
			var half: Vector2 = pd["half"]
			var rot := float(pd["rot"])
			var l := Vector2((u1 - 0.5) * 2.0 * half.x, (u2 - 0.5) * 2.0 * half.y)
			p = (pd["c"] as Vector2) + Vector2(l.x * cos(rot) - l.y * sin(rot), l.x * sin(rot) + l.y * cos(rot))
		if not rect.has_point(p) or _inside_building(pl, p, 1.2):
			continue
		var frozen := WorldConst.unit(WorldConst.hash64(h, 3)) < FROZEN_SHARE
		out.append({"pos": p, "yaw": WorldConst.unit(WorldConst.hash64(h, 4)) * TAU, "in": false, "frozen": frozen, "u": WorldConst.unit(WorldConst.hash64(h, 5))})
	return out


static func _inside_building(pl: Array, p: Vector2, margin: float) -> bool:
	for pp: Dictionary in pl:
		for b: Dictionary in pp["buildings"]:
			if SettlementGen.obb_has(b["obb"], p, margin):
				return true
	return false


# ------------------------------------------------------------------ terrain (HeightFunction._setup, main thread)
## Streets → road beds (pinned to the road they join), then building lots / POI yards → level oriented pads at the
## height of the street in front of them (or of their `h_at` point).
static func stamp(hf: HeightFunction) -> void:
	if not enabled:
		return
	for p: Dictionary in plans(hf.world_seed):
		for st: Dictionary in p["streets"]:
			var pts: PackedVector2Array = st["points"]
			var r := {"id": str(st["id"]), "kind": str(st["kind"]), "width": float(st["width"]), "shoulder": float(st["shoulder"]),
				"points": pts, "smooth": 3, "site": str(p["id"]), "street_name": str(st.get("name", ""))}
			if bool(st.get("pin_start", false)):
				r["pin_start"] = hf.sample(pts[0].x, pts[0].y)
			hf.add_road(r)
	for p: Dictionary in plans(hf.world_seed):
		for pd: Dictionary in p["pads"]:
			var ha: Vector2 = pd["h_at"]
			hf.add_pad(pd["c"], pd["half"], float(pd["rot"]), hf.sample(ha.x, ha.y), float(pd["blend"]))


# ------------------------------------------------------------------ queries
## Buildings + items whose centre lies in chunk `key` (world seed `seed_v`), in plan order.
static func items_in_chunk(seed_v: int, key: int) -> Array:
	if not enabled:
		return []
	plans(seed_v)
	var by: Dictionary = _chunks.get(seed_v, {})
	return by.get(key, [])


## Resident target of a chunk (zombies by land use: the buildings' residents + the street / yard share), −1 when no
## site touches the chunk (PopulationTable keeps its own rule there).
static func resident_target(seed_v: int, cx: int, cz: int) -> int:
	if not enabled:
		return -1
	plans(seed_v)
	var r: Dictionary = (_res.get(seed_v, {}) as Dictionary).get(WorldConst.key(cx, cz), {})
	return int(r["target"]) if not r.is_empty() else -1


## The resident spots of a chunk: indoor sleepers (floor 0 of their building) first, then the outdoor ones.
static func resident_spots(seed_v: int, key: int) -> Array:
	plans(seed_v)
	var r: Dictionary = (_res.get(seed_v, {}) as Dictionary).get(key, {})
	return r.get("spots", [])


## True when (x, z) lies inside a site building (+ margin): no random resident / drop inside a wall.
static func occupied(seed_v: int, x: float, z: float, margin: float = 0.0) -> bool:
	if not enabled or not _plans.has(seed_v):
		return false
	return _inside_building(_plans[seed_v], Vector2(x, z), margin)


## Every site's bounds (world rects): the only valley chunks M6b may change (tests/valley_unchanged).
static func all_bounds() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for e in defs():
		var d: Dictionary = e["def"]
		var b: Array = d.get("bounds", [])
		if b.size() >= 4:
			out.append(Rect2(float(b[0]), float(b[1]), float(b[2]), float(b[3])))
	return out


## SHA-256 (hex) of a canonical dump of every plan (layout, templates, styles, uses, doors, items; positions to the
## cm): the «aldea determinista (hash)» of the M6b acceptance — equal on the server and every client of a seed.
static func plan_hash(seed_v: int, site_id: String = "") -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	for p: Dictionary in plans(seed_v):
		if site_id != "" and str(p["id"]) != site_id:
			continue
		var parts := PackedStringArray([str(p["id"])])
		for st: Dictionary in p["streets"]:
			var s := str(st["id"])
			for q in (st["points"] as PackedVector2Array):
				s += ";%d,%d" % [roundi(q.x * 100.0), roundi(q.y * 100.0)]
			parts.append(s)
		for b: Dictionary in p["buildings"]:
			var bp: Vector2 = b["pos"]
			parts.append("B %s %s %s %d,%d,%d %d %s %s %d %x" % [b["template"], b["style"], b["use"], roundi(bp.x * 100.0), roundi(bp.y * 100.0),
				roundi(float(b["yaw"]) * 100.0), int(b["number"]), str(b["shop"]), str(b["enterable"]), int(b["residents"]), int(b["wid"])])
		for e: Dictionary in p["items"]:
			var ep: Vector2 = e["pos"]
			parts.append("I %s %s %d,%d,%d" % [e["k"], e.get("model", ""), roundi(ep.x * 100.0), roundi(ep.y * 100.0), roundi(float(e["yaw"]) * 100.0)])
		hc.update("\n".join(parts).to_utf8_buffer())
	return hc.finish().hex_encode()


## LocationInfo records of the POIs with a zone of their own (the sawmill; the gas station and the farm already are
## PoiRegistry regions): registered by SettlementSpawner so the zone titles (H2) name them.
static func zone_records() -> Array:
	var out: Array = []
	for e in defs():
		var d: Dictionary = e["def"]
		if not (d.get("zone", null) is Dictionary):
			continue   # the village's zone is its W1 region (PoiRegistry)
		var z: Dictionary = d["zone"]
		if z.is_empty() or not z.has("id"):
			continue
		var c := SettlementGen.v2(d["center"])
		out.append(LocationInfo.make(str(z["id"]), str(z["display"]), str(z.get("kind", "poi")), {"circle": [c, float(z.get("radius", 40.0))]},
			{"banner": str(z.get("banner", "")), "parent": str(z.get("parent", "")), "danger": int(z.get("danger", 1)),
			"power": str(z.get("power", "off")), "temp": float(z.get("temp", 0.0)), "zombies": z.get("zombies", [0, 0]), "milestone": "M6b"}))
	return out


## Model paths the sites use (warm-up; tests): sorted, unique.
static func models(seed_v: int) -> Array:
	var set := {}
	for p: Dictionary in plans(seed_v):
		for e: Dictionary in p["items"]:
			set[str(e.get("model", ""))] = true
		for b: Dictionary in p["buildings"]:
			set["buildings/%s/%s" % [str(b["style"]), str(b["template"])]] = true
	set.erase("")
	var out := set.keys()
	out.sort()
	return out
