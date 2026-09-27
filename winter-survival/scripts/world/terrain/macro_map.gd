class_name MacroMap
extends RefCounted
## Authored macro plan (ARQ v2 §8.4, PLAN §3.2 "macro autorado / micro procedural"; W1: PLAN C25):
## data/world/macro_map.png (768 × 768 px, 1 px = 8 m, covering −1536 … +4608 m on both axes; pixel (i, j) is
## centred at MACRO_ORIGIN + (i + 0.5) × 8) and data/world/macro_roads.json (road and rail splines). Channels:
## R = height high byte, A = height low byte (16 bits over 0…HEIGHT_RANGE m), G = biome × BIOME_STEP, B = scatter
## density (0…255). v1 is painted by tools/gen_macro_map.gd from the 48 × 48 ASCII map (PoiRegistry); its first
## 384² pixels are the M3 map, byte for byte where the valley reads them. Read-only after load: safe to query from
## worker threads.
##
## W1 also derives a per-pixel RELIEF amplitude from the biome (RELIEF_OF_BIOME): the slice noise of
## HeightFunction (±9 m) is multiplied by it, so the city, the port, the air base and the river are flat. The
## valley's biomes (0–5) have amplitude exactly 1 and `relief_block` returns {} (= 1 everywhere) for any area
## whose kernel only sees them: the valley's heights stay bit-identical.
##
## Height: the pixels are stored relative to H0_CODE (the value painted flat around the clearing), smoothed with
## a cubic B‑spline and sampled on a global LATTICE m grid (bilinear in between), so any caller — client,
## server, any chunk — computes identical values, and the clearing gets exactly 0.

const MAP_PATH := "res://data/world/macro_map.png"
const ROADS_PATH := "res://data/world/macro_roads.json"
const SIZE := 768
const PX := 8.0
const HEIGHT_RANGE := 160.0
## Height code painted around the clearing (≈ 20 m): the macro contributes exactly 0 there.
const H0_CODE := 8192
const LATTICE := 4.0
## 0–5 are the M3 valley's; 6–15 are W1's (doc 09 §4.1). RIVER = río helado (Albo, dársena); LAKE also holds the
## new frozen lakes (embalse, ibón).
enum Biome { DENSE_FOREST, FOREST, FIELD, LAKE, MOUNTAIN, SETTLEMENT, OLD_TOWN, ENSANCHE, FINANCIAL, BARRIADA,
	SUBURB, INDUSTRIAL, PORT, AIRBASE, SKI, RIVER }
const BIOME_COUNT := 16
## G channel = biome × BIOME_STEP (M3 used × 40 for 6 biomes; 16 biomes need × 16).
const BIOME_STEP := 16
## Amplitude of the slice noise per biome (1 = the M3 terrain; the valley's biomes must stay exactly 1).
const RELIEF_OF_BIOME := [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.12, 0.10, 0.08, 0.15, 0.4, 0.10, 0.06, 0.06, 0.8, 0.0]
## True for the biomes where nothing grows on the ground (open water ice).
const WATER_BIOMES := [Biome.LAKE, Biome.RIVER]

var ok: bool = false
## Heights relative to H0 (m), row-major (j * SIZE + i).
var rel := PackedFloat32Array()
var biome := PackedByteArray()
var density := PackedByteArray()
## Relief amplitude per pixel (RELIEF_OF_BIOME of its biome) and a summed-area table of the pixels where it is not
## 1 ((SIZE + 1)², so "is this block all 1?" is four reads).
var relief := PackedFloat32Array()
var _relief_sat := PackedInt32Array()
## [{"id": String, "kind": String, "width": float, "points": PackedVector2Array}]
var roads: Array = []


static func load_default() -> MacroMap:
	var m := MacroMap.new()
	var img: Image = null
	if ResourceLoader.exists(MAP_PATH):
		var res: Resource = load(MAP_PATH)
		if res is Image:
			img = res
		elif res is Texture2D:
			img = (res as Texture2D).get_image()
	if img == null:
		push_error("MacroMap: cannot load %s (run tools/gen_macro_map.gd)" % MAP_PATH)
	else:
		m.set_image(img)
	var roads_data: Variant = null
	if ResourceLoader.exists(ROADS_PATH):
		var j: Resource = load(ROADS_PATH)
		if j is JSON:
			roads_data = (j as JSON).data
	if roads_data == null and FileAccess.file_exists(ROADS_PATH):
		roads_data = JSON.parse_string(FileAccess.get_file_as_string(ROADS_PATH))
	if roads_data is Dictionary:
		m.set_roads(roads_data)
	else:
		push_error("MacroMap: cannot load %s" % ROADS_PATH)
	return m


func set_image(img: Image) -> void:
	var src := img
	if src.is_compressed():
		src = img.duplicate()
		src.decompress()
	if src.get_format() != Image.FORMAT_RGBA8:
		src = src.duplicate() if src == img else src
		src.convert(Image.FORMAT_RGBA8)
	if src.get_width() != SIZE or src.get_height() != SIZE:
		push_error("MacroMap: expected %d² px, got %dx%d" % [SIZE, src.get_width(), src.get_height()])
		return
	var data := src.get_data()
	var n := SIZE * SIZE
	# one pass, local arrays (member access and per-pixel function calls cost more than the maths here)
	var scale := HEIGHT_RANGE / 65535.0
	var b_lut := PackedByteArray()
	var r_lut := PackedFloat32Array()
	var one_lut := PackedInt32Array()
	b_lut.resize(256)
	r_lut.resize(256)
	one_lut.resize(256)
	for g in 256:
		var bb := clampi((g + BIOME_STEP / 2) / BIOME_STEP, 0, BIOME_COUNT - 1)
		b_lut[g] = bb
		r_lut[g] = RELIEF_OF_BIOME[bb]
		one_lut[g] = 0 if RELIEF_OF_BIOME[bb] == 1.0 else 1
	var l_rel := PackedFloat32Array()
	var l_bio := PackedByteArray()
	var l_den := PackedByteArray()
	var l_rlf := PackedFloat32Array()
	var sat := PackedInt32Array()
	l_rel.resize(n)
	l_bio.resize(n)
	l_den.resize(n)
	l_rlf.resize(n)
	var w := SIZE + 1
	sat.resize(w * w)
	sat.fill(0)
	var h0 := float(H0_CODE)
	var k := 0
	for j in SIZE:
		var row := 0
		var s0 := j * w + 1
		var s1 := s0 + w
		for i in SIZE:
			var o := k * 4
			var g := data[o + 1]
			l_rel[k] = (float(data[o] * 256 + data[o + 3]) - h0) * scale
			l_bio[k] = b_lut[g]
			l_rlf[k] = r_lut[g]
			l_den[k] = data[o + 2]
			row += one_lut[g]
			sat[s1 + i] = sat[s0 + i] + row
			k += 1
	rel = l_rel
	biome = l_bio
	density = l_den
	relief = l_rlf
	_relief_sat = sat
	ok = true


## Pixels with relief ≠ 1 in the pixel rect [i0, i1] × [j0, j1] (clamped to the map).
func _relief_count(i0: int, j0: int, i1: int, j1: int) -> int:
	var w := SIZE + 1
	var a0 := clampi(i0, 0, SIZE - 1)
	var b0 := clampi(j0, 0, SIZE - 1)
	var a1 := clampi(i1, 0, SIZE - 1) + 1
	var b1 := clampi(j1, 0, SIZE - 1) + 1
	return _relief_sat[b1 * w + a1] - _relief_sat[b0 * w + a1] - _relief_sat[b1 * w + a0] + _relief_sat[b0 * w + a0]


func set_roads(d: Dictionary) -> void:
	roads.clear()
	for r in d.get("roads", []):
		var pts := PackedVector2Array()
		for p in r.get("points", []):
			pts.append(Vector2(float(p[0]), float(p[1])))
		if pts.size() >= 2:
			# optional (W1): "name" (region banner of a named road), "smooth" (profile half window in samples of
			# 8 m, default 5), "shoulder" (m, default 7), "max_grade" (profile slope limit, 0 = none), "poles"
			# (snow pole spacing, m), "guard" ([[s0, s1], …] guardrail stretches, metres along the road)
			roads.append({"id": str(r.get("id", "")), "kind": str(r.get("kind", "road")), "width": float(r.get("width", 6.0)), "points": pts,
				"name": str(r.get("name", "")), "smooth": int(r.get("smooth", 5)), "shoulder": float(r.get("shoulder", 7.0)),
				"max_grade": float(r.get("max_grade", 0.0)), "poles": float(r.get("poles", 0.0)), "guard": r.get("guard", []), "pads": bool(r.get("pads", false)),
				"pole_model": str(r.get("pole_model", ""))})


# ------------------------------------------------------------------ height (relative to the clearing, m)
## Cubic B-spline of the relative heights at a world position (16 taps, clamped at the map edge).
func bspline(x: float, z: float) -> float:
	if not ok:
		return 0.0
	var u := (x - WorldConst.MACRO_ORIGIN) / PX - 0.5
	var v := (z - WorldConst.MACRO_ORIGIN) / PX - 0.5
	var i := int(floor(u))
	var j := int(floor(v))
	var t := u - float(i)
	var t2 := t * t
	var t3 := t2 * t
	var it := 1.0 - t
	var wu0 := it * it * it / 6.0
	var wu1 := (3.0 * t3 - 6.0 * t2 + 4.0) / 6.0
	var wu2 := (-3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0) / 6.0
	var wu3 := t3 / 6.0
	t = v - float(j)
	t2 = t * t
	t3 = t2 * t
	it = 1.0 - t
	var wv := [it * it * it / 6.0, (3.0 * t3 - 6.0 * t2 + 4.0) / 6.0, (-3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0) / 6.0, t3 / 6.0]
	var i0 := clampi(i - 1, 0, SIZE - 1)
	var i1 := clampi(i, 0, SIZE - 1)
	var i2 := clampi(i + 1, 0, SIZE - 1)
	var i3 := clampi(i + 2, 0, SIZE - 1)
	var acc := 0.0
	for b in 4:
		var r := clampi(j - 1 + b, 0, SIZE - 1) * SIZE
		acc += float(wv[b]) * (wu0 * rel[r + i0] + wu1 * rel[r + i1] + wu2 * rel[r + i2] + wu3 * rel[r + i3])
	return acc


## Lattice value at integer lattice coordinates (world (a × LATTICE, b × LATTICE)).
func lattice(a: int, b: int) -> float:
	return bspline(float(a) * LATTICE, float(b) * LATTICE)


## Relative macro height at a world position (bilinear over the global lattice).
func height_rel(x: float, z: float) -> float:
	var fa := x / LATTICE
	var fb := z / LATTICE
	var a := int(floor(fa))
	var b := int(floor(fb))
	var ta := fa - float(a)
	var tb := fb - float(b)
	var h00 := lattice(a, b)
	var h10 := lattice(a + 1, b)
	var h01 := lattice(a, b + 1)
	var h11 := lattice(a + 1, b + 1)
	return lerpf(lerpf(h00, h10, ta), lerpf(h01, h11, ta), tb)


## Lattice block covering world [x0, x1] × [z0, z1] (m): {"a0", "b0", "na", "nb", "v": PackedFloat32Array}.
func lattice_block(x0: float, z0: float, x1: float, z1: float) -> Dictionary:
	var a0 := int(floor(x0 / LATTICE))
	var b0 := int(floor(z0 / LATTICE))
	var a1 := int(floor(x1 / LATTICE)) + 1
	var b1 := int(floor(z1 / LATTICE)) + 1
	var na := a1 - a0 + 1
	var nb := b1 - b0 + 1
	var v := PackedFloat32Array()
	v.resize(na * nb)
	for bb in nb:
		for aa in na:
			v[bb * na + aa] = lattice(a0 + aa, b0 + bb)
	return {"a0": a0, "b0": b0, "na": na, "nb": nb, "v": v}


## Same value as height_rel() but from a precomputed block (chunk generation).
static func height_rel_block(blk: Dictionary, x: float, z: float) -> float:
	var fa := x / LATTICE
	var fb := z / LATTICE
	var a := int(floor(fa))
	var b := int(floor(fb))
	var ta := fa - float(a)
	var tb := fb - float(b)
	var na: int = blk["na"]
	var ia := a - int(blk["a0"])
	var ib := b - int(blk["b0"])
	var v: PackedFloat32Array = blk["v"]
	var k := ib * na + ia
	return lerpf(lerpf(v[k], v[k + 1], ta), lerpf(v[k + na], v[k + na + 1], ta), tb)


# ------------------------------------------------------------------ biome / density
func biome_at(x: float, z: float) -> int:
	if not ok:
		return Biome.FOREST
	var i := clampi(int(floor((x - WorldConst.MACRO_ORIGIN) / PX)), 0, SIZE - 1)
	var j := clampi(int(floor((z - WorldConst.MACRO_ORIGIN) / PX)), 0, SIZE - 1)
	return biome[j * SIZE + i]


## Scatter density multiplier 0…1 (bilinear).
func density_at(x: float, z: float) -> float:
	if not ok:
		return 1.0
	var u := (x - WorldConst.MACRO_ORIGIN) / PX - 0.5
	var v := (z - WorldConst.MACRO_ORIGIN) / PX - 0.5
	var i := int(floor(u))
	var j := int(floor(v))
	var tu := u - float(i)
	var tv := v - float(j)
	var d00 := float(density[clampi(j, 0, SIZE - 1) * SIZE + clampi(i, 0, SIZE - 1)])
	var d10 := float(density[clampi(j, 0, SIZE - 1) * SIZE + clampi(i + 1, 0, SIZE - 1)])
	var d01 := float(density[clampi(j + 1, 0, SIZE - 1) * SIZE + clampi(i, 0, SIZE - 1)])
	var d11 := float(density[clampi(j + 1, 0, SIZE - 1) * SIZE + clampi(i + 1, 0, SIZE - 1)])
	return lerpf(lerpf(d00, d10, tu), lerpf(d01, d11, tu), tv) / 255.0


# ------------------------------------------------------------------ relief amplitude (W1)
## Relief amplitude on the global lattice: exactly 1.0 when the 4 × 4 B-spline taps are all 1 (the valley), else
## the cubic B-spline of the per-pixel amplitudes (smooth: no steps where biomes meet).
func relief_lattice(a: int, b: int) -> float:
	if not ok:
		return 1.0
	var x := float(a) * LATTICE
	var z := float(b) * LATTICE
	var u := (x - WorldConst.MACRO_ORIGIN) / PX - 0.5
	var v := (z - WorldConst.MACRO_ORIGIN) / PX - 0.5
	var i := int(floor(u))
	var j := int(floor(v))
	if _relief_count(i - 1, j - 1, i + 2, j + 2) == 0:
		return 1.0
	var t := u - float(i)
	var wu := _bw(t)
	var wv := _bw(v - float(j))
	var acc := 0.0
	for bb in 4:
		var r := clampi(j - 1 + bb, 0, SIZE - 1) * SIZE
		for aa in 4:
			acc += float(wv[bb]) * float(wu[aa]) * relief[r + clampi(i - 1 + aa, 0, SIZE - 1)]
	return acc


static func _bw(t: float) -> Array:
	var t2 := t * t
	var t3 := t2 * t
	var it := 1.0 - t
	return [it * it * it / 6.0, (3.0 * t3 - 6.0 * t2 + 4.0) / 6.0, (-3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0) / 6.0, t3 / 6.0]


## Relief amplitude at a world point (bilinear over the lattice; exactly 1.0 in the valley).
func relief_at(x: float, z: float) -> float:
	var fa := x / LATTICE
	var fb := z / LATTICE
	var a := int(floor(fa))
	var b := int(floor(fb))
	var r00 := relief_lattice(a, b)
	var r10 := relief_lattice(a + 1, b)
	var r01 := relief_lattice(a, b + 1)
	var r11 := relief_lattice(a + 1, b + 1)
	if r00 == 1.0 and r10 == 1.0 and r01 == 1.0 and r11 == 1.0:
		return 1.0
	var ta := fa - float(a)
	var tb := fb - float(b)
	return lerpf(lerpf(r00, r10, ta), lerpf(r01, r11, ta), tb)


## Relief lattice block over world [x0, x1] × [z0, z1] (same layout as lattice_block), or {} when it is 1.0
## everywhere (the caller then leaves the slice noise untouched: bit-identical valley).
func relief_block(x0: float, z0: float, x1: float, z1: float) -> Dictionary:
	var a0 := int(floor(x0 / LATTICE))
	var b0 := int(floor(z0 / LATTICE))
	var a1 := int(floor(x1 / LATTICE)) + 1
	var b1 := int(floor(z1 / LATTICE)) + 1
	if not ok:
		return {}
	# fast path: every B-spline tap of every lattice point of the block is 1 (the valley)
	var pi0 := int(floor((float(a0) * LATTICE - WorldConst.MACRO_ORIGIN) / PX - 0.5)) - 1
	var pj0 := int(floor((float(b0) * LATTICE - WorldConst.MACRO_ORIGIN) / PX - 0.5)) - 1
	var pi1 := int(floor((float(a1) * LATTICE - WorldConst.MACRO_ORIGIN) / PX - 0.5)) + 2
	var pj1 := int(floor((float(b1) * LATTICE - WorldConst.MACRO_ORIGIN) / PX - 0.5)) + 2
	if _relief_count(pi0, pj0, pi1, pj1) == 0:
		return {}
	var na := a1 - a0 + 1
	var nb := b1 - b0 + 1
	var v := PackedFloat32Array()
	v.resize(na * nb)
	var any := false
	for bb in nb:
		for aa in na:
			var r := relief_lattice(a0 + aa, b0 + bb)
			v[bb * na + aa] = r
			if r != 1.0:
				any = true
	if not any:
		return {}
	return {"a0": a0, "b0": b0, "na": na, "nb": nb, "v": v}
