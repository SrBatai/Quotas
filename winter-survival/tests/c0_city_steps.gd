extends RefCounted
## Body of tests/c0_city.gd (loaded at runtime, after the autoloads exist).

const SEED := 1337

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


func run(p_tree: SceneTree) -> void:
	tree = p_tree
	await tree.process_frame
	var digest_out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--digest="):
			digest_out = a.substr(9)
	var t0 := Time.get_ticks_msec()
	print("== C0 city (Escaparate de Altavega)")
	ScatterCatalog.load_manifests()
	var macro := MacroMap.load_default()
	var hf := HeightFunction.create(SEED, macro)
	# ---- lot file
	var ok := CityLots.load_default()
	check(ok and CityLots.problems().is_empty(), "lot file %s loads and validates %s" % [CityLots.PATH, CityLots.problems()])
	# C1 replaced the lot file v0 (city_version 1, the generated districts): the C0 checks below describe v0 (one
	# superblock, 4–6 towers, every city chunk streamed); tests/c1_city.gd gates the city now.
	if CityLots.city_version() != 0:
		print("  skip the C0 checks: the lot file is city_version %d (C1) — see tests/c1_city.gd" % CityLots.city_version())
		print("== %d checks, %s (%d ms)" % [_checks, "ALL PASSED" if not _failed else "FAILED", Time.get_ticks_msec() - t0])
		tree.quit(0 if not _failed else 1)
		return
	check(CityLots.city_version() == 0 and WorldConst.CITY_VERSION == 0, "city_version 0 = WorldConst.CITY_VERSION (world_meta.city_version)")
	check(CityLots.file_hash().length() == 64 and CityLots.content_hash().length() == 64,
		"hashes: file %s…, content %s…" % [CityLots.file_hash().substr(0, 12), CityLots.content_hash().substr(0, 12)])
	var d := CityLots.data()
	var block := CityLots.rect_of(d["block"]["rect"])
	check(PoiRegistry.region_at(block.get_center().x, block.get_center().y) == "ALTAVEGA — LAS TORRES",
		"superblock LT-01 %s is in ALTAVEGA — LAS TORRES (doc 09 §4.3: (2 688, −384), 384 × 640 m)" % block)
	check(is_equal_approx(block.size.x, 112.0) and is_equal_approx(block.size.y, 80.0), "superblock is 112 × 80 m (doc 09 §4.5 Las Torres)")
	check(absf(block.end.y - (-384.0 - 22.0)) < 0.01, "the superblock fronts the Gran Vía (axis z −384, 30 m + sidewalks): south edge %.0f" % block.end.y)
	var towers := CityLots.towers()
	check(towers.size() >= 4 and towers.size() <= 6, "%d towers (4–6)" % towers.size())
	var flat := true
	var water := false
	for p in CityLots.podiums():
		var c := CityLots.v2(p["pos"])
		var s := CityLots.v2(p["size"]) * 0.5
		var hs: Array[float] = []
		for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2.ZERO]:
			var pt: Vector2 = c + Vector2(q.x * s.x, q.y * s.y)
			hs.append(hf.height_at(pt.x, pt.y))
			water = water or hf.is_w1_water(pt.x, pt.y)
			if q != Vector2.ZERO and not block.grow(0.01).has_point(pt):
				check(false, "podium %d corner %s inside the block" % [int(p["id"]), pt])
		flat = flat and (hs.max() - hs.min()) < 1.5
	check(flat and not water, "podiums on flat ground (< 1.5 m over their corners), none on the río Albo ice")
	# ---- tower assembler (A1 art) and the city contract
	var floors_ok := true
	var contract: Array = []
	var heights: Array = []
	for t in towers:
		var item := {"id": int(t["id"]), "family": str(t["family"]), "groups": int(t["groups"]), "wid": 1, "generator": false}
		var root := TowerAssembler.build(item)
		var probs := CityBuilding.validate(root, true)
		if not probs.is_empty():
			contract.append("%d: %s" % [int(t["id"]), probs])
		var fl := int(root.get_meta("floors"))
		floors_ok = floors_ok and fl >= 12 and fl <= 45 and fl == CityLots.tower_floors(t)
		var top := 0.0
		var proxy_top := 0.0
		var shafts := 0
		for c in root.get_children():
			var mi := c as MeshInstance3D
			if mi == null:
				continue
			var e := mi.mesh.get_aabb().end.y
			if String(c.name) == "ShadowProxy":
				proxy_top = e
			else:
				top = maxf(top, e)
			if String(c.name).begins_with("Shaft_"):
				shafts += 1
		var a := TowerAssembler.assembly(str(t["family"]), int(t["groups"]))
		var expect := float(a["height"])
		heights.append("%d:%s %dfl %.1fm (%d groups%s)" % [int(t["id"]), t["family"], fl, top, shafts, "" if bool(a["art"]) else ", procedural"])
		check(absf(top - expect) < 0.6 and proxy_top >= float(a["roof_z"]) - 0.6, "tower %d (%s, %d floors): pieces reach %.1f m (expected %.1f), proxy %.1f m" % [
			int(t["id"]), t["family"], fl, top, expect, proxy_top])
		root.free()
	check(contract.is_empty(), "assembled towers pass CityBuilding.validate (Base / Shaft_<n> with floor_from / Roof / ShadowProxy, no y offsets) %s" % [contract])
	check(floors_ok, "tower floors 12–45 (doc 09 Las Torres): %s" % [heights])
	check(TowerAssembler.has_art("towers/tower_a") and int(TowerAssembler.stats["fallback"]) == 0, "A1 CC0 towers used (no procedural fallback on desktop)")
	# procedural fallback (the Web build has no city .glb)
	Assets.force_placeholders = true
	TowerAssembler.clear_cache()
	var fb := TowerAssembler.build({"id": 99, "family": "tower_b", "groups": 6, "wid": 1})
	check(CityBuilding.validate(fb, true).is_empty() and int(fb.get_meta("floors")) == 32, "procedural tower fallback (Web) validates, 32 floors")
	fb.free()
	Assets.force_placeholders = false
	TowerAssembler.clear_cache()
	# podium buildings
	var pod_probs: Array = []
	for p in CityLots.podiums():
		var e := {"id": int(p["id"]), "size": CityLots.v2(p["size"]), "floors": int(p["floors"]), "ground_h": CityLots.cm(p["ground_h"]),
			"floor_h": CityLots.cm(p["floor_h"]), "style": str(p.get("style", "concrete")), "stair": p.get("stair", {})}
		var pc := CityChunk.podium_pieces(e)
		var root := Node3D.new()
		for n in ["Base", "Roof", "ShadowProxy"]:
			var mi := MeshInstance3D.new()
			mi.name = n
			mi.mesh = pc[n]
			root.add_child(mi)
		root.set_meta("floor_h", CityLots.cm(p["floor_h"]))
		root.set_meta("ground_h", CityLots.cm(p["ground_h"]))
		root.set_meta("floors", int(p["floors"]))
		var pr := CityBuilding.validate(root, true)
		if not pr.is_empty():
			pod_probs.append([int(p["id"]), pr])
		root.free()
	check(pod_probs.is_empty(), "non-enterable podiums pass the city contract %s" % [pod_probs])
	# ---- chunk items: layout + seeded jam, heights
	var keys := CityLots.chunk_keys()
	var n_items := 0
	var jam := 0
	var kinds := {}
	var jam_items: Array = []
	for k in keys:
		var items := CityLots.chunk_items(hf, WorldConst.key_cx(k), WorldConst.key_cz(k), func(x: float, z: float) -> float: return hf.height_at(x, z))
		n_items += items.size()
		for e in items:
			kinds[int(e["k"])] = int(kinds.get(int(e["k"]), 0)) + 1
			if bool(e.get("jam", false)):
				jam += 1
				jam_items.append(e)
	check(keys.size() >= 8 and n_items > 100, "%d city chunks, %d items (kinds %s)" % [keys.size(), n_items, kinds])
	var on_road := true
	var overlap := 0
	for i in jam_items.size():
		var e: Dictionary = jam_items[i]
		var p: Vector2 = e["pos"]
		on_road = on_road and absf(p.y - (-384.0)) <= 12.0
		for j in range(i + 1, jam_items.size()):
			if (jam_items[j]["pos"] as Vector2).distance_to(p) < 1.6:
				overlap += 1
	check(jam >= 30 and jam <= 140 and on_road and overlap == 0, "Gran Vía jam: %d A1 cars on the carriageway, %d overlapping pairs" % [jam, overlap])
	var jam_b := CityLots.jam_items(SEED + 1, Rect2(2200, -420, 700, 80))
	check(jam_b.size() > 0 and CityLots.items_digest(hf) == CityLots.items_digest(hf), "jam dressing is seeded (another world seed: %d cars) and the item digest is stable" % jam_b.size())
	# ---- bridge
	var br := CityLots.bridge()
	var ends := CityLots.bridge_ends(hf)
	var mid := CityLots.deck_profile(2432.0, ends)
	check(absf(mid - CityLots.cm(br["deck_y"])) < 0.01 and absf(CityLots.deck_profile(CityLots.cm(br["x_from"]), ends) - hf.height_at(CityLots.cm(br["x_from"]), -384.0)) < 0.01
		and absf(CityLots.deck_profile(CityLots.cm(br["x_to"]), ends) - hf.height_at(CityLots.cm(br["x_to"]), -384.0)) < 0.01,
		"Puente de Hierro (provisional): deck %.2f m over the ice (−6), ramps meet the terrain at both ends (%.2f / %.2f)" % [mid, ends.x, ends.y])
	# ---- streaming: ChunkJob (worker) → WorldChunk steps → city nodes; teardown
	var warm_us := CityChunk.warm()
	print("  info city warm-up (World.configure on a visual client): %d ms — towers %d variants, podiums %d, MultiMesh meshes %d" % [
		warm_us / 1000, int(TowerAssembler.stats["variants"]), int(CityChunk.stats["podiums"]), int(CityChunk.stats["group_meshes"])])
	var root3d := Node3D.new()
	root3d.name = "C0Chunks"
	tree.root.add_child(root3d)
	var lights := CityLights.new()
	lights.name = "CityLights"
	tree.root.add_child(lights)
	var cut := CityCut.new()
	tree.root.add_child(cut)
	var jobs: Array[ChunkJob] = []
	var ids: Array[int] = []
	for k in keys:
		var j := ChunkJob.new()
		j.cx = WorldConst.key_cx(k)
		j.cz = WorldConst.key_cz(k)
		j.key = k
		j.hf = hf
		j.visual = true
		jobs.append(j)
		ids.append(WorkerThreadPool.add_task(j.run, false, "c0 job"))
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(id)
	var gen: Array = []
	for j in jobs:
		gen.append("%d,%d:%d" % [j.cx, j.cz, j.usec / 1000])
	print("  info city chunk jobs (ms, 2 worker threads): %s" % [gen])
	var chunks: Array[WorldChunk] = []
	var step_max := {}
	var cleared := 0
	var painted_road := 0
	var painted_walk := 0
	for j in jobs:
		for e in j.entries:
			if CityLots.is_cleared(float(e["x"]), float(e["z"])):
				cleared += 1
		for s in j.surface:
			if (s & 255) == 230:
				painted_road += 1
			elif ((s >> 16) & 255) == 204:
				painted_walk += 1
		var c := WorldChunk.new()
		c.setup(j, true, true)
		root3d.add_child(c)
		while c.state != WorldChunk.State.LOADED:
			var kind := c.step_kind()
			var q0 := SchedProbe.wait_ns() if SchedProbe.available() else 0
			var s0 := Time.get_ticks_usec()
			c.step()
			# work = wall − the main thread's run-queue wait (W1: preemption by other processes is not our cost)
			var us := Time.get_ticks_usec() - s0
			if SchedProbe.available():
				us = maxi(us - int((SchedProbe.wait_ns() - q0) / 1000), 0)
			if kind.begins_with("_step_city"):
				step_max[kind] = maxi(int(step_max.get(kind, 0)), us)
		chunks.append(c)
	check(cleared == 0 and painted_road > 500 and painted_walk > 500, "city chunks: no scatter in the streets / block / bridge approaches, %d road and %d sidewalk samples painted" % [painted_road, painted_walk])
	var n_buildings := 0
	var n_hlod := 0
	var n_cols := 0
	for c in chunks:
		if c.city == null:
			continue
		n_buildings += c.city.buildings.size()
		if c.city.hlod != null:
			n_hlod += 1
		for b in c.city.find_children("*", "CollisionShape3D", true, false):
			n_cols += 1
	var mm_inst := 0
	var model_items := 0
	for c in chunks:
		if c.city == null:
			continue
		for n in c.city.find_children("*", "MultiMeshInstance3D", true, false):
			mm_inst += (n as MultiMeshInstance3D).multimesh.instance_count
		for e in c.data.city:
			if int(e["k"]) == CityLots.Kind.VEHICLE or int(e["k"]) == CityLots.Kind.PROP:
				model_items += 1
	check(mm_inst == model_items and mm_inst > 100, "cars and props drawn as MultiMesh instances per chunk × model: %d instances for %d items" % [mm_inst, model_items])
	var registered := CityCut.buildings().size()
	var expect_b := CityLots.podiums().size() + towers.size()
	check(n_buildings == expect_b and registered == expect_b, "%d buildings streamed, %d registered with CityCut (CityBuilding.attach from the chunk)" % [n_buildings, registered])
	check(n_hlod >= 1, "CityHlod.build_for on the chunks with buildings (%d HLOD meshes)" % n_hlod)
	check(n_cols > 60 and lights.lamps.size() > 30, "%d colliders (buildings, stair, parapets, bridge, cars, props), %d street lamps in CityLights" % [n_cols, lights.lamps.size()])
	var worst := 0
	for k in step_max:
		worst = maxi(worst, int(step_max[k]))
	print("  info city step max µs of work (wall − run-queue wait) by kind (headless, warm caches): %s" % [step_max])
	check(worst < 4000, "no single city step above 4 ms headless (max %d µs; the 2 ms/frame streaming budget is gated by perf_walk --cpu)" % worst)
	# stair + parapet: a ray down on the landing hits the stair, a ray down on the roof hits the podium
	await tree.physics_frame
	await tree.physics_frame
	var space := root3d.get_world_3d().direct_space_state
	var mir: Dictionary = CityLots.miradores()[0]
	var mp := CityLots.v2(mir["pos"])
	var roof_y := CityLots.podium_base(hf, int(mir["on"])) + CityLots.podium_roof(CityLots.podium(int(mir["on"])))
	var q := PhysicsRayQueryParameters3D.create(Vector3(mp.x, roof_y + 20.0, mp.y), Vector3(mp.x, roof_y - 20.0, mp.y))
	var hit := space.intersect_ray(q)
	check(not hit.is_empty() and absf(float((hit["position"] as Vector3).y) - roof_y) < 0.05, "mirador point stands on the podium roof (%.2f m, hit %s)" % [roof_y, hit.get("position")])
	var pod := CityLots.podium(int(mir["on"]))
	var pc2 := CityLots.v2(pod["pos"])
	var ps := CityLots.v2(pod["size"])
	var st: Dictionary = pod["stair"]
	var sx := pc2.x - ps.x * 0.5 - CityLots.cm(st["width"]) * 0.5
	var bottom_z := pc2.y + CityLots.cm(st["bottom"])
	var landing_z := pc2.y + CityLots.cm(st["top"]) - 1.5
	var mid_z := (bottom_z + pc2.y + CityLots.cm(st["top"]) - CityLots.LANDING) * 0.5
	var hl := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(sx, roof_y + 20.0, landing_z), Vector3(sx, roof_y - 30.0, landing_z)))
	var hm := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(sx, roof_y + 20.0, mid_z), Vector3(sx, roof_y - 30.0, mid_z)))
	var base_y := CityLots.podium_base(hf, int(mir["on"]))
	check(not hl.is_empty() and absf(float((hl["position"] as Vector3).y) - roof_y) < 0.2 and not hm.is_empty()
		and absf(float((hm["position"] as Vector3).y) - (base_y + (roof_y - base_y) * 0.5)) < 0.8,
		"exterior stair to the mirador: landing at roof level, ramp half way up (%s, %s)" % [hl.get("position"), hm.get("position")])
	# ---- teardown: buildings leave CityCut, lamps leave CityLights
	for c in chunks:
		c.begin_teardown()
		while not c.teardown_step(100000):
			pass
		root3d.remove_child(c)
		c.free()
	check(CityCut.buildings().is_empty() and lights.lamps.is_empty(), "chunk teardown: CityCut registry and CityLights lamps emptied")
	# ---- dedicated server path: the same chunk, no visuals — building roots + colliders only
	var sk := WorldConst.key(WorldConst.chunk_of(2708.0), WorldConst.chunk_of(-426.0))
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
	var s_meshes := sc.city.find_children("*", "GeometryInstance3D", true, false).size() if sc.city != null else -1
	var s_cols := sc.city.find_children("*", "CollisionShape3D", true, false).size() if sc.city != null else 0
	check(sc.city != null and s_meshes == 0 and s_cols > 10 and CityCut.buildings().is_empty() and sj.city_plan["groups"].is_empty(),
		"server path (no visuals): chunk %d,%d has %d buildings as bare roots with %d colliders, 0 meshes, nothing in CityCut" % [sj.cx, sj.cz,
			sc.city.buildings.size() if sc.city != null else 0, s_cols])
	sc.begin_teardown()
	while not sc.teardown_step(100000):
		pass
	root3d.remove_child(sc)
	sc.free()
	# ---- the Web build has no city .glb: the same chunk builds from the procedural stand-ins
	Assets.force_placeholders = true
	TowerAssembler.clear_cache()
	CityChunk.clear_cache()
	var wk := WorldConst.key(WorldConst.chunk_of(2708.0), WorldConst.chunk_of(-426.0))
	var wj := ChunkJob.new()
	wj.cx = WorldConst.key_cx(wk)
	wj.cz = WorldConst.key_cz(wk)
	wj.key = wk
	wj.hf = hf
	wj.visual = true
	wj.run()
	var wc := WorldChunk.new()
	wc.setup(wj, true, true)
	root3d.add_child(wc)
	wc.build_all()
	var wb := wc.city.buildings.size() if wc.city != null else 0
	var wmm := 0
	for n in wc.city.find_children("*", "MultiMeshInstance3D", true, false) if wc.city != null else []:
		wmm += (n as MultiMeshInstance3D).multimesh.instance_count
	var wprobs := 0
	for b in wc.city.buildings if wc.city != null else []:
		wprobs += CityBuilding.validate(b, true).size()
	check(wb > 0 and wmm > 0 and wprobs == 0 and int(TowerAssembler.stats["fallback"]) > 0,
		"without city art (Web): chunk %d,%d builds %d procedural buildings (contract ok) and %d stand-in instances" % [wj.cx, wj.cz, wb, wmm])
	wc.begin_teardown()
	while not wc.teardown_step(100000):
		pass
	root3d.remove_child(wc)
	wc.free()
	Assets.force_placeholders = false
	TowerAssembler.clear_cache()
	CityChunk.clear_cache()
	# ---- silhouettes v0
	var sil := CitySilhouettes.new()
	tree.root.add_child(sil)
	sil.build_now(hf)
	var sst := sil.stats
	check(sil.is_built and int(sst["meshes"]) >= 7 and int(sst["tris"]) > 20000 and int(sst["tris"]) < 200000,
		"district silhouettes v0: %d meshes (1–2 draw calls each), %d triangles, %d boxes, built in %.0f ms" % [int(sst["meshes"]), int(sst["tris"]), int(sst["boxes"]), float(sst["build_ms"])])
	sil.queue_free()
	# ---- digest (the determinism gate compares it between two processes)
	var dig := "file %s\ncontent %s\nitems %s\n" % [CityLots.file_hash(), CityLots.content_hash(), CityLots.items_digest(hf)]
	if digest_out != "":
		var f := FileAccess.open(digest_out, FileAccess.WRITE)
		f.store_string(dig)
		f.close()
	print("  digest: %s" % dig.replace("\n", " | "))
	lights.queue_free()
	cut.queue_free()
	root3d.queue_free()
	await tree.process_frame
	print("== %d checks, %s (%d ms)" % [_checks, "ALL PASSED" if not _failed else "FAILED", Time.get_ticks_msec() - t0])
	tree.quit(1 if _failed else 0)
