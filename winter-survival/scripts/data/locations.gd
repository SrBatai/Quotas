class_name Locations
## Every named zone of the world as LocationInfo records (H2, PLAN C35/C36; docs/research/10_hud_ux.md appendix
## §6.1 and §8.6), most specific first — the zone title, the highway sign, the paper map, the mission anchors, the
## camera profile and the group discovery all read this list. Migrated from PoiRegistry (W1):
##   - the slice's small zones inside the clearing (Regions.ZONES; «CLARO» folds into the Claro del cazador);
##   - PoiRegistry.REGIONS: the 16 valley places (display data in KNOWN below) and the 43 W1 records with their
##     LocationInfo fields (id, display, kind, parent, danger, power, temp, zombies, milestone, reserved), including
##     the reserved ones of C1–C3 (terrain + pad only for now); two records with the same banner become one zone;
##   - the water bodies (exact shapes), the named roads (PoiRegistry.ROAD_REGIONS: the road bed + 32 m, measured on
##     that road's own splines), the border ring (LAS CUMBRES), the valley's high forest and the forest (default).
## Order = the region banner's (PoiRegistry.region_at): places → water → named roads → broad areas → border → high
## forest → forest; inside the places the deeper level of the hierarchy wins (POI ⊂ district ⊂ city), so standing in
## Las Torres gives «Las Torres» with «Altavega» as its first fact. `register()` adds zones at runtime (C1+).

const DANGER_NAMES := ["peligro bajo", "peligro moderado", "peligro alto", "peligro extremo"]
const POWER_NAMES := {"off": "sin electricidad", "generator": "con generador", "on": "con electricidad"}
## Card on the first visit / on a re-entry per kind (C35: first visit = the 5.6 s title, re-entry = the name at 60 %
## for 2.5 s; natural areas say nothing on a re-entry; roads get the highway sign once). A player moving faster than
## 40 km/h on a road gets the highway sign instead of any title (ZoneTracker).
const CARD := {
	"city": ["full", "compact"], "district": ["full", "compact"], "town": ["full", "compact"],
	"village": ["full", "compact"], "farm": ["full", "compact"], "poi": ["full", "compact"],
	"natural": ["full", "none"], "road": ["sign", "none"],
}
## A named road zone reaches this far (m) from the edge of its bed (M3: the N‑140 banner within 32 m).
const ROAD_REACH := 32.0
## Road kinds a vehicle drives on (the rail is not one).
const DRIVABLE := ["highway", "avenue", "road", "track"]
## Road plates and sign styles (Spanish signage, doc 10 §7.1): blue autovía, white conventional road with the red
## N plate, white urban avenue.
const ROAD_STYLE := {
	"AUTOVÍA A-14": {"kind": "highway", "plate": "A‐14", "style": "autovia"},
	"N-140": {"kind": "highway", "plate": "N‐140", "style": "nacional"},
	"CARRETERA DEL PUERTO": {"kind": "road", "plate": "", "style": "convencional"},
	"GRAN VÍA": {"kind": "avenue", "plate": "", "style": "urbana"},
	"RONDA NORTE": {"kind": "avenue", "plate": "", "style": "urbana"},
	"RONDA SUR": {"kind": "avenue", "plate": "", "style": "urbana"},
	"FERROCARRIL DEL ALBO": {"kind": "rail", "plate": "", "style": "convencional"},
}
## The city whose zones use the urban camera profile (C28).
const CITY_ID := "altavega"

## Display names and data of the valley places (PoiRegistry keeps their upper-case banner names only).
const KNOWN := {
	"CLARO DEL CAZADOR": {"name": "Claro del cazador", "kind": "poi", "danger": 0},
	"CABAÑA DEL PESCADOR": {"name": "Cabaña del pescador", "kind": "poi", "danger": 0, "parent": "claro_del_cazador"},
	"LAGO HELADO": {"name": "Lago helado", "kind": "natural", "danger": 0, "parent": "claro_del_cazador", "temp": -2.0},
	"PUNTO DE EVACUACIÓN": {"name": "Punto de evacuación", "kind": "poi", "danger": 2, "power": "generator"},
	"CONTROL MILITAR KM 12": {"name": "Control militar km 12", "kind": "poi", "danger": 3, "power": "generator"},
	"GASOLINERA NORTE": {"name": "Gasolinera norte", "kind": "poi", "danger": 1, "power": "off"},
	"GASOLINERA SUR": {"name": "Gasolinera sur", "kind": "poi", "danger": 1, "power": "off"},
	"ÁREA DE DESCANSO": {"name": "Área de descanso", "kind": "poi", "danger": 1, "power": "off"},
	"GRANJA DEL MOLINO": {"name": "Granja del Molino", "kind": "farm", "danger": 1, "power": "off"},
	"GRANJA ALTA": {"name": "Granja Alta", "kind": "farm", "danger": 1, "power": "off"},
	"GRANJA ROMERO": {"name": "Granja Romero", "kind": "farm", "danger": 1, "power": "off"},
	"LA HERRERÍA": {"name": "La Herrería", "kind": "village", "danger": 1, "power": "off"},
	"EL EMBARCADERO": {"name": "El Embarcadero", "kind": "village", "danger": 1, "power": "off"},
	"SAN BLAS": {"name": "San Blas", "kind": "village", "danger": 2, "power": "off"},
	"PRESA": {"name": "Presa", "kind": "poi", "danger": 2, "power": "off", "temp": -3.0},
	"REPETIDOR DEL PICO": {"name": "Repetidor del Pico", "kind": "poi", "danger": 1, "power": "off", "temp": -6.0},
	"TORRE DE VIGILANCIA": {"name": "Torre de vigilancia", "kind": "poi", "danger": 1},
	"VALDENIEVE": {"name": "Valdenieve", "kind": "town", "danger": 2, "power": "off"},
}
## Natural areas of the banner computed by function (after the water and the roads).
const LAKE := {"id": "lago_animas", "name": "Lago de las Ánimas", "banner": "LAGO DE LAS ÁNIMAS", "kind": "natural", "danger": 1, "temp": -3.0}
const BORDER := {"id": "las_cumbres", "name": "Las Cumbres", "banner": "LAS CUMBRES", "kind": "natural", "danger": 1, "temp": -8.0}
const HIGH_FOREST := {"id": "pinos_altos", "name": "Pinos Altos", "banner": "PINOS ALTOS", "kind": "natural", "danger": 1, "temp": -3.0}
static var DEFAULT: Dictionary = LocationInfo.make("bosque_profundo", "Bosque profundo", "natural", {"fn": &"default"},
	{"banner": "BOSQUE PROFUNDO", "danger": 1, "tier": LocationInfo.Tier.DEFAULT})

## Height function for the road zones when no World is running (tests, tools).
static var hf_override: HeightFunction = null

static var _list: Array = []
static var _by_id: Dictionary = {}
static var _extra: Array = []
static var _roads_hf: HeightFunction = null
## banner name -> [PackedVector2Array segment ends (a0, b0, a1, b1…), PackedFloat32Array half widths, PackedFloat32Array
## cumulative metres at each segment start]
static var _roads: Dictionary = {}
## Every drivable road: [PackedVector2Array points, half width, banner name, kind]
static var _drive: Array = []
## Ends of the named roads (junction candidates): [point, banner]
static var _ends: Array = []


## All zones, most specific first (built once; `register` / `reset` rebuild it).
static func all() -> Array:
	if _list.is_empty():
		_build()
	return _list


## A zone by id (or by one of its aliases); {} when unknown.
static func by_id(id: String) -> Dictionary:
	if _list.is_empty():
		_build()
	if _by_id.has(id):
		return _by_id[id]
	return DEFAULT if id == str(DEFAULT["id"]) else {}


## Adds (or replaces, same id) a zone at runtime (a LocationInfo record: LocationInfo.make).
static func register(entry: Dictionary) -> void:
	var e := entry.duplicate(true)
	e["enabled"] = true
	for i in _extra.size():
		if str((_extra[i] as Dictionary)["id"]) == str(e["id"]):
			_extra[i] = e
			_list.clear()
			return
	_extra.append(e)
	_list.clear()


## Test hook: back to the static data.
static func reset() -> void:
	_extra.clear()
	_list.clear()
	hf_override = null


static func _build() -> void:
	var out: Array = []
	# 1. the slice's small zones inside the clearing ("CLARO" is the Claro del cazador below)
	for z: Dictionary in Regions.ZONES:
		var n := str(z["name"])
		if KNOWN.has(n):
			out.append(_known(n, {"circle": [z["center"], float(z["radius"])]}))
	# 2. PoiRegistry.REGIONS (valley places + W1 records); same banner = one zone in several parts
	var merged := {}
	for r: Dictionary in PoiRegistry.REGIONS:
		var n := str(r["name"])
		var shape := {"rect": [r["center"], r["size"]]} if r.has("size") else {"circle": [r["center"], float(r["radius"])]}
		if r.has("water"):
			shape = {"fn": StringName("water:" + str(r["water"]))}   # exact shape (PoiRegistry.natural_depth)
		if merged.has(n):
			var e0: Dictionary = merged[n]
			var parts: Array = (e0["shape"] as Dictionary).get("multi", [e0["shape"]])
			parts.append(shape)
			e0["shape"] = {"multi": parts}
			e0["aliases"] = (e0.get("aliases", []) as Array) + [str(r.get("id", ""))]
			continue
		var e: Dictionary
		if not r.has("display"):
			e = _known(n, shape)
		else:
			var tier := LocationInfo.Tier.PLACE
			if r.has("water"):
				tier = LocationInfo.Tier.WATER
			elif int(r.get("tier", 0)) == 1:
				tier = LocationInfo.Tier.BROAD
			var data := r.duplicate()
			data["banner"] = n
			data["tier"] = tier
			e = LocationInfo.make(str(r["id"]), str(r["display"]), str(r.get("kind", "poi")), shape, data)
		merged[n] = e
		out.append(e)
	# 3. water by function, the named roads, the border ring, the valley's high forest
	out.append(LocationInfo.make(LAKE["id"], LAKE["name"], "natural", {"fn": &"lake"}, _with(LAKE, {"tier": LocationInfo.Tier.WATER})))
	for rn: String in PoiRegistry.ROAD_REGIONS:
		var rr: Dictionary = PoiRegistry.ROAD_REGIONS[rn]
		var st: Dictionary = ROAD_STYLE.get(rn, {"kind": "road", "plate": "", "style": "convencional"})
		var data := _with(rr, {"banner": rn, "tier": LocationInfo.Tier.ROAD, "road": st})
		if str(st["kind"]) == "avenue":
			data["parent"] = CITY_ID
		out.append(LocationInfo.make(str(rr["id"]), str(rr["display"]), "road", {"fn": StringName("road:" + rn)}, data))
	out.append(LocationInfo.make(BORDER["id"], BORDER["name"], "natural", {"fn": &"border"}, _with(BORDER, {"tier": LocationInfo.Tier.BORDER})))
	out.append(LocationInfo.make(HIGH_FOREST["id"], HIGH_FOREST["name"], "natural", {"fn": &"high_forest"},
		_with(HIGH_FOREST, {"tier": LocationInfo.Tier.HIGH_FOREST})))
	for e: Dictionary in _extra:
		out.append(e)
	# index, levels, camera profile
	_by_id.clear()
	for e: Dictionary in out:
		_by_id[str(e["id"])] = e
		for a in e.get("aliases", []):
			_by_id[str(a)] = e
	_by_id[str(DEFAULT["id"])] = DEFAULT
	var ranked: Array = []
	for i in out.size():
		var e: Dictionary = out[i]
		var chain := chain_ids(e)
		if e.get("camera", &"") == &"" and (str(e["id"]) == CITY_ID or chain.has(CITY_ID)):
			e["camera"] = &"city"   # C28: the urban camera profile in Altavega (its districts, POIs and avenues)
		ranked.append([LocationInfo.order_key(e, chain.size()), i, e])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	_list = []
	for r: Array in ranked:
		_list.append(r[2])


static func _known(banner: String, shape: Dictionary) -> Dictionary:
	var k: Dictionary = KNOWN.get(banner, {})
	var display := str(k.get("name", banner.capitalize()))
	var data := k.duplicate()
	data["banner"] = banner
	data["tier"] = LocationInfo.Tier.PLACE
	return LocationInfo.make(slug(display), display, str(k.get("kind", "poi")), shape, data)


static func _with(d: Dictionary, extra: Dictionary) -> Dictionary:
	var o := d.duplicate()
	o.merge(extra, true)
	return o


static func slug(s: String) -> String:
	var t := s.to_lower()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ñ", "n"], ["‑", "-"]]:
		t = t.replace(pair[0], pair[1])
	return t.replace(" ", "_").replace("-", "")


# ------------------------------------------------------------------ geometry
static func hf() -> HeightFunction:
	if hf_override != null:
		return hf_override
	var w := World.instance
	if w != null and w.is_configured:
		return w.hf
	return null


## Signed depth (m) of a point inside a zone: > 0 inside (distance to the border), < 0 outside.
static func depth(e: Dictionary, x: float, z: float) -> float:
	var shape: Dictionary = e["shape"]
	var d := LocationInfo.shape_depth(shape, x, z)
	if not is_nan(d):
		return d
	var fn := String(shape.get("fn", ""))
	match fn:
		"lake":
			return 40.0 - PoiRegistry.lake_sdf(x, z)
		"border", "high_forest":
			return PoiRegistry.natural_depth(fn, x, z)   # W1: per-side border, valley-only high forest
		"default":
			return INF
	if fn.begins_with("water:"):
		return PoiRegistry.natural_depth(fn, x, z)
	if fn.begins_with("road:"):
		return ROAD_REACH - road_edge_distance(fn.substr(5), x, z)
	return -INF


## Inset (m) the player must be inside before a zone counts (12 m; a quarter of the smallest side / half the radius
## in small places).
static func inset(e: Dictionary) -> float:
	var m := LocationInfo.shape_min_size(e["shape"])
	return minf(UiTokens.ZONE_INSET, m * 0.25) if m < INF else UiTokens.ZONE_INSET


## Representative point of a zone (map label, mission anchor, sign distance); Vector2.INF for function shapes.
static func center(e: Dictionary) -> Vector2:
	return LocationInfo.shape_center(e["shape"])


## Every zone containing the point (depth ≥ `margin`), most specific first.
static func containing(x: float, z: float, margin: float = 0.0) -> Array:
	var out: Array = []
	for e: Dictionary in all():
		if depth(e, x, z) >= margin:
			out.append(e)
	return out


## Ids of the ancestors, nearest first.
static func chain_ids(e: Dictionary) -> Array:
	var out: Array = []
	var p := str(e.get("parent", ""))
	var guard := 0
	while p != "" and guard < 6:
		out.append(p)
		var pe := _record_of(p)
		if pe.is_empty():
			break
		p = str(pe.get("parent", ""))
		guard += 1
	return out


## A record by id during the build (the index may not be ready yet).
static func _record_of(id: String) -> Dictionary:
	if _by_id.has(id):
		return _by_id[id]
	var r := PoiRegistry.region_by_id(id)
	if not r.is_empty():
		return {"id": id, "parent": str(r.get("parent", ""))}
	for k: String in KNOWN:
		if slug(str(KNOWN[k]["name"])) == id:
			return {"id": id, "parent": str(KNOWN[k].get("parent", ""))}
	return {}


## Chain of parents (display names), nearest first.
static func parents(e: Dictionary) -> Array:
	var out: Array = []
	for id: String in chain_ids(e):
		var pe := by_id(id)
		if pe.is_empty():
			break
		out.append(str(pe["name"]))
	return out


## True when `e` is `anc` or lies inside it in the hierarchy.
static func is_within(e: Dictionary, anc: Dictionary) -> bool:
	if e.is_empty() or anc.is_empty():
		return false
	return str(e["id"]) == str(anc["id"]) or chain_ids(e).has(str(anc["id"]))


## Card kinds [first visit, re-entry] of a zone. Places (even a road-kind place such as El Gran Atasco) get titles.
static func cards_of(e: Dictionary) -> Array:
	var kind := str(e.get("kind", "poi"))
	if kind == "road" and int(e.get("tier", 0)) == LocationInfo.Tier.PLACE:
		return CARD["poi"]
	return CARD.get(kind, CARD["poi"])


## Danger right now (0–3): the zone's base, +1 at night.
static func danger_now(e: Dictionary, night: bool) -> int:
	return clampi(int(e.get("danger", 1)) + (1 if night else 0), 0, 3)


## The one-line facts of a card: parent · electricity · temperature · danger, as available (§V.4.4).
static func facts(e: Dictionary, air_c: float, night: bool) -> Array:
	var out: Array = []
	var ps := parents(e)
	var kind := str(e.get("kind", "poi"))
	if not ps.is_empty() and kind != "natural":
		out.append(ps[0])
	var power := str(e.get("power", ""))
	if POWER_NAMES.has(power):
		out.append(POWER_NAMES[power])
	out.append(UiTokens.temperature(air_c + float(e.get("temp", 0.0))))
	if kind != "natural" and kind != "road":
		out.append(DANGER_NAMES[danger_now(e, night)])
	return out


# ------------------------------------------------------------------ roads (own splines per banner name)
static func _ensure_roads() -> bool:
	var h := hf()
	if h == null:
		return false
	if h == _roads_hf:
		return true
	_roads_hf = h
	_roads.clear()
	_drive.clear()
	_ends.clear()
	for ri in h.road_count():
		var info := h.road_info(ri)
		var pts: PackedVector2Array = info["points"]
		var hw := float(info["hw"])
		var rname := str(info["name"])
		if DRIVABLE.has(str(info["kind"])):
			_drive.append([pts, hw, rname, str(info["kind"])])
		if rname == "":
			continue
		_ends.append([pts[0], rname])
		_ends.append([pts[pts.size() - 1], rname])
		if not _roads.has(rname):
			_roads[rname] = [PackedVector2Array(), PackedFloat32Array(), PackedFloat32Array()]
		var rec: Array = _roads[rname]
		# packed arrays are values: fill local copies and store them back
		var segs: PackedVector2Array = rec[0]
		var hws: PackedFloat32Array = rec[1]
		var starts: PackedFloat32Array = rec[2]
		var acc := 0.0
		for i in pts.size() - 1:
			segs.append(pts[i])
			segs.append(pts[i + 1])
			hws.append(hw)
			starts.append(acc)
			acc += pts[i].distance_to(pts[i + 1])
		_roads[rname] = [segs, hws, starts]
	return true


## Distance (m) from a point to the edge of the bed of the named road `banner` (< 0 on the bed); INF when unknown.
static func road_edge_distance(banner: String, x: float, z: float) -> float:
	if not _ensure_roads() or not _roads.has(banner):
		return INF
	var rec: Array = _roads[banner]
	var segs: PackedVector2Array = rec[0]
	var hws: PackedFloat32Array = rec[1]
	var p := Vector2(x, z)
	var best := INF
	for i in hws.size():
		var a := segs[i * 2]
		var b := segs[i * 2 + 1]
		# cheap reject: the segment's box grown by the reach
		if p.x < minf(a.x, b.x) - 80.0 or p.x > maxf(a.x, b.x) + 80.0 or p.y < minf(a.y, b.y) - 80.0 or p.y > maxf(a.y, b.y) + 80.0:
			continue
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) - hws[i])
	return best


## The drivable road under a point: {d (m to the bed edge, < 0 on it), name (banner, "" unnamed), kind, dir (unit,
## along the road), km (kilometre point along a named road)}; {} when none within `reach` m.
static func road_at(x: float, z: float, reach: float = 12.0) -> Dictionary:
	if not _ensure_roads():
		return {}
	var p := Vector2(x, z)
	var best := {}
	var best_d := reach
	for r: Array in _drive:
		var pts: PackedVector2Array = r[0]
		var hw := float(r[1])
		var acc := 0.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var l := a.distance_to(b)
			if p.x < minf(a.x, b.x) - hw - reach or p.x > maxf(a.x, b.x) + hw + reach or p.y < minf(a.y, b.y) - hw - reach or p.y > maxf(a.y, b.y) + hw + reach:
				acc += l
				continue
			var q := Geometry2D.get_closest_point_to_segment(p, a, b)
			var d := q.distance_to(p) - hw
			if d < best_d:
				best_d = d
				best = {"d": d, "name": str(r[2]), "kind": str(r[3]), "dir": (b - a) / maxf(l, 0.001), "km": (acc + a.distance_to(q)) / 1000.0}
			acc += l
	return best


## Kilometre point (km) of the named road `banner` nearest to a point; -1 when unknown.
static func road_km(banner: String, x: float, z: float) -> float:
	if not _ensure_roads() or not _roads.has(banner):
		return -1.0
	var rec: Array = _roads[banner]
	var segs: PackedVector2Array = rec[0]
	var starts: PackedFloat32Array = rec[2]
	var p := Vector2(x, z)
	var best := INF
	var km := -1.0
	for i in starts.size():
		var a := segs[i * 2]
		var q := Geometry2D.get_closest_point_to_segment(p, a, segs[i * 2 + 1])
		var d := q.distance_to(p)
		if d < best:
			best = d
			km = (starts[i] + a.distance_to(q)) / 1000.0
	return km


## The next junction ahead on the named road `banner` (another named road ending on it), travelling along `heading`
## from (x, z): {banner, km (its kilometre point on this road), ahead (m)}; {} when none between `min_ahead` and
## `max_ahead` metres.
static func next_junction(banner: String, x: float, z: float, heading: Vector2, min_ahead: float = 150.0, max_ahead: float = 4000.0) -> Dictionary:
	if not _ensure_roads() or not _roads.has(banner):
		return {}
	var here := road_km(banner, x, z)
	var r := road_at(x, z, 16.0)
	var sgn := 1.0
	if r.has("dir") and heading != Vector2.ZERO:
		sgn = 1.0 if (r["dir"] as Vector2).dot(heading) >= 0.0 else -1.0
	var best := {}
	var best_ahead := max_ahead
	for en: Array in _ends:
		var other := str(en[1])
		if other == banner:
			continue
		var q: Vector2 = en[0]
		if road_edge_distance(banner, q.x, q.y) > 40.0:
			continue
		var km := road_km(banner, q.x, q.y)
		var ahead := (km - here) * 1000.0 * sgn
		if ahead >= min_ahead and ahead <= best_ahead:
			best_ahead = ahead
			best = {"banner": other, "km": km, "ahead": ahead}
	return best


## The style of a named road's sign: {kind, plate, style (autovia | nacional | convencional | urbana), display}.
static func road_style(banner: String) -> Dictionary:
	var st: Dictionary = ROAD_STYLE.get(banner, {"kind": "road", "plate": "", "style": "convencional"}).duplicate()
	var rr: Dictionary = PoiRegistry.ROAD_REGIONS.get(banner, {})
	st["display"] = str(rr.get("display", banner.capitalize())).replace("\u2011", "\u2010")
	return st
