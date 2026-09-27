extends RefCounted
## Body of tests/valley_unchanged.gd (loaded at runtime, after the autoloads exist).
##
## Per chunk three SHA-256 digests (first 16 hex digits), computed from the server path of ChunkJob (no visuals):
##   h  the 65 × 65 heights, raw float32 bits (the valley must stay byte-identical, not just to the cm)
##   s  the surface mask (asphalt, ice, packed track, road lateral byte)
##   e  the scatter entries + node entries (variant, node kind, x/z to the mm, y to the cm, yaw, scale, wid)
## plus `hq` (heights quantized to the cm, as determinism.gd): on another CPU architecture only the raw bits may
## differ (< 1 mm, ARQ v2 §8.2); with VALLEY_TOLERANT=1 such chunks pass when `hq`, `s` and `e` match.
## The region name is not hashed: the old border ring legitimately becomes the new sierras (W1).

const SEED := 1337
const BASELINE := "res://tests/data/valley_prew1_hashes.json"
## |x|, |z| < VALLEY_LIMIT m at the chunk centre (chunks 7…41).
const VALLEY_LIMIT := 1152.0
## Closed list (C25 / W1 card): the Carretera del Puerto chunks, the only valley chunks W1 may change. The road
## leaves the N‑140 at the Gasolinera Norte (632, −392) and climbs east along row 9 of the macro map (z ≈ −384):
## its stamp (3.5 m half width + 7 m shoulders) and scatter clearance reach chunks 34…41 of row 18, and the pass
## cutting of the macro map (tools/gen_macro_map.gd PASS_*, from x = 960 m) the three chunks beside its last
## valley stretch. [cx, cz]
const PUERTO_CHUNKS := [[34, 18], [35, 18], [36, 18], [37, 18], [38, 18], [39, 18], [40, 18], [41, 18],
	[40, 17], [41, 17], [41, 19]]

var tree: SceneTree


static func valley_range() -> Vector2i:
	var lo := 999
	var hi := -1
	for c in WorldConst.WORLD_CHUNKS:
		if absf(WorldConst.chunk_center(c, WorldConst.CENTER_CHUNK).x) < VALLEY_LIMIT:
			lo = mini(lo, c)
			hi = maxi(hi, c)
	return Vector2i(lo, hi)


static func chunk_hashes(j: ChunkJob) -> Dictionary:
	var out := {}
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(j.heights.to_byte_array())
	out["h"] = hc.finish().hex_encode().substr(0, 16)
	var hq := PackedInt32Array()
	hq.resize(j.heights.size())
	for i in j.heights.size():
		hq[i] = int(round(j.heights[i] * 100.0))
	hc = HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(hq.to_byte_array())
	out["hq"] = hc.finish().hex_encode().substr(0, 16)
	hc = HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(j.surface.to_byte_array())
	out["s"] = hc.finish().hex_encode().substr(0, 16)
	var ent := PackedInt64Array()
	for e in j.entries + j.nodes:
		ent.append_array(PackedInt64Array([int(e["v"]), int(e["node"]), int(round(float(e["x"]) * 1000.0)), int(round(float(e["z"]) * 1000.0)),
			int(round(float(e.get("y", 0.0)) * 100.0)), int(round(float(e["yaw"]) * 100000.0)), int(round(float(e["s"]) * 100000.0)), int(e["wid"])]))
	hc = HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	if not ent.is_empty():
		hc.update(ent.to_byte_array())
	out["e"] = hc.finish().hex_encode().substr(0, 16)
	out["n"] = j.entries.size() + j.nodes.size()
	return out


func run(p_tree: SceneTree) -> void:
	tree = p_tree
	await tree.process_frame
	var write := OS.get_cmdline_user_args().has("--write")
	var tolerant := OS.get_environment("VALLEY_TOLERANT") == "1"
	var t0 := Time.get_ticks_msec()
	ScatterCatalog.load_manifests()
	var macro := MacroMap.load_default()
	var hf := HeightFunction.create(SEED, macro)
	var clearing := ScatterGen.clearing_entries(SEED)
	var r := valley_range()
	var jobs: Array[ChunkJob] = []
	for cz in range(r.x, r.y + 1):
		for cx in range(r.x, r.y + 1):
			var j := ChunkJob.new()
			j.cx = cx
			j.cz = cz
			j.key = WorldConst.key(cx, cz)
			j.hf = hf
			j.clearing = clearing
			j.visual = false
			jobs.append(j)
	var ids: Array[int] = []
	for j in jobs:
		ids.append(WorkerThreadPool.add_task(j.run, false, "valley"))
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(id)
	var got := {}
	for j in jobs:
		got["%d,%d" % [j.cx, j.cz]] = chunk_hashes(j)
	if write:
		var f := FileAccess.open(ProjectSettings.globalize_path(BASELINE), FileAccess.WRITE)
		if f == null:
			print("FAIL: cannot write %s" % BASELINE)
			tree.quit(1)
			return
		# one chunk per line (a small, diffable file)
		var lines: Array[String] = []
		for j in jobs:
			var k := "%d,%d" % [j.cx, j.cz]
			lines.append("\t\t\"%s\": %s" % [k, JSON.stringify(got[k], "", true)])
		f.store_string("{\n\t\"doc\": \"Pre-W1 valley hashes (tests/valley_unchanged.gd --write), seed %d, chunks %d..%d\",\n\t\"seed\": %d,\n\t\"chunks\": {\n%s\n\t}\n}\n" % [
			SEED, r.x, r.y, SEED, ",\n".join(lines)])
		f.close()
		print("valley baseline written: %d chunks (%d ms)" % [got.size(), Time.get_ticks_msec() - t0])
		tree.quit(0)
		return
	var base_text := FileAccess.get_file_as_string(BASELINE)
	var base: Variant = JSON.parse_string(base_text)
	if not (base is Dictionary) or not (base as Dictionary).has("chunks"):
		print("FAIL: cannot read %s" % BASELINE)
		tree.quit(1)
		return
	var bc: Dictionary = base["chunks"]
	var allowed := {}
	for p in PUERTO_CHUNKS:
		allowed["%d,%d" % [int(p[0]), int(p[1])]] = true
	var bad: Array[String] = []
	var changed_allowed: Array[String] = []
	var raw_only := 0
	var same := 0
	for k in got:
		if not bc.has(k):
			bad.append("%s missing from the baseline" % k)
			continue
		var a: Dictionary = got[k]
		var b: Dictionary = bc[k]
		var diff: Array[String] = []
		for f in ["h", "s", "e"]:
			if str(a[f]) != str(b[f]):
				diff.append(f)
		if diff.is_empty():
			same += 1
			continue
		if allowed.has(k):
			changed_allowed.append(k)
			continue
		if tolerant and diff == ["h"] and str(a["hq"]) == str(b["hq"]):
			raw_only += 1
			continue
		bad.append("%s changed (%s; entries %d -> %d)" % [k, ",".join(diff), int(b["n"]), int(a["n"])])
	var unchanged_allowed := allowed.size() - changed_allowed.size()
	print("valley unchanged: %d chunks (%d..%d), %d identical, %d on the Carretera del Puerto list changed (%d listed, %d of them unchanged), %d raw-bit only (tolerant), %d FAILED (%d ms)" % [
		got.size(), r.x, r.y, same, changed_allowed.size(), allowed.size(), unchanged_allowed, raw_only, bad.size(), Time.get_ticks_msec() - t0])
	for s in bad.slice(0, 40):
		print("  FAIL: " + s)
	if bad.is_empty():
		print("VALLEY UNCHANGED OK")
		tree.quit(0)
	else:
		print("VALLEY UNCHANGED FAILED")
		tree.quit(1)
