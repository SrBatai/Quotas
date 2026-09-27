extends RefCounted
## Body of tests/determinism.gd (loaded at runtime, after the autoloads exist).

const SEED := 1337
## W1: 60 chunks across the four quadrants of the 6 km world (≥ 8 per quadrant).
const N_CHUNKS := 60
const MIN_PER_QUADRANT := 8

var tree: SceneTree


## 60 chunks that cover every generator branch: the clearing (legacy scatter + stamps), the lake, the N‑140 and
## secondary roads, the border mountains, POI pads, and a hash-picked spread of forest / fields / villages; W1: the
## Carretera del Puerto, the city districts, the río Albo and dársena, the embalse, the A‑14, the reserved pads, the
## tunnel portals, the ski slopes, the ibón and the far corner, then a hash-picked spread per quadrant.
static func chunk_list() -> Array[int]:
	var keys: Array[int] = []
	var add := func(x: float, z: float) -> void:
		var k := WorldConst.key(WorldConst.chunk_of(x), WorldConst.chunk_of(z))
		if not keys.has(k) and keys.size() < N_CHUNKS:
			keys.append(k)
	for k in WorldConst.ring_keys(24, 24, 1):
		add.call(WorldConst.chunk_center(WorldConst.key_cx(k), WorldConst.key_cz(k)).x, WorldConst.chunk_center(WorldConst.key_cx(k), WorldConst.key_cz(k)).z)
	for p in [Vector2(-760, 380), Vector2(-640, 500), Vector2(-900, 450), Vector2(-470, 520), Vector2(646, -240),
			Vector2(652, 128), Vector2(640, 700), Vector2(640, -1152), Vector2(-300, 250), Vector2(-560, 44),
			Vector2(1400, 0), Vector2(-1450, -1450), Vector2(1450, 1450), Vector2(-1152, -128), Vector2(-512, -300),
			Vector2(256, 896), Vector2(176, -512), Vector2(-704, -768), Vector2(960, 768), Vector2(150, 60)]:
		add.call(p.x, p.y)
	for p in [Vector2(1536, -384), Vector2(2432, -384), Vector2(2688, -384), Vector2(2432, 1216), Vector2(4096, 1280),
			Vector2(3712, -256), Vector2(3264, 3520), Vector2(640, 1672), Vector2(-640, 2176), Vector2(-1024, 3072),
			Vector2(2432, -1500), Vector2(4390, 4390)]:
		add.call(p.x, p.y)
	var i := 0
	var span := WorldConst.WALL_MAX - WorldConst.WALL_MIN
	while keys.size() < N_CHUNKS:
		var per := [0, 0, 0, 0]
		for k in keys:
			var c := WorldConst.chunk_center(WorldConst.key_cx(k), WorldConst.key_cz(k))
			per[WorldConst.quadrant(c.x, c.z)] += 1
		var q := per.find(per.min())
		var h := WorldConst.hash64(SEED, 999, i)
		var x := WorldConst.WALL_MIN + float(h % 100000) / 100000.0 * span
		var z := WorldConst.WALL_MIN + float((h >> 20) % 100000) / 100000.0 * span
		i += 1
		if per[q] < MIN_PER_QUADRANT and WorldConst.quadrant(x, z) != q:
			continue
		add.call(x, z)
	return keys


func run(p_tree: SceneTree) -> void:
	tree = p_tree
	await tree.process_frame
	var role := "server"
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
		elif a.begins_with("--out="):
			out = a.substr(6)
	var t0 := Time.get_ticks_msec()
	ScatterCatalog.load_manifests()
	var macro := MacroMap.load_default()
	var hf := HeightFunction.create(SEED, macro)
	var clearing := ScatterGen.clearing_entries(SEED)
	var keys := chunk_list()
	var jobs: Array[ChunkJob] = []
	for k in keys:
		var j := ChunkJob.new()
		j.cx = WorldConst.key_cx(k)
		j.cz = WorldConst.key_cz(k)
		j.key = k
		j.hf = hf
		j.clearing = clearing
		j.visual = role == "client"
		jobs.append(j)
	if role == "client":
		var ids: Array[int] = []
		for j in jobs:
			ids.append(WorkerThreadPool.add_task(j.run, false, "det"))
		for id in ids:
			WorkerThreadPool.wait_for_task_completion(id)
	else:
		for j in jobs:
			j.run()
	var lines: Array[String] = []
	var total := HashingContext.new()
	total.start(HashingContext.HASH_SHA256)
	var entries_total := 0
	for j in jobs:
		var hc := HashingContext.new()
		hc.start(HashingContext.HASH_SHA256)
		var hq := PackedInt32Array()
		hq.resize(j.heights.size())
		for i in j.heights.size():
			hq[i] = int(round(j.heights[i] * 100.0))
		hc.update(hq.to_byte_array())
		hc.update(j.surface.to_byte_array())
		var ent := PackedInt64Array()
		for e in j.entries + j.nodes:
			ent.append_array(PackedInt64Array([int(e["v"]), int(e["node"]), int(round(float(e["x"]) * 1000.0)), int(round(float(e["z"]) * 1000.0)),
				int(round(float(e.get("y", 0.0)) * 100.0)), int(round(float(e["yaw"]) * 100000.0)), int(round(float(e["s"]) * 100000.0)), int(e["wid"])]))
		entries_total += j.entries.size() + j.nodes.size()
		if not ent.is_empty():
			hc.update(ent.to_byte_array())
		hc.update(j.region.to_utf8_buffer())
		var digest := hc.finish()
		total.update(digest)
		lines.append("chunk %d,%d %s entries=%d region=%s" % [j.cx, j.cz, digest.hex_encode().substr(0, 16), j.entries.size() + j.nodes.size(), j.region])
	# gameplay queries (main thread): height_at / surface_at at fixed points
	var hq2 := PackedInt32Array()
	for i in 300:
		var h := WorldConst.hash64(SEED, 777, i)
		var x := float(h % 300000) / 100.0 - 1500.0
		var z := float((h >> 20) % 300000) / 100.0 - 1500.0
		if i >= 200:   # W1: the rest of the 6 km world
			x = float(h % 587000) / 100.0 - 1450.0
			z = float((h >> 20) % 587000) / 100.0 - 1450.0
		hq2.append(int(round(hf.height_at(x, z) * 100.0)))
		var sc := hf.surface_at(x, z)
		hq2.append(sc.r8 | (sc.g8 << 8) | (sc.b8 << 16))
	var qh := HashingContext.new()
	qh.start(HashingContext.HASH_SHA256)
	qh.update(hq2.to_byte_array())
	var qd := qh.finish()
	total.update(qd)
	lines.append("height_at x300 %s" % qd.hex_encode().substr(0, 16))
	var per := [0, 0, 0, 0]
	for j in jobs:
		var c := WorldConst.chunk_center(j.cx, j.cz)
		per[WorldConst.quadrant(c.x, c.z)] += 1
	lines.append("quadrants NW %d NE %d SW %d SE %d" % per)
	if per.min() < MIN_PER_QUADRANT:
		print("FAIL: determinism chunk list has < %d chunks in a quadrant %s" % [MIN_PER_QUADRANT, per])
		tree.quit(1)
		return
	var tot := total.finish().hex_encode()
	lines.append("TOTAL %s chunks=%d entries=%d" % [tot, jobs.size(), entries_total])
	var text := "\n".join(lines) + "\n"
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	print("determinism role=%s: %d chunks, %d entries, total %s (%d ms, %s)" % [role, jobs.size(), entries_total, tot.substr(0, 16),
		Time.get_ticks_msec() - t0, "worker threads" if role == "client" else "main thread"])
	tree.quit(0)
