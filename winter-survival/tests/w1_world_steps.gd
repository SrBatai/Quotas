extends RefCounted
## Body of tests/w1_world.gd (loaded at runtime, after the autoloads exist).

const SEED := 1337

## The 20 banner test points of the W1 card (chunk centres; the banner is evaluated per chunk like Regions.name_at,
## the clearing's small zones first). [x, z, expected banner]
const BANNER_POINTS := [
	[0, 0, "CLARO"],
	[192, -512, "VALDENIEVE"],
	[-768, 384, "LAGO DE LAS ÁNIMAS"],
	[640, -1152, "CONTROL MILITAR KM 12"],
	[-1408, 0, "LAS CUMBRES"],
	[1024, -384, "CARRETERA DEL PUERTO"],
	[1536, -384, "CONTROL DEL PUERTO"],
	[1472, 0, "SIERRA DEL CIERZO"],
	[2176, -512, "CATEDRAL DE ALTAVEGA"],
	[2688, -640, "ALTAVEGA — LAS TORRES"],
	[2432, 1600, "RÍO ALBO"],
	[2432, 1216, "PUERTO FLUVIAL DEL ALBO"],
	[3200, -768, "HOSPITAL PROVINCIAL"],
	[4096, 1280, "EL GRAN ATASCO"],
	[4096, 3968, "AUTOVÍA A-14"],
	[3264, 3520, "BASE AÉREA DE LA VEGA"],
	[-640, 2176, "ESTACIÓN DE ESQUÍ PEÑA BLANCA"],
	[640, 2304, "DESFILADERO DE PEÑA ROYA"],
	[-1024, 3072, "IBÓN HELADO"],
	[1024, 3712, "LA VEGA"],
]

var tree: SceneTree
var _checks := 0
var _failed := false


func check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("  ok   " + what)
	else:
		_failed = true
		print("FAIL: " + what)


## Banner name as the game computes it (Regions.name_at / chunk_name) from a height function.
static func banner(hf: HeightFunction, x: float, z: float) -> String:
	var p := Vector2(x, z)
	for zone in Regions.ZONES:
		if p.distance_to(zone["center"]) <= float(zone["radius"]):
			return zone["name"]
	var cx := WorldConst.chunk_of(x)
	var cz := WorldConst.chunk_of(z)
	var c := WorldConst.chunk_center(cx, cz)
	var n := PoiRegistry.region_of_chunk(cx, cz, hf.named_road_at(c.x, c.z, 32.0))
	return Regions.DEFAULT if n == "CLARO DEL CAZADOR" else n


func run(p_tree: SceneTree) -> void:
	tree = p_tree
	await tree.process_frame
	var t0 := Time.get_ticks_msec()
	print("== W1 world checks")
	# ---- grid, keys, walls
	check(WorldConst.WORLD_CHUNKS == 96 and WorldConst.CENTER_CHUNK == 24 and WorldConst.chunk_of(0.0) == 24
		and WorldConst.chunk_of(WorldConst.EXTENT_MIN + 0.1) == 0 and WorldConst.chunk_of(WorldConst.EXTENT_MAX - 0.1) == 95
		and WorldConst.key_cx(WorldConst.key(95, 7)) == 95 and WorldConst.key_cz(WorldConst.key(95, 7)) == 7
		and WorldConst.key(24, 24) == (24 << 16 | 24) and WorldConst.in_grid(95, 95) and not WorldConst.in_grid(96, 0),
		"WorldConst: 96 × 96 chunks of 64 m, chunk 24 on the origin, keys cx << 16 | cz unchanged (%d)" % WorldConst.key(95, 95))
	check(WorldConst.in_playable(4400.0, 4400.0) and not WorldConst.in_playable(4425.0, 0.0) and not WorldConst.in_playable(0.0, -1455.0)
		and WorldConst.clamp_playable(9000.0, -9000.0, 2.0) == Vector2(4418.0, -1448.0) and is_equal_approx(WorldConst.wall_distance(0, 0), 1450.0)
		and is_equal_approx(WorldConst.wall_distance(4000, 2000), 420.0), "walls per axis: x, z ∈ [−1450, 4420] (clamp, distance to the nearest wall)")
	check(WorldConst.quadrant(0, 0) == 0 and WorldConst.quadrant(2688, -384) == 1 and WorldConst.quadrant(-640, 2176) == 2 and WorldConst.quadrant(3264, 3520) == 3,
		"quadrants: valley NW, Altavega NE, Peña Blanca SW, La Vega SE")
	var fog_ok := (is_equal_approx(World.border_fog_scale(0, 0), 1.0) and World.border_fog_scale(4415, 1000) > 3.8
		and World.border_fog_scale(1000, 4415) > 3.8 and World.border_fog_scale(-1445, 0) > 3.8 and is_equal_approx(World.border_fog_scale(1400, 0), 1.0)
		and is_equal_approx(World.border_fog_scale(-1300, 0), 1.0 + 3.0 * HeightFunction.smooth(1252.0, 1450.0, 1300.0)))
	check(fog_ok, "border fog per side (nearest wall), the M3 ramp on the valley's west side; none at the old east border (x 1400)")
	# ---- macro map
	ScatterCatalog.load_manifests()
	var macro := MacroMap.load_default()
	check(macro.ok and macro.rel.size() == 768 * 768 and MacroMap.SIZE == 768, "macro map 768² at 8 m/px loaded")
	var biomes := {}
	for b in macro.biome:
		biomes[b] = true
	check(biomes.size() == MacroMap.BIOME_COUNT, "all %d biomes painted (%d)" % [MacroMap.BIOME_COUNT, biomes.size()])
	check(macro.biome_at(2688, -384) == MacroMap.Biome.FINANCIAL and macro.biome_at(2048, -700) == MacroMap.Biome.OLD_TOWN
		and macro.biome_at(3200, 1300) == MacroMap.Biome.INDUSTRIAL and macro.biome_at(2432, 900) == MacroMap.Biome.RIVER
		and macro.biome_at(3300, 3500) == MacroMap.Biome.AIRBASE and macro.biome_at(-640, 1900) == MacroMap.Biome.SKI,
		"biomes where doc 09 §4.2 puts them (financial, old town, industrial, river, air base, ski)")
	var hf := HeightFunction.create(SEED, macro)
	# ---- banners
	var wrong: Array[String] = []
	for p in BANNER_POINTS:
		var got := banner(hf, float(p[0]), float(p[1]))
		if got != str(p[2]):
			wrong.append("(%d, %d) %s ≠ %s" % [int(p[0]), int(p[1]), got, str(p[2])])
	check(wrong.is_empty(), "banner / region correct at the 20 W1 test points %s" % [wrong])
	# ---- LocationInfo data (H2)
	var missing: Array[String] = []
	var ids := {}
	for r: Dictionary in PoiRegistry.REGIONS:
		if not r.has("id"):
			continue
		ids[str(r["id"])] = true
		for f in ["name", "display", "kind", "parent", "danger", "power", "temp", "zombies", "milestone", "reserved"]:
			if not r.has(f):
				missing.append("%s.%s" % [r["id"], f])
	for r: Dictionary in PoiRegistry.REGIONS:
		var par := str(r.get("parent", ""))
		if par != "" and not ids.has(par):
			missing.append("%s.parent=%s" % [r.get("id", r["name"]), par])
	check(missing.is_empty() and ids.size() >= 40, "LocationInfo data: %d W1 regions with id, display, kind, parent, danger, power, temp, zombies, milestone %s" % [ids.size(), missing])
	var chain := PoiRegistry.regions_containing(2688, -640)
	var chain_ids := []
	for r: Dictionary in chain:
		chain_ids.append(str(r.get("id", r["name"])))
	check(chain_ids.has("altavega_las_torres") and chain_ids.has("altavega") and chain_ids.find("altavega_las_torres") < chain_ids.find("altavega"),
		"hierarchy at Las Torres: district before the city %s" % [chain_ids])
	var loc := Locations.by_id("altavega_las_torres")
	check(not loc.is_empty() and str(loc["name"]) == "Las Torres" and str(loc["parent"]) == "altavega" and Locations.depth(loc, 2688, -640) > 0.0
		and Locations.depth(Locations.by_id("las_cumbres"), 4400, 1000) > 0.0 and Locations.depth(Locations.by_id("las_cumbres"), 1400, 0) < 0.0
		and Locations.depth(Locations.by_id("pinos_altos"), 2000, 0) < 0.0 and Locations.depth(Locations.by_id("rio_albo"), 2432, 2000) > 0.0,
		"Locations (H1/H2) reads the W1 regions: Las Torres ⊂ Altavega, border per side, Pinos Altos only in the valley, río Albo")
	var bad_names: Array[String] = []
	for r: Dictionary in PoiRegistry.REGIONS:
		for w in ["ALBARR", "ALBAR ", "Albarr"]:
			if str(r["name"]).contains(w) or str(r.get("display", "")).contains(w):
				bad_names.append(str(r["name"]))
	check(bad_names.is_empty() and not PoiRegistry.region_record("RÍO ALBO").is_empty(), "final names (C36): Altavega, río Albo; no «Albarrán» / «Albar»")
	# ---- water: flat, safe ice
	var ice_bad: Array[String] = []
	for q in [Vector2(2432, -900), Vector2(2432, 0), Vector2(2430, 1216), Vector2(2330, 1100), Vector2(2540, 1400), Vector2(2432, 2560),
			Vector2(2430, 3968), Vector2(2432, -384), Vector2(2432, 640)]:
		if absf(hf.height_at(q.x, q.y) - PoiRegistry.RIVER_LEVEL) > 0.001 or hf.surface_at(q.x, q.y).g8 < 250 or not hf.is_w1_water(q.x, q.y):
			ice_bad.append("%s h=%.2f" % [q, hf.height_at(q.x, q.y)])
	for q in [Vector2(2432, -1500), Vector2(-1024, 3072)]:
		var lvl := float(PoiRegistry.WATER[int(PoiRegistry.water_at(q.x, q.y, 0.0).z)]["level"])
		if absf(hf.height_at(q.x, q.y) - lvl) > 0.001 or hf.surface_at(q.x, q.y).g8 < 250:
			ice_bad.append("%s h=%.2f" % [q, hf.height_at(q.x, q.y)])
	check(ice_bad.is_empty(), "río Albo, dársena (%.0f m), embalse and ibón: flat ice with the ice mask, also under the future bridges %s" % [PoiRegistry.RIVER_LEVEL, ice_bad])
	var bank := hf.height_at(2432 + 64 + 30, 300)
	check(bank > PoiRegistry.RIVER_LEVEL + 0.8 and hf.surface_at(2432 + 64 + 30, 300).g8 == 0, "the banks stand above the ice (%.1f m) and are not ice" % bank)
	# ---- roads and rail as stamps
	var info := {}
	for ri in hf.road_count():
		var ri_info := hf.road_info(ri)
		info[str(ri_info["id"])] = ri_info
	var need := ["n140", "carretera_puerto", "gran_via", "ronda_norte", "ronda_sur", "a14", "n140_sur", "ferrocarril_eo", "ferrocarril_ns"]
	var have := need.filter(func(id: String) -> bool: return info.has(id))
	check(have.size() == need.size(), "splines: N‑140, Carretera del Puerto, Gran Vía, rondas, A‑14, N‑140 sur, ferrocarril (%d roads)" % hf.road_count())
	var cp: Dictionary = info.get("carretera_puerto", {})
	var max_grade := 0.0
	var asphalt := true
	if not cp.is_empty():
		var len_m := float(cp["length"])
		var s := 0.0
		var prev := INF
		var ri2 := -1
		for ri in hf.road_count():
			if str(hf.road_info(ri)["id"]) == "carretera_puerto":
				ri2 = ri
		while s < len_m:
			var pd := hf.road_point_dir(ri2, s)
			var p: Vector2 = pd[0]
			var hh := hf.height_at(p.x, p.y)
			if prev != INF:
				max_grade = maxf(max_grade, absf(hh - prev) / 8.0)
			prev = hh
			if hf.surface_at(p.x, p.y).r8 < 200:
				asphalt = false
			s += 8.0
	check(not cp.is_empty() and max_grade <= 0.12 and asphalt and float(cp["length"]) > 1100.0,
		"Carretera del Puerto: %.0f m of asphalt over the Sierra del Cierzo, max grade %.1f %% (≤ 12 %%)" % [float(cp.get("length", 0.0)), max_grade * 100.0])
	check(hf.surface_at(2432, -384).r8 == 0 and hf.surface_at(2250, -384).r8 > 200 and hf.surface_at(2620, -384).r8 > 200,
		"the Gran Vía stops at the banks of the Albo (no road bed on the ice until the Puente de Hierro, C1)")
	check(hf.named_road_at(4096, 0) == "AUTOVÍA A-14" and hf.surface_at(4096, 2000).r8 > 200 and hf.surface_at(3712, 1600).b8 > 100 and hf.surface_at(3712, 1600).a8 == 0,
		"A‑14 asphalt, railway bed packed snow without ruts")
	# ---- pads
	var pad_bad: Array[String] = []
	for pad: Dictionary in PoiRegistry.PADS:
		if not bool(pad.get("reserved", false)):
			continue
		var c: Vector2 = pad["center"]
		var half: Vector2 = (pad["size"] as Vector2) * 0.5 if pad.has("size") else Vector2.ONE * float(pad["radius"]) * 0.42
		half = half.min(Vector2(60, 60))
		var lo := INF
		var hi := -INF
		for k in 9:
			var q := c + Vector2((float(k % 3) - 1.0) * half.x * 0.9, (float(k / 3) - 1.0) * half.y * 0.9)
			var hq := hf.height_at(q.x, q.y)
			lo = minf(lo, hq)
			hi = maxf(hi, hq)
		# W1 roads run level over the W1 pads (HeightFunction._fix_pads): only the road's own camber remains
		if hi - lo > 0.35:
			pad_bad.append("%s %.2f m" % [pad["id"], hi - lo])
	check(pad_bad.is_empty(), "reserved pads of C1–C3 are flat (≤ 0.35 m across) %s" % [pad_bad])
	# ---- W1 art placements (placeholders until assets/models/world/ has them)
	var portals := 0
	for pad: Dictionary in PoiRegistry.PADS:
		if str(pad.get("model", "")).begins_with("tunnel_portal"):
			portals += 1
			var at: Vector2 = pad.get("model_at", pad["center"])
			var got := ScatterGen.poi_entries(SEED, Rect2(at - Vector2(1, 1), Vector2(2, 2)))
			if got.is_empty():
				portals = -100
	# the art contract (T2): the terrain stays at road level inside each portal's `carve` rect (x ±6.5, z −12.2…0.3)
	var carve_bad: Array[String] = []
	for pad: Dictionary in PoiRegistry.PADS:
		if not str(pad.get("model", "")).begins_with("tunnel_portal"):
			continue
		var at: Vector2 = pad.get("model_at", pad["center"])
		var y0 := hf.height_at(at.x, at.y)
		var yaw := deg_to_rad(float(pad.get("yaw", 0.0)))
		var worst := -INF
		for iz in 6:
			for ix in 5:
				var lp := Vector2(-6.5 + 13.0 * ix / 4.0, -12.2 + 12.5 * iz / 5.0)
				# model frame → world (rotation about +Y by yaw: x' = x cos + z sin, z' = −x sin + z cos)
				var wp := at + Vector2(lp.x * cos(yaw) + lp.y * sin(yaw), -lp.x * sin(yaw) + lp.y * cos(yaw))
				worst = maxf(worst, hf.height_at(wp.x, wp.y) - y0)
		if worst > 0.25:
			carve_bad.append("%s +%.2f m" % [pad["id"], worst])
	check(carve_bad.is_empty(), "tunnel portals: the ground inside the art's carve rect stays at the mouth's level %s" % [carve_bad])
	check(portals == 8, "tunnel portals on their pads: Peña Roya north (collapsed) and south, A‑14 north / south (one per carriageway), railway north / west")
	var counts := {}
	for rect in [Rect2(1400, -700, 256, 256), Rect2(1100, -420, 700, 80), Rect2(-900, 1500, 512, 512)]:
		for e in ScatterGen.procedural(hf, rect):
			var n := ScatterCatalog.name_of(int(e["v"]))
			counts[n] = int(counts.get(n, 0)) + 1
	var crest := int(counts.get("crest_rock_a", 0)) + int(counts.get("crest_rock_b", 0)) + int(counts.get("crest_spire", 0)) + int(counts.get("cornice", 0)) + int(counts.get("scree_field", 0))
	check(crest > 0 and int(counts.get("snow_pole", 0)) + int(counts.get("snow_pole_tall", 0)) > 10 and int(counts.get("guardrail", 0)) > 20,
		"W1 props: crests on the sierras (%d), snow poles (%d) and guardrails (%d) along the Carretera del Puerto" % [crest,
			int(counts.get("snow_pole", 0)) + int(counts.get("snow_pole_tall", 0)), int(counts.get("guardrail", 0)) + int(counts.get("guardrail_end", 0)) + int(counts.get("guardrail_bent", 0))])
	var on_ice := 0
	for e in ScatterGen.procedural(hf, Rect2(2368, 0, 128, 512)):
		if hf.is_w1_water(float(e["x"]), float(e["z"])):
			on_ice += 1
	var city_trees := 0
	for e in ScatterGen.procedural(hf, Rect2(2560, -640, 256, 256)):
		if int(e["v"]) >= 0 and ScatterCatalog.variant(int(e["v"]))["kind"] == ScatterCatalog.Kind.TREE:
			city_trees += 1
	check(on_ice == 0 and city_trees < 20, "nothing grows on the ice; Las Torres is open ground until C1 (%d trees in 256² m)" % city_trees)
	# ---- population table 96²
	var pt := PopulationTable.create(hf)
	var tp0 := Time.get_ticks_usec()
	pt.fill_all()
	var tp_ms := (Time.get_ticks_usec() - tp0) / 1000.0
	var total := 0
	var q_tot := [0, 0, 0, 0]
	var maxv := 0
	for cz in WorldConst.WORLD_CHUNKS:
		for cx in WorldConst.WORLD_CHUNKS:
			var v := pt.target(cx, cz)
			total += v
			maxv = maxi(maxv, v)
			var c := WorldConst.chunk_center(cx, cz)
			q_tot[WorldConst.quadrant(c.x, c.z)] += v
	check(pt.table.size() == 9216 and pt.target(24, 24) == 0 and pt.target(0, 0) == 0 and q_tot[0] > 0 and q_tot[1] > q_tot[0] and q_tot[2] > 0 and q_tot[3] > 0 and maxv <= PopulationTable.UNBUILT_CAP,
		"population table 96² (%d B): residents NW %d, NE %d, SW %d, SE %d (max %d per chunk; %.0f ms to fill)" % [pt.table.size(), q_tot[0], q_tot[1], q_tot[2], q_tot[3], maxv, tp_ms])
	# ---- chunk cost per quadrant (informative) and the far corners
	var clearing := ScatterGen.clearing_entries(SEED)
	var gen_ms := []
	for p in [Vector2(-500, -500), Vector2(2688, -384), Vector2(-640, 2176), Vector2(3264, 3520), Vector2(4390, 4390), Vector2(1536, -384)]:
		var j := ChunkJob.new()
		j.cx = WorldConst.chunk_of(p.x)
		j.cz = WorldConst.chunk_of(p.y)
		j.key = WorldConst.key(j.cx, j.cz)
		j.hf = hf
		j.clearing = clearing
		j.visual = true
		j.run()
		gen_ms.append(snappedf(j.usec / 1000.0, 0.1))
	check(true, "chunk generation (visual, one thread) NW / NE / SW / SE / far corner / Control del Puerto: %s ms" % [gen_ms])
	print("== %d checks, %s (%d ms)" % [_checks, "FAILED" if _failed else "ALL PASSED", Time.get_ticks_msec() - t0])
	tree.quit(1 if _failed else 0)
