extends RefCounted
## Body of tests/c1_city.gd (loaded at runtime, after the autoloads exist).

const SEED := 1337
## Sample points (world x, z): a casco street, an ensanche chaflán crossing, between barriada slabs, the Edificio
## Meridiano (hero), the Control del Puerto, LT-01 (C0's superblock, unchanged).
const SAMPLES := {"casco": Vector2(2024, -611), "ensanche": Vector2(3003, -511), "barriada": Vector2(1990, 262),
	"meridiano": Vector2(2812, -446), "control": Vector2(1536, -384), "lt01": Vector2(2680, -446)}
## Zone title of each district (LocationInfo display name of the most specific zone at a street point of it).
const TITLES := {"casco_viejo": "Casco viejo", "ensanche": "Ensanche", "barriada": "Barriada de San Lázaro", "las_torres": "Las Torres"}

var tree: SceneTree
var hf: HeightFunction
var _checks := 0
var _failed := false


func check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("  ok   " + what)
	else:
		_failed = true
		print("FAIL: " + what)


func run(p_tree: SceneTree) -> void:
	tree = p_tree
	await tree.process_frame
	var t0 := Time.get_ticks_msec()
	var digest_out := ""
	var do_gen := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--digest="):
			digest_out = a.substr(9)
		if a == "--no-gen":
			do_gen = false
	print("== C1 city (Altavega: núcleo urbano)")
	ScatterCatalog.load_manifests()
	var macro := MacroMap.load_default()
	hf = HeightFunction.create(SEED, macro)
	Locations.hf_override = hf
	# ---- lot file + generator
	var ok := CityLots.load_default()
	check(ok and CityLots.problems().is_empty(), "lot file %s loads and validates %s" % [CityLots.PATH, CityLots.problems()])
	check(CityLots.city_version() == 1 and WorldConst.CITY_VERSION == 1 and PersistenceSchema.city_version() == 1,
		"city_version 1 = WorldConst.CITY_VERSION = world_meta.city_version (C0 → C1 migration: no city deltas existed)")
	var d := CityLots.data()
	var st: Dictionary = d.get("stats", {})
	if do_gen:
		var src: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/city/districts.json"))
		var g0 := Time.get_ticks_msec()
		var gen := CityGen.new()
		var text := CityGen.serialize(gen.run(src, HeightFunction.create(1337, macro)))
		var file_text := FileAccess.get_file_as_string(CityLots.PATH)
		check(text == file_text and gen.problems.is_empty(), "tools/gen_city.gd reproduces the lot file byte for byte (%d bytes, %d ms)" % [text.length(), Time.get_ticks_msec() - g0])
	var rows: Array = d["buildings"]["rows"]
	var by_fam := {}
	var by_district := {}
	var ent := 0
	for r in rows:
		by_fam[str(r[1])] = int(by_fam.get(str(r[1]), 0)) + 1
		by_district[int(r[9])] = int(by_district.get(int(r[9]), 0)) + 1
		if int(r[8]) & 1:
			ent += 1
	check(rows.size() >= 2000 and by_fam.has("casco") and by_fam.has("ensanche") and by_fam.has("bloque") and by_fam.has("caseta"),
		"%d generated lots in 4 families %s" % [rows.size(), by_fam])
	check(by_district.get(0, 0) > 500 and by_district.get(1, 0) > 500 and by_district.get(2, 0) >= 30,
		"lots per district (0 casco, 1 ensanche, 2 barriada): %s; Las Torres: %d podiums, %d towers, %d heroes" % [by_district,
		CityLots.podiums().size(), CityLots.towers().size(), CityLots.heroes().size()])
	check(CityLots.towers().size() >= 20 and CityLots.heroes().size() == 2 and ent >= 150,
		"Las Torres holds ≥ 20 A1 towers and the 2 hero towers; %d enterable ground floors" % ent)
	# LT-01 (C0) kept as it was
	var lt_ok := true
	for id in [21, 22, 23, 24, 25]:
		var found := false
		for t in CityLots.towers():
			if int(t["id"]) == id:
				found = true
		lt_ok = lt_ok and found
	check(lt_ok and not CityLots.podium(11).is_empty() and CityLots.miradores().size() >= 5,
		"C0's superblock LT-01 (podiums 11–14, towers 21–25) and the provisional mirador kept; %d miradores" % CityLots.miradores().size())
	# no overlaps, no lot on the ice, every lot in its district rect
	var overlaps := 0
	var wet := 0
	var tested := 0
	var ids := CityLots.building_ids()
	for i in range(0, ids.size(), 3):
		var b := CityLots.building(int(ids[i]))
		var q := CityLots.obb(b["pos"], (b["size"] as Vector2) - Vector2(0.4, 0.4), float(b["yaw"]))
		var p: Vector2 = b["pos"]
		if hf.is_w1_water(p.x, p.y):
			wet += 1
		for j in range(i + 1, mini(i + 40, ids.size())):
			var o := CityLots.building(int(ids[j]))
			if (o["pos"] as Vector2).distance_to(p) > 45.0:
				continue
			if CityGen._overlap(q, CityLots.obb(o["pos"], (o["size"] as Vector2) - Vector2(0.4, 0.4), float(o["yaw"]))):
				overlaps += 1
		tested += 1
	check(overlaps == 0 and wet == 0, "no lot overlaps its neighbours (%d lots tested) nor stands on the río Albo ice" % tested)
	# zone titles of the four districts (H2's LocationInfo)
	var titles := {}
	for di in CityGen.DISTRICT_IDS.size():
		var dist: String = CityGen.DISTRICT_IDS[di]
		var got := ""
		var zr := Rect2()
		for z in CityLots.districts():
			if str(z["district"]) == dist:
				zr = CityLots.rect_of(z["rect"])
		var best := INF
		var bp := Vector2.ZERO
		for r in rows:
			if int(r[9]) != di:
				continue
			var p := Vector2(float(r[4]) / 100.0, float(r[5]) / 100.0)
			if p.distance_to(zr.get_center()) < best:
				best = p.distance_to(zr.get_center())
				bp = p
		var zs := Locations.containing(bp.x, bp.y, 12.0)
		if not zs.is_empty():
			got = str((zs[0] as Dictionary)["name"])
		if dist == "las_torres":
			var h := CityLots.heroes()[0] as Dictionary
			var zs2 := Locations.containing(CityLots.cm(h["pos"][0]), CityLots.cm(h["pos"][1]) + 30.0, 12.0)
			got = str((zs2[0] as Dictionary)["name"]) if not zs2.is_empty() else ""
		titles[dist] = got
	var titles_ok := true
	for k in TITLES:
		titles_ok = titles_ok and str(titles.get(k, "")) == str(TITLES[k])
	check(titles_ok, "zone titles of the four districts (LocationInfo, most specific first): %s" % [titles])
	var cams := {}
	for k in ["altavega_casco_viejo", "altavega_ensanche", "barriada_de_san_lazaro", "altavega_las_torres", "catedral"]:
		cams[k] = Locations.by_id(k).get("camera", &"")
	check(cams["altavega_casco_viejo"] == &"casco" and cams["altavega_ensanche"] == &"ensanche" and cams["barriada_de_san_lazaro"] == &"barriada"
		and cams["altavega_las_torres"] == &"torres" and cams["catedral"] == &"casco", "district camera profiles (casco / ensanche / barriada / torres; POIs inherit): %s" % [cams])
	var far_street := CameraProfile.far_for(95.0, 44.0, -43.0, 36.0, 0.0)
	var far_roof := CameraProfile.far_for(130.0, 50.0, -40.0, 36.0, 92.0)
	check(is_equal_approx(far_street, 95.0) and far_roof > 250.0, "dynamic far: street %.0f m (the profile's), 92 m up a tower roof %.0f m (the street stays in frame)" % [far_street, far_roof])
	# street graph: one connected net
	var gr := CityLots.graph()
	var comp := _largest_component(gr)
	check((gr["nodes"] as Array).size() > 300 and float(comp) >= 0.9 * float((gr["nodes"] as Array).size()),
		"street graph: %d nodes, %d edges, the largest connected part holds %d nodes" % [(gr["nodes"] as Array).size(), (gr["edges"] as Array).size(), comp])
	# ---- families: contract and budgets at their tallest, enterable and not
	var fam_probs: Array = []
	var max_tris := 0
	for fam in BuildingAssembler.FAMILIES:
		for vi in BuildingAssembler.variant_count(fam):
			var fl: Array = BuildingAssembler.FAMILIES[fam]["floors"]
			for e in [false, true]:
				var root := BuildingAssembler.build({"id": 1, "fam": fam, "var": vi, "floors": int(fl[1]), "pal": vi, "ent": e, "wid": 9}, true)
				var pr := CityBuilding.validate(root, true)
				if not pr.is_empty():
					fam_probs.append("%s/%d/%s: %s" % [fam, vi, e, pr])
				max_tris = maxi(max_tris, int(BuildingAssembler.data(fam, vi, int(fl[1]), vi, e)["tris"]))
				root.free()
	check(fam_probs.is_empty() and max_tris <= 12000, "every family variant passes the city contract (Base / ShadowProxy / door leaf, no y offsets); max %d triangles %s" % [max_tris, fam_probs])
	# ---- streaming: sample chunks through ChunkJob → WorldChunk (visual client)
	var root3d := Node3D.new()
	root3d.name = "C1Chunks"
	tree.root.add_child(root3d)
	var lights := CityLights.new()
	lights.name = "CityLights"
	tree.root.add_child(lights)
	var cut := CityCut.new()
	tree.root.add_child(cut)
	var keys: Array[int] = []
	for k in SAMPLES:
		var p: Vector2 = SAMPLES[k]
		for rk in WorldConst.ring_keys(WorldConst.chunk_of(p.x), WorldConst.chunk_of(p.y), 1 if k != "lt01" else 0):
			if not keys.has(rk):
				keys.append(rk)
	var jobs: Array[ChunkJob] = []
	var tids: Array[int] = []
	for k in keys:
		var j := ChunkJob.new()
		j.cx = WorldConst.key_cx(k)
		j.cz = WorldConst.key_cz(k)
		j.key = k
		j.hf = hf
		j.visual = true
		jobs.append(j)
		tids.append(WorkerThreadPool.add_task(j.run, false, "c1 job"))
	for id in tids:
		WorkerThreadPool.wait_for_task_completion(id)
	var chunks: Array[WorldChunk] = []
	var step_max := {}
	var cleared_bad := 0
	var road := 0
	var walk := 0
	for j in jobs:
		for e in j.entries:
			if CityLots.is_cleared(float(e["x"]), float(e["z"])):
				cleared_bad += 1
		for sv in j.surface:
			if (sv & 255) == 230:
				road += 1
			elif ((sv >> 16) & 255) == 204:
				walk += 1
		var c := WorldChunk.new()
		c.setup(j, true, true)
		root3d.add_child(c)
		while c.state != WorldChunk.State.LOADED:
			var kind := c.step_kind()
			var s0 := Time.get_ticks_usec()
			c.step()
			var us := Time.get_ticks_usec() - s0
			if kind.begins_with("_step_city"):
				step_max[kind] = maxi(int(step_max.get(kind, 0)), us)
		chunks.append(c)
	var n_b := 0
	var n_lots := 0
	var n_doors := 0
	var n_loot := 0
	var items_b := 0
	var heroes: Array[HeroTower] = []
	for c in chunks:
		if c.city == null:
			continue
		n_b += c.city.buildings.size()
		for e in c.data.city:
			if int(e["k"]) in [CityLots.Kind.PODIUM, CityLots.Kind.TOWER, CityLots.Kind.BUILDING, CityLots.Kind.HERO]:
				items_b += 1
			if int(e["k"]) == CityLots.Kind.BUILDING:
				n_lots += 1
		for b in c.city.buildings:
			n_doors += b.find_children("*", "KitDoor", true, false).size()
			n_loot += b.find_children("*", "LootContainer", true, false).size()
			if b is HeroTower:
				heroes.append(b as HeroTower)
	check(n_b == items_b and n_lots > 150 and cleared_bad == 0 and road > 2000 and walk > 2000,
		"%d chunks streamed: %d buildings (%d family lots) = their items; streets painted (%d road, %d sidewalk samples), no scatter in the city" % [chunks.size(), n_b, n_lots, road, walk])
	check(n_doors >= 10 and n_loot >= 20, "enterable ground floors and the hero tower built their KitDoors (%d) and loot containers (%d)" % [n_doors, n_loot])
	check(heroes.size() == 1 and heroes[0].hero_id == 902, "the Edificio Meridiano streamed as a HeroTower (%s)" % [heroes])
	var worst := 0
	for k in step_max:
		worst = maxi(worst, int(step_max[k]))
	print("  info city step max µs by kind (headless, cold family caches in the workers): %s" % [step_max])
	# hero tower: finish the meshes, contract, stairs, doors, roof
	var ht: HeroTower = heroes[0] if not heroes.is_empty() else null
	if ht != null:
		ht.finish_now()
		var pr := CityBuilding.validate(ht, true)
		var shafts := 0
		for ch in ht.get_children():
			if String(ch.name).begins_with("Shaft_"):
				shafts += 1
		check(pr.is_empty() and shafts == 5 and ht.get_node_or_null("Roof") != null and ht.get_node_or_null("CityBuilding") != null,
			"Meridiano: 24 floors = Base + %d floor groups + Roof + ShadowProxy, the city contract %s, registered with CityCut" % [shafts, pr])
		check(ht.doors.size() >= 10 and ht.containers >= 12, "Meridiano: %d doors (stair + offices on the furnished floors, the roof door), %d containers" % [ht.doors.size(), ht.containers])
	await tree.physics_frame
	await tree.physics_frame
	var space := root3d.get_world_3d().direct_space_state
	if ht != null:
		var stair_ok := true
		var detail: Array = []
		for k in [1, 3, 8, 23]:
			var sw := HeroTower.stairwell(ht.size)
			var y0 := ht.floor_y(k)
			var y1 := ht.floor_y(k + 1)
			# flight A half way up, the half landing, flight B half way up (rays down from 0.8 m over each)
			var pts := [[Vector3(float(sw["x0"]) + 0.75, 0, float(sw["z1"]) - HeroTower.LANDING - HeroTower.RUN * 0.5), y0 + (y1 - y0) * 0.25],
				[Vector3((float(sw["x0"]) + float(sw["x1"])) * 0.5, 0, float(sw["z0"]) + HeroTower.LANDING * 0.5), y0 + (y1 - y0) * 0.5],
				[Vector3(float(sw["x1"]) - 0.75, 0, float(sw["z0"]) + HeroTower.LANDING + HeroTower.RUN * 0.5), y0 + (y1 - y0) * 0.75]]
			for pp in pts:
				var lp: Vector3 = pp[0]
				var want := float(pp[1])
				var wp := ht.global_transform * Vector3(lp.x, 0.0, lp.z)
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(wp.x, want + 0.8, wp.z), Vector3(wp.x, want - 1.5, wp.z)))
				var hy := float((hit.get("position", Vector3(0, -999, 0)) as Vector3).y)
				if absf(hy - want) > 0.35:
					stair_ok = false
					detail.append("floor %d: %.2f vs %.2f" % [k, hy, want])
		check(stair_ok, "Meridiano: the stair's ramps and half landings sit where a walker needs them on floors 1, 3, 8, 23 %s" % [detail])
		var roof_y := ht.floor_y(ht.floors)
		var rp := ht.global_transform * Vector3(-10.0, 0.0, 5.0)
		var rh := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(rp.x, roof_y + 5.0, rp.z), Vector3(rp.x, roof_y - 5.0, rp.z)))
		var sw2 := HeroTower.stairwell(ht.size)
		var gap := ht.global_transform * Vector3(float(sw2["x0"]) + 0.7, 0.0, float(sw2["z1"]) + 0.2)
		var gap_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(gap.x, roof_y + 1.2, gap.z) + ht.global_transform.basis.z * 1.5,
			Vector3(gap.x, roof_y + 1.2, gap.z) - ht.global_transform.basis.z * 1.5))
		check(not rh.is_empty() and absf(float((rh["position"] as Vector3).y) - roof_y) < 0.3 and (gap_hit.is_empty() or (gap_hit["collider"] as Node) is KitDoor),
			"Meridiano: the roof is walkable at %.1f m and the stair house door is the only thing in its doorway" % roof_y)
		# NavFloorTile + stair links: a path from floor 1 to floor 3 on a map of its own
		var map := NavigationServer3D.map_create()
		NavigationServer3D.map_set_cell_size(map, 0.25)
		NavigationServer3D.map_set_cell_height(map, NavBaker.CELL_HEIGHT)
		NavigationServer3D.map_set_use_edge_connections(map, false)
		NavigationServer3D.map_set_active(map, true)
		var tiles: Array = []
		var bake_ms := 0
		var polys := 0
		for k in [1, 2, 3]:
			var t := NavFloorTile.make(ht, k, 0.25)
			t.run()
			bake_ms = maxi(bake_ms, t.usec / 1000)
			polys += t.polygon_count()
			t.region = NavigationServer3D.region_create()
			NavigationServer3D.region_set_map(t.region, map)
			NavigationServer3D.region_set_navigation_mesh(t.region, t.nm)
			tiles.append(t)
		var lks: Array = []
		for k in [1, 2]:
			for pair in CityNav.stair_links(ht, k):
				var l := NavigationServer3D.link_create()
				NavigationServer3D.link_set_map(l, map)
				NavigationServer3D.link_set_bidirectional(l, true)
				NavigationServer3D.link_set_start_position(l, pair[0])
				NavigationServer3D.link_set_end_position(l, pair[1])
				lks.append(l)
		lks.append(_door_link(map, ht, 1))
		var w := 0
		while NavigationServer3D.map_get_iteration_id(map) < 2 and w < 300:
			await tree.physics_frame
			w += 1
		for i in 4:
			await tree.physics_frame
		# the central office area (the wings behind the 1 m office doors are their own rooms)
		var from := ht.global_transform * Vector3(-7.0, 0.0, 6.0)
		from.y = ht.floor_y(1)
		var to := ht.global_transform * Vector3(7.0, 0.0, 6.0)
		to.y = ht.floor_y(3)
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		var top_y := -INF
		for pnt in path:
			top_y = maxf(top_y, pnt.y)
		var end_ok := not path.is_empty() and path[path.size() - 1].distance_to(to) < 1.5
		check(polys > 0 and end_ok and top_y > ht.floor_y(3) - 0.5, "NavFloorTile: floors 1–3 baked (%d polygons, ≤ %d ms each), a path from floor 1 to floor 3 through the stair links (%d points, ends %.1f m from the goal)" % [
			polys, bake_ms, path.size(), path[path.size() - 1].distance_to(to) if not path.is_empty() else -1.0])
		for l in lks:
			NavigationServer3D.free_rid(l)
		for t in tiles:
			NavigationServer3D.free_rid((t as NavFloorTile).region)
		NavigationServer3D.free_rid(map)
		# vertical interest filter: a floor is indoors, the street and the roof slab level are not below 1.5 m
		var f5 := ht.global_transform * Vector3(-12.0, 0.0, 6.0)
		f5.y = ht.floor_y(5)
		var street := ht.global_transform * Vector3(-12.0, 0.0, ht.size.y * 0.5 + 6.0)
		street.y = hf.height_at(street.x, street.z)
		var lobby := ht.global_transform * Vector3(-12.0, 0.0, 6.0)
		lobby.y = ht.floor_y(0)
		check(CityLots.indoors_at(f5, hf) and not CityLots.indoors_at(street, hf) and not CityLots.indoors_at(lobby, hf),
			"vertical filter: floor 5 of a tower is «indoors», its lobby and the street are not (ZombieNet sends those regardless of height)")
		# floor population (L3 per floor): deterministic, off the core
		var rec := ht.rec
		var tot := 0
		for k in range(1, ht.floors):
			tot += CityPopulation.residents(SEED, rec, k)
		var pts3 := CityPopulation.floor_points(rec, 3, 5, SEED)
		check(tot > 20 and tot == _residents_total(rec) and pts3.size() == 5 and CityPopulation.residents(SEED, rec, ht.floors - 1) == 0,
			"floor population: %d residents over the floors of the Meridiano (0 on the top floor), 5 standing points off the core on floor 3" % tot)
	# ---- the Control del Puerto: huts (enterable, military loot), barriers and lamps
	var ctrl_huts := 0
	var ctrl_loot := 0
	for c in chunks:
		if c.city == null:
			continue
		for b in c.city.buildings:
			if str(b.get_meta("family", "")) == "caseta":
				ctrl_huts += 1
				ctrl_loot += b.find_children("*", "LootContainer", true, false).size()
	check(ctrl_huts == 3 and ctrl_loot >= 3, "Control del Puerto: %d huts with %d military containers, barriers, tents and trucks" % [ctrl_huts, ctrl_loot])
	# ---- teardown: CityCut empty, doors / containers out of the registry
	for c in chunks:
		c.begin_teardown()
		while not c.teardown_step(100000):
			pass
		root3d.remove_child(c)
		c.free()
	check(CityCut.buildings().is_empty() and lights.lamps.is_empty(), "chunk teardown: CityCut registry and CityLights lamps emptied")
	# ---- server path: the Meridiano chunk without visuals (colliders, doors, containers; no meshes)
	var sk := WorldConst.key(WorldConst.chunk_of(2812.0), WorldConst.chunk_of(-446.0))
	var sj := ChunkJob.new()
	sj.cx = WorldConst.key_cx(sk)
	sj.cz = WorldConst.key_cz(sk)
	sj.key = sk
	sj.hf = hf
	sj.visual = false
	sj.run()
	var sc := WorldChunk.new()
	sc.setup(sj, false, true)
	root3d.add_child(sc)
	sc.build_all()
	var s_meshes := 0
	var s_cols := 0
	var s_doors := 0
	if sc.city != null:
		for gi in sc.city.find_children("*", "GeometryInstance3D", true, false):
			if (gi as GeometryInstance3D).visible and not String(gi.name).begins_with("Door_"):
				s_meshes += 1
		s_cols = sc.city.find_children("*", "CollisionShape3D", true, false).size()
		s_doors = sc.city.find_children("*", "KitDoor", true, false).size()
	check(sc.city != null and s_cols > 400 and s_doors >= 10 and CityCut.buildings().is_empty(),
		"server path: the Meridiano chunk has %d colliders and %d doors (the same wids), %d visible meshes (only loot models), nothing in CityCut" % [s_cols, s_doors, s_meshes])
	sc.begin_teardown()
	while not sc.teardown_step(100000):
		pass
	root3d.remove_child(sc)
	sc.free()
	# ---- dressing digest (the determinism gate compares it between two processes) and silhouettes / statues
	var dg := CityLots.lot_digest(SEED, 50)
	check(dg.ends_with("lots=50") and dg != CityLots.lot_digest(SEED + 1, 50) and dg == CityLots.lot_digest(SEED, 50),
		"dressing of 50 enterable lots: %s… (another world seed changes it)" % dg.substr(0, 16))
	var sil := CitySilhouettes.new()
	tree.root.add_child(sil)
	sil.build_now(hf)
	check(sil.is_built and int(sil.stats["boxes"]) >= 2500 and int(sil.stats["tris"]) < 400000,
		"district silhouettes from the real lots: %d boxes, %d triangles, %d meshes (%.0f ms)" % [int(sil.stats["boxes"]), int(sil.stats["tris"]), int(sil.stats["meshes"]), float(sil.stats["build_ms"])])
	sil.queue_free()
	var fs := FrozenStatues.new()
	tree.root.add_child(fs)
	await fs.bake()
	var fs_tris := 0
	for m in FrozenStatues._meshes:
		if m != null:
			for si in (m as ArrayMesh).get_surface_count():
				fs_tris += ((m as ArrayMesh).surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	check(FrozenStatues._meshes.size() == FrozenStatues.POSES and fs_tris > 500, "frozen statues: %d baked poses (%d triangles) for the MultiMesh" % [FrozenStatues._meshes.size(), fs_tris])
	fs.queue_free()
	var dig := "file %s\ncontent %s\nitems %s\ndressing %s\n" % [CityLots.file_hash(), CityLots.content_hash(), CityLots.items_digest(hf), dg]
	if digest_out != "":
		var f := FileAccess.open(digest_out, FileAccess.WRITE)
		f.store_string(dig)
		f.close()
	print("  digest: %s" % dig.replace("\n", " | "))
	lights.queue_free()
	cut.queue_free()
	root3d.queue_free()
	Locations.hf_override = null
	await tree.process_frame
	print("== %d checks, %s (%d ms)" % [_checks, "ALL PASSED" if not _failed else "FAILED", Time.get_ticks_msec() - t0])
	tree.quit(1 if _failed else 0)


func _door_link(map: RID, ht: HeroTower, k: int) -> RID:
	var pair := CityNav.door_link(ht, k)
	var l := NavigationServer3D.link_create()
	NavigationServer3D.link_set_map(l, map)
	NavigationServer3D.link_set_bidirectional(l, true)
	NavigationServer3D.link_set_start_position(l, pair[0])
	NavigationServer3D.link_set_end_position(l, pair[1])
	return l


func _residents_total(rec: Dictionary) -> int:
	var t := 0
	for k in range(1, int(rec["floors"])):
		t += CityPopulation.residents(SEED, rec, k)
	return t


## Size of the largest connected part of the street graph (union-find).
func _largest_component(gr: Dictionary) -> int:
	var n := (gr.get("nodes", []) as Array).size()
	var parent: Array = []   # an Array (a reference): the lambda below sees the unions made after its creation
	parent.resize(n)
	for i in n:
		parent[i] = i
	var find := func(x: int) -> int:
		var r := x
		while int(parent[r]) != r:
			r = int(parent[r])
		return r
	for e in gr.get("edges", []):
		var a: int = find.call(int(e[0]))
		var b: int = find.call(int(e[1]))
		if a != b:
			parent[a] = b
	var counts := {}
	for i in n:
		var r: int = find.call(i)
		counts[r] = int(counts.get(r, 0)) + 1
	var best := 0
	for k in counts:
		best = maxi(best, int(counts[k]))
	return best
