extends RefCounted
## Body of tests/m6b_checks.gd (M6b, headless). See the runner for the scope.

const MIN_CHECKS := 37
const SEED := 1337
const SEEDS := [1337, 20260928, 7, 424242]
const VILLAGE := "la_herreria"

var tree: SceneTree
var root: Node3D
var _checks := 0
var _failed := 0


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		_failed += 1
		print("FAIL: ", msg)


func run(p_tree: SceneTree) -> void:
	tree = p_tree
	await tree.process_frame
	print("== VENTISCA M6b checks (La Herrería generator, POIs, stamps, residents, zones, built chunks)")
	root = Node3D.new()
	root.name = "M6bChecks"
	tree.root.add_child(root)
	_data()
	_village()
	_determinism()
	_terrain()
	_residents()
	_zones()
	_loot()
	await _built()
	if _checks < MIN_CHECKS:
		_failed += 1
		print("FAIL: only %d of %d checks ran (a script error above cut a section short)" % [_checks, MIN_CHECKS])
	print("== m6b checks: %d checks, %d failed" % [_checks, _failed])
	tree.quit(0 if _failed == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


# ------------------------------------------------------------------ data
func _data() -> void:
	var ids: Array = []
	for e in Settlements.defs():
		ids.append(str((e["def"] as Dictionary)["id"]))
	check(ids == [VILLAGE, "aserradero", "gasolinera_norte", "granja_molino"],
		"site data: the procedural village + the 3 hand-made POIs (%s)" % [ids])
	var d: Dictionary = Settlements.defs()[0]["def"]
	var reg := PoiRegistry.region_record(str(d.get("region", "")))
	var circ: Array = d["circle"]
	check(not reg.is_empty() and Vector2(float(circ[0]), float(circ[1])).is_equal_approx(reg["center"]) and float(circ[2]) == float(reg["radius"]),
		"La Herrería sits on its W1 region «%s» (%s r %s; macro map v + S, row 6)" % [d.get("region"), circ.slice(0, 2), circ[2]])
	var missing: Array = []
	for p: Dictionary in Settlements.plans(SEED):
		for b: Dictionary in p["buildings"]:
			var fp := "res://data/buildings/templates/%s.json" % b["template"]
			if not FileAccess.file_exists(fp) or not Assets.has_model(KitBuilding.model_name(str(b["template"]), str(b["style"]))):
				missing.append("%s/%s" % [b["style"], b["template"]])
		for e: Dictionary in p["items"]:
			var m := str(e.get("model", ""))
			if m != "" and not Assets.has_model(m):
				missing.append(m)
	check(missing.is_empty(), "every building (template JSON + .glb of its style) and every item model has its art %s" % [missing.slice(0, 8)])


# ------------------------------------------------------------------ the generator
func _village() -> void:
	var p := Settlements.site(SEED, VILLAGE)
	var bl: Array = p["buildings"]
	var n_enter := 0
	var uses := {}
	for b: Dictionary in bl:
		if bool(b["enterable"]):
			n_enter += 1
		uses[str(b["use"])] = int(uses.get(str(b["use"]), 0)) + 1
	check(bl.size() >= 15 and bl.size() <= 20 and n_enter >= 6, "La Herrería (seed %d): %d buildings, %d enterable (15–20, ≥ 6)" % [SEED, bl.size(), n_enter])
	check(uses.has("bar") and uses.has("shop") and uses.has("garage") and int(uses.get("house", 0)) >= bl.size() - 4,
		"land use: reserved bar, shop and garage + houses (%s)" % [uses])
	var streets: Array = p["streets"]
	check(streets.size() >= 2 and streets.size() <= 3 and str(streets[0]["name"]) == "Calle Mayor",
		"streets: the main street + %d branches (1–2; the sawmill lane is one)" % (streets.size() - 1))
	var lot_bad: Array = []
	for l: Dictionary in p["lots"]:
		var h: Vector2 = (l["obb"] as Dictionary)["h"]
		var area := 4.0 * h.x * h.y
		if area < 399.0 or area > 901.0:
			lot_bad.append(snappedf(area, 1.0))
	check(lot_bad.is_empty() and (p["lots"] as Array).size() >= bl.size(), "%d OBB lots, all 400–900 m² %s" % [(p["lots"] as Array).size(), lot_bad])
	# no building overlaps another or a street bed; every building faces its street and stands in the region
	var overlap := 0
	var on_street := 0
	var facing_bad := 0
	var outside := 0
	var circ := Vector2(-704, -768)
	for i in bl.size():
		var a: Dictionary = bl[i]
		for j in range(i + 1, bl.size()):
			if SettlementGen.obb_overlap(a["obb"], (bl[j] as Dictionary)["obb"], 1.0):
				overlap += 1
		for st: Dictionary in streets:
			for o in SettlementGen.corridor(st["points"], float(st["width"]) * 0.5):
				if SettlementGen.obb_overlap(a["obb"], o, 0.5):
					on_street += 1
		var yaw := deg_to_rad(float(a["yaw"]))
		var fwd := Vector2(sin(yaw), cos(yaw))
		var to_street: Vector2 = ((a["p"] as Vector2) - (a["pos"] as Vector2)).normalized()
		if fwd.dot(to_street) < 0.9:
			facing_bad += 1
		for c in SettlementGen.obb_corners(a["obb"]):
			if c.distance_to(circ) > 170.0:
				outside += 1
	check(overlap == 0 and on_street == 0, "no building overlaps another (+1 m) or a street bed (%d / %d)" % [overlap, on_street])
	check(facing_bad == 0 and outside == 0, "every building faces its street and stands inside the region circle (%d / %d)" % [facing_bad, outside])
	var kinds := {}
	for e: Dictionary in p["items"]:
		kinds[str(e["k"])] = int(kinds.get(str(e["k"]), 0)) + 1
	check(int(kinds.get("lamp", 0)) >= 6 and int(kinds.get("pole", 0)) >= 3 and int(kinds.get("car", 0)) >= 3
		and int(kinds.get("sign", 0)) >= 3 and int(kinds.get("container", 0)) >= 1 and int(kinds.get("fence", 0)) >= 1,
		"street dressing: lamps, power poles, fences, signs (village + street names), cars, dumpster %s" % [kinds])
	var entry := false
	for e: Dictionary in p["items"]:
		if str(e.get("model", "")) == "signs/sign_road" and str(e.get("text", "")) == "La Herrería" and str(e.get("back", "")) == "strike":
			entry = true
	check(entry, "the S-500 village sign «La Herrería» (crossed out behind) at the main street's start")


func _determinism() -> void:
	var h1 := Settlements.plan_hash(SEED)
	Settlements.reset()
	var h2 := Settlements.plan_hash(SEED)
	check(h1 == h2 and h1.length() == 64, "plan hash (SHA-256) equal after a fresh rebuild: %s…" % h1.substr(0, 16))
	var hashes := {}
	var rules_ok := true
	var info: Array = []
	for s in SEEDS:
		var v := Settlements.site(int(s), VILLAGE)
		var bl: Array = v["buildings"]
		var ne := 0
		for b: Dictionary in bl:
			if bool(b["enterable"]):
				ne += 1
		if bl.size() < 15 or bl.size() > 20 or ne < 6:
			rules_ok = false
		hashes[Settlements.plan_hash(int(s), VILLAGE)] = true
		info.append("%d: %d/%d" % [s, bl.size(), ne])
	check(rules_ok and hashes.size() == SEEDS.size(), "%d seeds: each village 15–20 buildings / ≥ 6 enterable, all different (%s)" % [SEEDS.size(), ", ".join(info)])
	var wids := {}
	var dup := 0
	for p: Dictionary in Settlements.plans(SEED):
		for b: Dictionary in p["buildings"]:
			if wids.has(int(b["wid"])):
				dup += 1
			wids[int(b["wid"])] = true
			if int(b["wid"]) != KitBuilding.wid_for(SEED, str(p["id"]), int(b["index"])):
				dup += 1
		for e: Dictionary in p["items"]:
			if wids.has(int(e["wid"])):
				dup += 1
			wids[int(e["wid"])] = true
	check(dup == 0 and wids.size() > 100, "%d unique deterministic wids (buildings = KitBuilding.wid_for(seed, site, i))" % wids.size())


# ------------------------------------------------------------------ terrain stamps
func _terrain() -> void:
	var macro := MacroMap.load_default()
	var hf := HeightFunction.create(SEED, macro)
	var p := Settlements.site(SEED, VILLAGE)
	# level pads: each building's footprint corners at its centre's height (±3 cm)
	var worst := 0.0
	for pl: Dictionary in Settlements.plans(SEED):
		for b: Dictionary in pl["buildings"]:
			var o: Dictionary = b["obb"]
			var c: Vector2 = o["c"]
			var h0 := hf.height_at(c.x, c.y)
			for q in SettlementGen.obb_corners(SettlementGen.obb(c, o["u"], (o["h"] as Vector2) - Vector2(0.3, 0.3))):
				worst = maxf(worst, absf(hf.height_at(q.x, q.y) - h0))
	check(worst < 0.03, "every building stands on a level pad (worst corner %.3f m off, ≤ 0.03)" % worst)
	# the main street joins the Valdenieve road at its height; the street bed is asphalt
	var ms: Dictionary = (p["streets"] as Array)[0]
	var pts: PackedVector2Array = ms["points"]
	var j0 := pts[0]
	var road_h := hf.height_at(j0.x, j0.y)
	var s10: Vector2 = SettlementGen.point_at(pts, 12.0)[0]
	var asph := hf.surface_at(s10.x, s10.y).r
	check(absf(hf.height_at(s10.x, s10.y) - road_h) < 1.2 and asph > 0.5,
		"the main street leaves the Valdenieve road level (Δ %.2f m at 12 m) with an asphalt bed (mask %.2f)" % [hf.height_at(s10.x, s10.y) - road_h, asph])
	# a lot pad sits at the height of the street in front of it
	var dh := 0.0
	for b: Dictionary in p["buildings"]:
		var front: Vector2 = b["p"]
		dh = maxf(dh, absf(hf.height_at((b["pos"] as Vector2).x, (b["pos"] as Vector2).y) - hf.height_at(front.x, front.y)))
	check(dh < 0.08, "each lot is levelled at the street in front of it (worst %.3f m)" % dh)
	# every stamp inside the sites' bounds (the valley_unchanged allowance)
	var bounds := Settlements.all_bounds()
	var outside := 0
	for pl: Dictionary in Settlements.plans(SEED):
		for pd: Dictionary in pl["pads"]:
			var inside := false
			for r in bounds:
				if r.grow(8.0).has_point(pd["c"]):
					inside = true
			if not inside:
				outside += 1
		for st: Dictionary in pl["streets"]:
			for q in (st["points"] as PackedVector2Array):
				var ins := false
				for r in bounds:
					if r.grow(2.0).has_point(q):
						ins = true
				if not ins:
					outside += 1
	check(outside == 0, "every pad / street point lies in the sites' bounds (%d outside)" % outside)
	# the scatter keeps off the buildings
	var in_bldg := 0
	var entries := 0
	for b: Dictionary in p["buildings"]:
		var c2: Vector2 = b["pos"]
		for e in ScatterGen.procedural(hf, Rect2(c2 - Vector2(12, 12), Vector2(24, 24))):
			entries += 1
			if SettlementGen.obb_has(b["obb"], Vector2(float(e["x"]), float(e["z"])), 0.5):
				in_bldg += 1
	check(in_bldg == 0, "no tree / rock / pickup of the scatter inside a building (%d of %d entries near them)" % [in_bldg, entries])


# ------------------------------------------------------------------ residents
func _residents() -> void:
	var keys := {}
	var total := 0
	var maxv := 0
	var inside_bad := 0
	var outside_bad := 0
	var p := Settlements.site(SEED, VILLAGE)
	for b: Dictionary in p["buildings"]:
		keys[int(b["key"])] = true
	for k in keys:
		var cx := WorldConst.key_cx(int(k))
		var cz := WorldConst.key_cz(int(k))
		var t := Settlements.resident_target(SEED, cx, cz)
		total += t
		maxv = maxi(maxv, t)
		for sp: Dictionary in Settlements.resident_spots(SEED, int(k)):
			var pos: Vector2 = sp["pos"]
			var in_b := Settlements.occupied(SEED, pos.x, pos.y, 0.0)
			if bool(sp["in"]) and not in_b:
				inside_bad += 1
			if not bool(sp["in"]) and in_b:
				outside_bad += 1
	var avg := float(total) / float(maxi(keys.size(), 1))
	check(avg >= 3.0 and avg <= 8.0 and maxv <= Settlements.MAX_PER_CHUNK,
		"village density by land use: %d residents in %d chunks (%.1f per chunk: aldea 3–8; max %d)" % [total, keys.size(), avg, maxv])
	check(inside_bad == 0 and outside_bad == 0, "indoor sleepers inside their building, outdoor residents outside every building (%d / %d)" % [inside_bad, outside_bad])
	var macro := MacroMap.load_default()
	var hf := HeightFunction.create(SEED, macro)
	var k0: int = keys.keys()[0]
	check(PopulationTable.compute(hf, WorldConst.key_cx(k0), WorldConst.key_cz(k0)) == Settlements.resident_target(SEED, WorldConst.key_cx(k0), WorldConst.key_cz(k0)),
		"PopulationTable uses the land-use target in the village chunks")
	var saw := Settlements.site(SEED, "aserradero")
	var sk := int((saw["buildings"] as Array)[0]["key"])
	check(Settlements.resident_target(SEED, WorldConst.key_cx(sk), WorldConst.key_cz(sk)) >= 5, "the sawmill's shed chunk holds its crew (%d)" % Settlements.resident_target(SEED, WorldConst.key_cx(sk), WorldConst.key_cz(sk)))


# ------------------------------------------------------------------ zones (H2 titles)
func _zones() -> void:
	Locations.reset()
	for z in Settlements.zone_records():
		Locations.register(z)
	var at := func(x: float, z: float) -> String:
		var c := Locations.containing(x, z)
		return str((c[0] as Dictionary)["id"]) if not c.is_empty() else ""
	var p := Settlements.site(SEED, VILLAGE)
	var mid: Vector2 = SettlementGen.point_at(((p["streets"] as Array)[0] as Dictionary)["points"], 60.0)[0]
	var ids := [at.call(mid.x, mid.y), at.call(-632.0, -772.0), at.call(606.0, -386.0), at.call(-128.0, -896.0)]
	check(ids == ["la_herreria", "aserradero_la_herreria", "gasolinera_norte", "granja_del_molino"],
		"zone titles: the village street, the sawmill (registered, inside La Herrería), the gas station, the farm %s" % [ids])
	var saw := Locations.by_id("aserradero_la_herreria")
	check(not saw.is_empty() and str(saw["parent"]) == "la_herreria" and str(saw["kind"]) == "poi" and LocationInfo.validate(saw).is_empty(),
		"the sawmill zone is a valid LocationInfo POI under La Herrería")
	Locations.reset()


# ------------------------------------------------------------------ loot by use
func _loot() -> void:
	var t_ok := true
	for t in [&"shop", &"bar", &"garage", &"sawmill", &"farm", &"car", &"dumpster", &"gas_station", &"house"]:
		var tb := LootTables.table(t)
		if tb.is_empty():
			t_ok = false
			continue
		for e: Dictionary in tb["entries"]:
			if not Items.DB.has(e["id"]):
				t_ok = false
	check(t_ok, "loot tables by building use (shop, bar, garage, sawmill, farm, car, dumpster) use only known items")
	var a := Loot.roll(SEED, 12345, &"car", 1)
	var b := Loot.roll(SEED, 12345, &"car", 1)
	check(JSON.stringify(a) == JSON.stringify(b), "a car boot rolls the same contents twice (%d entries)" % a.size())


# ------------------------------------------------------------------ built chunks
func _built() -> void:
	KitBuilding.render_override = 0
	KitDoor.force_alarm = 1
	var sp := SettlementSpawner.new()
	sp.test_seed = SEED
	root.add_child(sp)
	var keys := {}
	for pl: Dictionary in Settlements.plans(SEED):
		for b: Dictionary in pl["buildings"]:
			keys[int(b["key"])] = true
	var klist := keys.keys()
	klist.sort()
	var holder := Node3D.new()
	root.add_child(holder)
	var t0 := Time.get_ticks_usec()
	var chunks := sp.build_now(holder, klist)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	await _frames(2)
	var n_plan := 0
	for pl: Dictionary in Settlements.plans(SEED):
		n_plan += (pl["buildings"] as Array).size()
	var built := sp.all_buildings()
	check(built.size() == n_plan and chunks.size() == klist.size(), "%d chunks built %d KitBuildings (= the plans) in %.0f ms" % [chunks.size(), built.size(), ms])
	var locked_ok := true
	var alarm := 0
	var remap_ok := true
	var village := Settlements.site(SEED, VILLAGE)
	for b in built:
		var rec: Dictionary = (Settlements.site(SEED, str(b.get_meta("site")))["buildings"] as Array)[int(b.get_meta("index"))]
		for d in b.doors:
			if d.exterior and d.locked != (not bool(rec["enterable"])):
				locked_ok = false
			if d.alarm_armed:
				alarm += 1
		if str(rec["use"]) == "bar":
			for c in b.find_children("loot_*", "LootContainer", true, false):
				if not (c as LootContainer).loose and (c as LootContainer).table_id != &"bar":
					remap_ok = false
	check(locked_ok, "exterior doors locked exactly on the non-enterable houses («Cerrada con llave»)")
	var unreg := 0
	var n_cont := 0
	for b in built:
		for c in b.find_children("loot_*", "LootContainer", true, false):
			n_cont += 1
			if WorldRegistry.get_object(int(c.get_meta("wid"))) != c:
				unreg += 1
	check(n_cont > 20 and unreg == 0, "every building container (moved under its Interior<k>) answers by its wid in the registry (%d of %d missing)" % [unreg, n_cont])
	check(alarm >= 2 and remap_ok, "shop / bar / gas station doors can ring (forced: %d armed); the bar's shelves roll the bar table" % alarm)
	var locked_door: KitDoor = null
	for b in built:
		for d in b.doors:
			if d.locked and locked_door == null:
				locked_door = d
	check(locked_door != null and locked_door.get_interact_label(null) == "Cerrada con llave", "a locked door says «Cerrada con llave»")
	var shop_door: KitDoor = null
	for b in built:
		for d in b.doors:
			if d.alarm_armed and shop_door == null:
				shop_door = d
	if shop_door != null:
		shop_door.apply_net_delta({"open": true, "swing": 1, "alarm": true}, true)
		check(shop_door.alarm_fired and shop_door.alarm_left > 59.0, "the alarm delta starts 60 s of alarm on a peer that sees it live")
		shop_door.apply_net_delta({"alarm": true}, true)
		check(shop_door.alarm_left > 59.0 and shop_door.alarm_fired, "an alarm never restarts from a repeated delta")
	var cars := 0
	var hidden := 0
	var props_mm := 0
	for sc in chunks:
		for c in sc.containers:
			if c.table_id == &"car":
				cars += 1
			if c.hidden_model:
				hidden += 1
		for n in sc.pieces:
			if n is StaticBody3D and n.is_in_group("nav_static"):
				props_mm += (n as StaticBody3D).get_child_count()
	check(cars >= 3 and hidden == cars + _count_items("container"), "car boots (%d) and dumpsters are hidden-model loot containers (%d)" % [cars, hidden])
	check(props_mm > 50, "props / cars carry their collision (%d shapes in the chunks' static bodies)" % props_mm)
	# rebuilding gives the same wids
	var w1 := _wids(built)
	for c in holder.get_children():
		c.free()
	sp.live.clear()
	await _frames(1)
	var chunks2 := sp.build_now(holder, klist)
	var w2 := _wids(sp.all_buildings())
	check(w1.size() > 150 and w1 == w2 and chunks2.size() == chunks.size(), "a second build of the chunks gives the same %d wids (buildings, doors, containers)" % w1.size())
	KitDoor.force_alarm = -1
	KitBuilding.render_override = -1
	holder.queue_free()
	sp.queue_free()
	await _frames(2)


func _count_items(k: String) -> int:
	var n := 0
	for pl: Dictionary in Settlements.plans(SEED):
		for e: Dictionary in pl["items"]:
			if str(e["k"]) == k:
				n += 1
	return n


func _wids(built: Array[KitBuilding]) -> Array:
	var out := []
	for b in built:
		out.append(int(b.get_meta("wid")))
		for d in b.doors:
			out.append(int(d.get_meta("wid")))
		for c in b.find_children("*", "LootContainer", true, false):
			out.append(int(c.get_meta("wid")))
	out.sort()
	return out
