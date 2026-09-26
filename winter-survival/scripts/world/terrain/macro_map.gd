class_name MacroMap
extends RefCounted
## Authored macro plan (ARQ v2 §8.4, PLAN §3.2 "macro autorado / micro procedural"): data/world/macro_map.png
## (384 × 384 px, 1 px = 8 m, covering ±1536 m; pixel (i, j) is centred at −1536 + (i + 0.5) × 8) and
## data/world/macro_roads.json. Channels: R = height high byte, A = height low byte (16 bits over
## 0…HEIGHT_RANGE m), G = biome × 40, B = scatter density (0…255). v0 is painted by tools/gen_macro_map.gd from
## the ASCII map of PLAN §4.2 (PoiRegistry). Read-only after load: safe to query from worker threads.
##
## Height: the pixels are stored relative to H0_CODE (the value painted flat around the clearing), smoothed with
## a cubic B‑spline and sampled on a global LATTICE m grid (bilinear in between), so any caller — client,
## server, any chunk — computes identical values, and the clearing gets exactly 0.

const MAP_PATH := "res://data/world/macro_map.png"
const ROADS_PATH := "res://data/world/macro_roads.json"
const SIZE := 384
const PX := 8.0
const HEIGHT_RANGE := 160.0
## Height code painted around the clearing (≈ 20 m): the macro contributes exactly 0 there.
const H0_CODE := 8192
const LATTICE := 4.0
enum Biome { DENSE_FOREST, FOREST, FIELD, LAKE, MOUNTAIN, SETTLEMENT }
const BIOME_STEP := 40

var ok: bool = false
## Heights relative to H0 (m), row-major (j * SIZE + i).
var rel := PackedFloat32Array()
var biome := PackedByteArray()
var density := PackedByteArray()
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
	rel.resize(n)
	biome.resize(n)
	density.resize(n)
	var scale := HEIGHT_RANGE / 65535.0
	for k in n:
		var o := k * 4
		var code := int(data[o]) * 256 + int(data[o + 3])
		rel[k] = float(code - H0_CODE) * scale
		biome[k] = clampi(int(round(float(data[o + 1]) / float(BIOME_STEP))), 0, Biome.SETTLEMENT)
		density[k] = data[o + 2]
	ok = true


func set_roads(d: Dictionary) -> void:
	roads.clear()
	for r in d.get("roads", []):
		var pts := PackedVector2Array()
		for p in r.get("points", []):
			pts.append(Vector2(float(p[0]), float(p[1])))
		if pts.size() >= 2:
			roads.append({"id": str(r.get("id", "")), "kind": str(r.get("kind", "road")), "width": float(r.get("width", 6.0)), "points": pts})


# ------------------------------------------------------------------ height (relative to the clearing, m)
## Cubic B-spline of the relative heights at a world position (16 taps, clamped at the map edge).
func bspline(x: float, z: float) -> float:
	if not ok:
		return 0.0
	var u := (x + WorldConst.HALF) / PX - 0.5
	var v := (z + WorldConst.HALF) / PX - 0.5
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
	var i := clampi(int(floor((x + WorldConst.HALF) / PX)), 0, SIZE - 1)
	var j := clampi(int(floor((z + WorldConst.HALF) / PX)), 0, SIZE - 1)
	return biome[j * SIZE + i]


## Scatter density multiplier 0…1 (bilinear).
func density_at(x: float, z: float) -> float:
	if not ok:
		return 1.0
	var u := (x + WorldConst.HALF) / PX - 0.5
	var v := (z + WorldConst.HALF) / PX - 0.5
	var i := int(floor(u))
	var j := int(floor(v))
	var tu := u - float(i)
	var tv := v - float(j)
	var d00 := float(density[clampi(j, 0, SIZE - 1) * SIZE + clampi(i, 0, SIZE - 1)])
	var d10 := float(density[clampi(j, 0, SIZE - 1) * SIZE + clampi(i + 1, 0, SIZE - 1)])
	var d01 := float(density[clampi(j + 1, 0, SIZE - 1) * SIZE + clampi(i, 0, SIZE - 1)])
	var d11 := float(density[clampi(j + 1, 0, SIZE - 1) * SIZE + clampi(i + 1, 0, SIZE - 1)])
	return lerpf(lerpf(d00, d10, tu), lerpf(d01, d11, tu), tv) / 255.0
