class_name ScatterGen
## Pure scatter generators (ARQ v2 §8.6, PLAN M3). Two sources, both deterministic from the world seed:
##
## 1. `clearing_entries(hf)`: the slice's scatter of the hunter's clearing (ex scripts/world/scatter.gd), ported
##    call for call (same RandomNumberGenerator sequence, weights as ordered arrays) so every tree, rock, bush
##    and pickup of the clearing keeps its exact position, yaw, scale and variant. Global list, built once.
## 2. `procedural(hf, rect)`: the rest of the world, one candidate per cell of global grids (trees 4 m, rocks and
##    small props 8 m, logs and interactive nodes 16 m). Every random number is a stateless hash of
##    (seed, generator, cell, k), so any chunk can evaluate any cell (neighbour entries for the contact AO, no
##    seams, no neighbour cache, identical on client and server). Cells never straddle chunks (64 = 16 × 4).
##
## Entry: {"v": variant index (ScatterCatalog) or -1, "node": ScatterCatalog.NodeKind or -1, "x", "z", "yaw",
## "s" (scale), "wid" (63-bit, WorldConst.hash64), + "item"/"model" for pickups}. Heights are added by the
## chunk builder from its own samples (so objects sit exactly on the rendered surface).

const GEN_CLEARING := 100
const GEN_TREES := 101
const GEN_LOGS := 102
const GEN_ROCKS := 103
const GEN_SMALL := 104
const GEN_NODES := 105
## The slice clearing (legacy list) owns |x|, |z| < CLEARING_ZONE; the procedural scatter starts outside.
const CLEARING_ZONE := 80.0
const LEGACY_BOUNDS := 78.0
const LEGACY_EXCLUSIONS := [[Vector2(-21, -13), 8.0], [Vector2(-11, -3), 4.5], [Vector2(-6.5, 9.5), 1.5]]

## Per-biome acceptance (MacroMap.Biome order: dense forest, forest, field, lake, mountain, settlement).
const TREE_P := [0.62, 0.42, 0.03, 0.0, 0.35, 0.05]
const ROCK_P := [0.06, 0.10, 0.05, 0.0, 0.55, 0.03]
const LOG_P := [0.45, 0.35, 0.08, 0.0, 0.25, 0.05]
const TREE_W := [
	[["pine_a", 0.26], ["pine_b", 0.20], ["pine_c", 0.12], ["pine_d", 0.16], ["pine_e", 0.12], ["pine_young", 0.06], ["dead_tree", 0.05], ["dead_tree_b", 0.03]],
	[["pine_a", 0.22], ["pine_b", 0.22], ["pine_c", 0.18], ["pine_d", 0.06], ["pine_e", 0.08], ["pine_young", 0.12], ["dead_tree", 0.08], ["dead_tree_b", 0.04]],
	[["pine_young", 0.45], ["pine_c", 0.25], ["dead_tree", 0.20], ["dead_tree_b", 0.10]],
	[["pine_c", 1.0]],
	[["pine_d", 0.30], ["pine_a", 0.25], ["pine_e", 0.15], ["pine_c", 0.10], ["dead_tree", 0.12], ["dead_tree_b", 0.08]],
	[["pine_young", 0.40], ["pine_b", 0.30], ["dead_tree", 0.30]],
]
const ROCK_W_FOREST := [["rock_a", 0.35], ["rock_b", 0.20], ["rock_c", 0.30], ["rock_d", 0.15]]
const ROCK_W_MOUNTAIN := [["rock_e", 0.35], ["rock_b", 0.25], ["rock_d", 0.20], ["rock_a", 0.20]]
const LOG_W := [["fallen_log", 0.40], ["fallen_log_b", 0.30], ["stump", 0.20], ["branch_pile", 0.10]]
const SNOW_W := [["snow_pile_a", 0.35], ["snow_pile_b", 0.30], ["snow_pile_c", 0.25], ["snow_drift_4", 0.10]]
const BUSH_W := [["bush_a", 0.55], ["bush_b", 0.45]]

static var _cum_cache: Dictionary = {}


# ------------------------------------------------------------------ helpers
## k-th uniform number of a cell hash.
static func sub(h: int, k: int) -> float:
	return WorldConst.unit(WorldConst.mix64(h ^ (k * -7046029254386353131)))


## Weighted pick with an ordered weight table (no Dictionary order dependence, R3).
static func pick(table: Array, r: float) -> int:
	var acc := 0.0
	for e in table:
		acc += float(e[1])
		if r <= acc:
			return ScatterCatalog.index_of(e[0])
	return ScatterCatalog.index_of(table[0][0])


# ------------------------------------------------------------------ 1. the slice clearing (exact port)
## The slice scatter, in the slice's order. Returns entries (see header) with wid = hash64(seed, GEN_CLEARING, i).
static func clearing_entries(world_seed: int) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 11
	var placed: Array = []   # Vector2 (an Array: lambdas capture locals by value, packed arrays would not be shared)
	var add := func(v: String, node: int, p: Vector2, s: float, extra: Dictionary, record: bool) -> void:
		var e := {"v": ScatterCatalog.index_of(v) if v != "" else -1, "node": node, "x": p.x, "z": p.y,
			"yaw": rng.randf_range(0.0, TAU), "s": s, "wid": WorldConst.hash64(world_seed, GEN_CLEARING, out.size())}
		e.merge(extra)
		out.append(e)
		if record:
			placed.append(p)
	var ok := func(p: Vector2, spacing: float, cabin_r: float, avoid_lake: bool) -> bool:
		if absf(p.x) > LEGACY_BOUNDS - 1.0 or absf(p.y) > LEGACY_BOUNDS - 1.0:
			return false
		if p.length() < cabin_r:
			return false
		for ex in LEGACY_EXCLUSIONS:
			if p.distance_to(ex[0]) < float(ex[1]):
				return false
		var lake_d := p.distance_to(HeightFunction.SMALL_LAKE_CENTER)
		var in_lake := lake_d < HeightFunction.SMALL_LAKE_RADIUS
		if avoid_lake and in_lake:
			return false
		if not avoid_lake and in_lake and lake_d < HeightFunction.SMALL_LAKE_RADIUS * 0.8:
			return false
		var sp2 := spacing * spacing
		for q in placed:
			if q.distance_squared_to(p) < sp2:
				return false
		return true
	var sample := func(spacing: float, cabin_r: float, avoid_lake: bool) -> Vector2:
		for i in 30:
			var p := Vector2(rng.randf_range(-LEGACY_BOUNDS + 1.0, LEGACY_BOUNDS - 1.0), rng.randf_range(-LEGACY_BOUNDS + 1.0, LEGACY_BOUNDS - 1.0))
			if ok.call(p, spacing, cabin_r, avoid_lake):
				return p
		return Vector2.INF
	var porch := func(p: Vector2) -> bool:
		return p.y > 1.0 and p.y < 16.0 and absf(p.x) < 7.0 + (p.y - 1.0) * 0.5
	var pick_rng := func(table: Array) -> String:
		var r := rng.randf()
		var acc := 0.0
		for e in table:
			acc += float(e[1])
			if r <= acc:
				return e[0]
		return table[0][0]
	var none := -1
	# trees
	var pine_w := [["pine_a", 0.5], ["pine_b", 0.3], ["pine_c", 0.2]]
	var placed_trees := 0
	var attempts := 0
	while placed_trees < 420 and attempts < 30000:
		attempts += 1
		var p: Vector2 = sample.call(2.4, 8.5, true)
		if p == Vector2.INF:
			continue
		if porch.call(p):
			continue
		var edge := maxf(absf(p.x), absf(p.y)) > 66.0
		if not edge and rng.randf() < 0.15:
			continue
		var v: String = pick_rng.call(pine_w)
		add.call(v, none, p, rng.randf_range(0.9, 1.15), {}, true)
		placed_trees += 1
	for i in 40:
		var p: Vector2 = sample.call(2.2, 9.0, true)
		if p != Vector2.INF and not porch.call(p):
			add.call("dead_tree", none, p, rng.randf_range(0.9, 1.15), {}, true)
	for i in 15:
		var p: Vector2 = sample.call(1.5, 9.0, true)
		if p != Vector2.INF:
			add.call("stump", none, p, rng.randf_range(0.9, 1.1), {}, true)
	var rock_w := [["rock_a", 0.5], ["rock_b", 0.25], ["rock_c", 0.25]]
	for i in 110:
		var p: Vector2 = sample.call(1.8, 9.0, false)
		if p != Vector2.INF:
			var v: String = pick_rng.call(rock_w)
			add.call(v, none, p, rng.randf_range(0.9, 1.15), {}, true)
	for i in 40:
		var p: Vector2 = sample.call(1.5, 9.0, true)
		if p != Vector2.INF:
			add.call("", ScatterCatalog.NodeKind.BERRY_BUSH, p, 1.0, {}, true)
	var wood := {"item": &"madera", "model": "firewood"}
	var stone := {"item": &"piedra", "model": "stone"}
	for i in 45:
		var p: Vector2 = sample.call(1.0, 9.0, false)
		if p != Vector2.INF:
			add.call("", ScatterCatalog.NodeKind.PICKUP, p, 1.0, wood, false)
	for i in 30:
		var p: Vector2 = sample.call(1.0, 9.0, false)
		if p != Vector2.INF:
			add.call("", ScatterCatalog.NodeKind.PICKUP, p, 1.0, stone, false)
	# a few near the porch so the first quest is easy
	for off in [Vector2(3.5, 8.5), Vector2(-4.0, 6.5), Vector2(6.0, 5.0), Vector2(-3.0, 11.0), Vector2(8.0, 9.0)]:
		add.call("", ScatterCatalog.NodeKind.PICKUP, off, 1.0, wood, false)
	for off in [Vector2(5.5, 10.5), Vector2(-6.0, 12.0), Vector2(7.5, 3.5), Vector2(-9.0, 9.0)]:
		add.call("", ScatterCatalog.NodeKind.PICKUP, off, 1.0, stone, false)
	# fallen logs: 4 within 20 m of the cabin, rest anywhere
	var logs := 0
	attempts = 0
	while logs < 4 and attempts < 500:
		attempts += 1
		var ang := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(11.0, 20.0)
		var p := Vector2(cos(ang) * d, sin(ang) * d)
		if ok.call(p, 1.5, 9.0, false):
			add.call("fallen_log", none, p, 1.0, {}, true)
			logs += 1
	for i in 10:
		var p: Vector2 = sample.call(1.5, 9.0, false)
		if p != Vector2.INF:
			add.call("fallen_log", none, p, 1.0, {}, true)
	return out


## Server (dawn respawn, Respawner): a free random point of the slice clearing, like the slice's `_sample`.
static func clearing_random_point(rng: RandomNumberGenerator) -> Vector2:
	for i in 30:
		var p := Vector2(rng.randf_range(-LEGACY_BOUNDS + 1.0, LEGACY_BOUNDS - 1.0), rng.randf_range(-LEGACY_BOUNDS + 1.0, LEGACY_BOUNDS - 1.0))
		if p.length() < 9.0:
			continue
		var blocked := false
		for ex in LEGACY_EXCLUSIONS:
			if p.distance_to(ex[0]) < float(ex[1]):
				blocked = true
		if blocked or p.distance_to(HeightFunction.SMALL_LAKE_CENTER) < HeightFunction.SMALL_LAKE_RADIUS * 0.8:
			continue
		return p
	return Vector2.INF


# ------------------------------------------------------------------ 2. procedural (per cell)
class Ctx:
	extends RefCounted
	var world_seed: int
	var macro: MacroMap
	var segs: PackedFloat32Array
	var pads: PackedFloat32Array
	var lake: bool
	var trees: Dictionary = {}   # tree cell key -> entry or {}


static func _blocked(c: Ctx, x: float, z: float, clr: float) -> bool:
	if absf(x) < CLEARING_ZONE and absf(z) < CLEARING_ZONE:
		return true
	if c.lake and PoiRegistry.lake_sdf(x, z) < 2.0 + clr:
		return true
	var segs := c.segs
	for k in range(0, segs.size(), 5):
		var ax := segs[k]
		var az := segs[k + 1]
		var dx := segs[k + 2] - ax
		var dz := segs[k + 3] - az
		var l2 := dx * dx + dz * dz
		var t := 0.0
		if l2 > 0.0001:
			t = clampf(((x - ax) * dx + (z - az) * dz) / l2, 0.0, 1.0)
		var px := ax + dx * t - x
		var pz := az + dz * t - z
		var lim := segs[k + 4] + 1.5 + clr
		if px * px + pz * pz < lim * lim:
			return true
	var pads := c.pads
	for k in range(0, pads.size(), 3):
		var dx := pads[k] - x
		var dz := pads[k + 1] - z
		var lim := pads[k + 2] + clr
		if dx * dx + dz * dz < lim * lim:
			return true
	return false


## Tree of a 4 m cell ({} when the cell has none). Cached per context.
static func _tree(c: Ctx, gx: int, gz: int) -> Dictionary:
	var ck := (gx << 20) ^ (gz & 0xFFFFF)
	if c.trees.has(ck):
		return c.trees[ck]
	var e := {}
	var h := WorldConst.hash64(c.world_seed, GEN_TREES, gx, gz)
	var x := (float(gx) + 0.5 + (sub(h, 1) - 0.5) * 0.84) * 4.0
	var z := (float(gz) + 0.5 + (sub(h, 2) - 0.5) * 0.84) * 4.0
	if not _blocked(c, x, z, 1.0):
		var b := c.macro.biome_at(x, z)
		var p: float = TREE_P[b] * c.macro.density_at(x, z)
		if sub(h, 0) < p:
			e = {"v": pick(TREE_W[b], sub(h, 3)), "node": -1, "x": x, "z": z, "yaw": sub(h, 4) * TAU,
				"s": 0.85 + 0.35 * sub(h, 5), "wid": h}
	c.trees[ck] = e
	return e


static func _near_tree(c: Ctx, x: float, z: float, r: float) -> bool:
	var gx := int(floor(x / 4.0))
	var gz := int(floor(z / 4.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var t := _tree(c, gx + dx, gz + dz)
			if not t.is_empty() and Vector2(float(t["x"]) - x, float(t["z"]) - z).length() < r:
				return true
	return false


## Every procedural entry whose cell overlaps `rect` (world metres), in a fixed order (pass, cell row, cell col).
## `margin` also returns the cells of one extra ring around it (neighbour entries for the contact AO).
static func procedural(hf: HeightFunction, rect: Rect2, margin: bool = false) -> Array:
	var c := Ctx.new()
	c.world_seed = hf.world_seed
	c.macro = hf.macro
	c.segs = hf.road_segments_in(rect.grow(40.0))
	c.pads = hf.pads_in(rect.grow(40.0))
	c.lake = PoiRegistry.LAKE_BBOX.grow(40.0).intersects(rect)
	var out: Array = []
	# fully inside the slice clearing: nothing procedural
	var zone := Rect2(-CLEARING_ZONE, -CLEARING_ZONE, CLEARING_ZONE * 2.0, CLEARING_ZONE * 2.0)
	if zone.encloses(rect.grow(16.0 if margin else 0.0)):
		return out
	var r4 := rect.grow(4.0) if margin else rect
	var r8 := rect.grow(8.0) if margin else rect
	var r16 := rect.grow(16.0) if margin else rect
	# 1. trees (4 m)
	for gz in range(int(floor(r4.position.y / 4.0)), int(ceil(r4.end.y / 4.0))):
		for gx in range(int(floor(r4.position.x / 4.0)), int(ceil(r4.end.x / 4.0))):
			var t := _tree(c, gx, gz)
			if not t.is_empty():
				out.append(t)
	# 2. rocks (8 m) and 3. small props (8 m, two candidates)
	for gz in range(int(floor(r8.position.y / 8.0)), int(ceil(r8.end.y / 8.0))):
		for gx in range(int(floor(r8.position.x / 8.0)), int(ceil(r8.end.x / 8.0))):
			var h := WorldConst.hash64(c.world_seed, GEN_ROCKS, gx, gz)
			var x := (float(gx) + 0.5 + (sub(h, 1) - 0.5) * 0.8) * 8.0
			var z := (float(gz) + 0.5 + (sub(h, 2) - 0.5) * 0.8) * 8.0
			if not _blocked(c, x, z, 1.0):
				var b := c.macro.biome_at(x, z)
				if sub(h, 0) < float(ROCK_P[b]) * (0.6 + 0.4 * c.macro.density_at(x, z)) and not _near_tree(c, x, z, 1.8):
					var table: Array = ROCK_W_MOUNTAIN if b == MacroMap.Biome.MOUNTAIN else ROCK_W_FOREST
					out.append({"v": pick(table, sub(h, 3)), "node": -1, "x": x, "z": z, "yaw": sub(h, 4) * TAU,
						"s": 0.8 + 0.5 * sub(h, 5), "wid": h})
			for k in 2:
				var hs := WorldConst.hash64(c.world_seed, GEN_SMALL, gx, gz, k)
				var sx := (float(gx) + 0.5 + (sub(hs, 1) - 0.5) * 0.84) * 8.0
				var sz := (float(gz) + 0.5 + (sub(hs, 2) - 0.5) * 0.84) * 8.0
				if _blocked(c, sx, sz, 0.3):
					continue
				var b := c.macro.biome_at(sx, sz)
				if b == MacroMap.Biome.LAKE:
					continue
				var r := sub(hs, 0)
				var table: Array = []
				if k == 0:
					var pb := 0.15 if b == MacroMap.Biome.FIELD else (0.10 if b != MacroMap.Biome.MOUNTAIN else 0.02)
					if r < pb:
						table = BUSH_W
				else:
					var ps := 0.12 if b == MacroMap.Biome.FIELD else 0.07
					if r < ps:
						table = SNOW_W
				if table.is_empty() or _near_tree(c, sx, sz, 1.2):
					continue
				out.append({"v": pick(table, sub(hs, 3)), "node": -1, "x": sx, "z": sz, "yaw": sub(hs, 4) * TAU,
					"s": 0.8 + 0.45 * sub(hs, 5), "wid": hs})
	# 4. logs / stumps / branch piles (16 m) and 5. interactive nodes (16 m, three candidates)
	for gz in range(int(floor(r16.position.y / 16.0)), int(ceil(r16.end.y / 16.0))):
		for gx in range(int(floor(r16.position.x / 16.0)), int(ceil(r16.end.x / 16.0))):
			var h := WorldConst.hash64(c.world_seed, GEN_LOGS, gx, gz)
			var x := (float(gx) + 0.5 + (sub(h, 1) - 0.5) * 0.8) * 16.0
			var z := (float(gz) + 0.5 + (sub(h, 2) - 0.5) * 0.8) * 16.0
			if not _blocked(c, x, z, 1.4):
				var b := c.macro.biome_at(x, z)
				if sub(h, 0) < float(LOG_P[b]) and not _near_tree(c, x, z, 2.0):
					out.append({"v": pick(LOG_W, sub(h, 3)), "node": -1, "x": x, "z": z, "yaw": sub(h, 4) * TAU,
						"s": 0.9 + 0.25 * sub(h, 5), "wid": h})
			for k in 3:
				var hn := WorldConst.hash64(c.world_seed, GEN_NODES, gx, gz, k)
				var nx := (float(gx) + 0.5 + (sub(hn, 1) - 0.5) * 0.84) * 16.0
				var nz := (float(gz) + 0.5 + (sub(hn, 2) - 0.5) * 0.84) * 16.0
				if _blocked(c, nx, nz, 0.6):
					continue
				var b := c.macro.biome_at(nx, nz)
				if b == MacroMap.Biome.LAKE or b == MacroMap.Biome.MOUNTAIN:
					continue
				var r := sub(hn, 0)
				var e := {}
				if k == 0 and r < (0.22 if b <= MacroMap.Biome.FOREST else 0.08):
					e = {"item": &"madera", "model": "firewood", "node": ScatterCatalog.NodeKind.PICKUP}
				elif k == 1 and r < 0.12:
					e = {"item": &"piedra", "model": "stone", "node": ScatterCatalog.NodeKind.PICKUP}
				elif k == 2 and r < (0.07 if b <= MacroMap.Biome.FIELD else 0.02):
					e = {"node": ScatterCatalog.NodeKind.BERRY_BUSH}
				if e.is_empty() or _near_tree(c, nx, nz, 1.3):
					continue
				e.merge({"v": -1, "x": nx, "z": nz, "yaw": sub(hn, 4) * TAU, "s": 1.0, "wid": hn})
				out.append(e)
	return out


## POI props of PoiRegistry.PADS whose centre lies in `rect` (static models on their pad).
static func poi_entries(world_seed: int, rect: Rect2) -> Array:
	var out: Array = []
	for i in PoiRegistry.PADS.size():
		var pad: Dictionary = PoiRegistry.PADS[i]
		var model := str(pad.get("model", ""))
		var c: Vector2 = pad["center"]
		if model == "" or not rect.has_point(c):
			continue
		out.append({"v": -1, "node": ScatterCatalog.NodeKind.PROP, "model": model, "id": str(pad["id"]), "x": c.x, "z": c.y,
			"yaw": deg_to_rad(float(pad.get("yaw", 0.0))), "s": 1.0, "wid": WorldConst.hash64(world_seed, 200, i)})
	return out
