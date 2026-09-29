class_name PopulationTable
extends RefCounted
## Resident zombie targets of the 96 × 96 chunks (W1, PLAN C25 "tablas de población de 96²"; ARQ v2 §10.7 población).
## Pure and deterministic from the seed, the macro map and PoiRegistry, so any server computes the same table. The
## server's PopulationManager reads it (× the rule `zombie_count_scale`); values are filled lazily per chunk into a
## dense PackedByteArray of WorldConst.CHUNK_COUNT bytes (9 kB; WorldConst.chunk_index), NOT_SET until asked.
##
## Rules:
## - the M3 valley square (chunk centre within ±VALLEY_SQUARE m): the M4 formula, unchanged (forest 0–1, field
##   0–1, lake ice 0–1, mountains 0, settlements 3–8, +1 per forest cabin);
## - elsewhere: the deepest W1 region with a "zombies" [min, max] range (doc 09 §4.3; tier 0 before the broad
##   areas); a region still `reserved` (nothing urban built yet: W1) uses UNBUILT_SCALE of it, capped at
##   UNBUILT_CAP, until its milestone builds the buildings the population is meant to fill;
## - no region: the biome (BIOME_RANGE; the valley's biomes keep their M4 ranges).

const GEN := 404   # same generator id as PopulationManager (M4): the valley's targets are the M4 ones
const NOT_SET := 255
const VALLEY_SQUARE := 1450.0
const CLEARING_SAFE := 100.0
const UNBUILT_SCALE := 0.2
const UNBUILT_CAP := 12
## [min, max] residents per chunk of each biome outside any region range (MacroMap.Biome order).
const BIOME_RANGE := [[0, 1], [0, 1], [0, 1], [0, 1], [0, 0], [3, 8], [2, 4], [2, 4], [2, 4], [2, 4], [0, 2], [0, 2],
	[0, 1], [0, 2], [0, 0], [0, 1]]

var hf: HeightFunction
var table := PackedByteArray()


static func create(p_hf: HeightFunction) -> PopulationTable:
	var t := PopulationTable.new()
	t.hf = p_hf
	t.table.resize(WorldConst.CHUNK_COUNT)
	t.table.fill(NOT_SET)
	return t


## Base target of a chunk (before the server rule scale).
func target(cx: int, cz: int) -> int:
	if not WorldConst.in_grid(cx, cz):
		return 0
	var i := WorldConst.chunk_index(cx, cz)
	var v := table[i]
	if v == NOT_SET:
		v = mini(compute(hf, cx, cz), NOT_SET - 1)
		table[i] = v
	return v


## Fills the whole 96² table (tools / tests; the server fills it lazily).
func fill_all() -> void:
	for cz in WorldConst.WORLD_CHUNKS:
		for cx in WorldConst.WORLD_CHUNKS:
			target(cx, cz)


static func compute(p_hf: HeightFunction, cx: int, cz: int) -> int:
	var c := WorldConst.chunk_center(cx, cz)
	if maxf(absf(c.x), absf(c.z)) < CLEARING_SAFE or not WorldConst.in_playable(c.x, c.z):
		return 0
	var seed_v := p_hf.world_seed
	var u := WorldConst.rand01(seed_v, GEN, cx, cz, 0)
	var key := WorldConst.key(cx, cz)
	var b := p_hf.macro.biome_at(c.x, c.z)
	var n := 0
	if absf(c.x) <= VALLEY_SQUARE and absf(c.z) <= VALLEY_SQUARE:
		var site_n := Settlements.resident_target(seed_v, cx, cz)
		if site_n >= 0:
			return site_n   # M6b: the village / POI residents by land use (buildings + streets)
		# the M4 formula (PopulationManager.target_of before W1)
		match b:
			MacroMap.Biome.DENSE_FOREST, MacroMap.Biome.FOREST:
				n = 1 if u < 0.45 else 0
			MacroMap.Biome.FIELD:
				n = 1 if u < 0.35 else 0
			MacroMap.Biome.LAKE:
				n = 1 if u < 0.3 else 0
			MacroMap.Biome.SETTLEMENT:
				n = 3 + int(WorldConst.rand01(seed_v, GEN, cx, cz, 1) * 6.0)
		for pad in PoiRegistry.PADS:
			var pc: Vector2 = pad["center"]
			if str(pad.get("model", "")) == "cabin_small" and WorldConst.key(WorldConst.chunk_of(pc.x), WorldConst.chunk_of(pc.y)) == key:
				n += 1
		return n
	var u2 := WorldConst.rand01(seed_v, GEN, cx, cz, 1)
	var rec := _range_region(c.x, c.z)
	if not rec.is_empty():
		var zr: Array = rec["zombies"]
		var lo := int(zr[0])
		var hi := int(zr[1])
		n = lo + int(u2 * float(hi - lo + 1))
		if bool(rec.get("reserved", false)):
			n = mini(int(round(float(n) * UNBUILT_SCALE)), UNBUILT_CAP)
		return n
	var br: Array = BIOME_RANGE[b]
	return int(br[0]) + int(u2 * float(int(br[1]) - int(br[0]) + 1))


## The deepest region with a zombie range at a point: tier 0 (places, districts, water) before tier 1 (broad areas).
static func _range_region(x: float, z: float) -> Dictionary:
	for tier in [0, 1]:
		for r: Dictionary in PoiRegistry.REGIONS:
			if not r.has("zombies") or int(r.get("tier", 0)) != tier:
				continue
			if PoiRegistry.region_has(r, x, z):
				return r
	return {}
