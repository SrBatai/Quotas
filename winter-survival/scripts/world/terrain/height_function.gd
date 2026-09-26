class_name HeightFunction
extends RefCounted
## The world's height field (ARQ v2 §8.2, PLAN M3): one pure function of (seed, x, z), identical on client and
## server (R3: seeded FastNoiseLite, integer hashes, arrays in fixed order, no Dictionary iteration order). Built
## once per world (the road profiles and pad heights are precomputed), then read-only: safe from worker threads.
##
##   h(x, z) = legacy_noise(x, z)                  slice fBm ×6 + low ×3, amplitude 0.3 inside the clearing
##           → small lake + clearing pads          (the slice stamps: the clearing stays exactly as it was)
##           + macro_rel(x, z)                     macro map, 0 within 180 m of the clearing
##           → Lago de las Ánimas                  flat ice at PoiRegistry.LAKE_LEVEL, shore blend
##           → POI pads                            PoiRegistry.PADS
##           → road beds                           macro_roads.json, smoothed longitudinal profile, 7 m shoulders
##
## The world height is defined on the 1 m integer grid (`sample`); between samples it is bilinear (`height_at`),
## which is what the chunk meshes / HeightMapShape3D show (to < 1 cm). `surface_*` returns the CUSTOM0 mask:
## r = asphalt road bed, g = ice, b = packed snow (tracks), a = signed distance to the road centreline
## (128 + 16 × metres, 0 = not on a road) so the terrain shader can draw wheel ruts.

## Slice clearing (ex scripts/world/terrain.gd): amplitude ramp and stamps, in world metres.
const CLEAR_AMP_INNER := 14.0
const CLEAR_AMP_OUTER := 45.0
const SMALL_LAKE_CENTER := Vector2(-42, 30)
const SMALL_LAKE_RADIUS := 20.0
const CLEARING_PADS := [[Vector2(0, 0), 14.0], [Vector2(-21, -13), 8.0], [Vector2(-11, -3), 4.0]]
## Roads.
const ROAD_SHOULDER := 7.0
const ROAD_PROFILE_STEP := 8.0
const ROAD_PROFILE_SMOOTH := 5
const ROAD_KINDS := {"highway": 0, "road": 1, "track": 2}
## Lake shore.
const SHORE_LIFT := 70.0
const SHORE_BLEND := 25.0

var world_seed: int = 0
var macro: MacroMap
var small_lake_level: float = 0.0

var _noise := FastNoiseLite.new()
var _noise2 := FastNoiseLite.new()
var _clearing_pad_h := PackedFloat32Array()
# POI pads: parallel arrays
var _pad_c := PackedVector2Array()
var _pad_r := PackedFloat32Array()
var _pad_h := PackedFloat32Array()
# road segments: parallel arrays (ax, az, bx, bz, s0, len, road index)
var _seg := PackedFloat32Array()    # 6 floats per segment
var _seg_road := PackedInt32Array()
var _road_hw := PackedFloat32Array()
var _road_kind := PackedInt32Array()
var _road_prof: Array[PackedFloat32Array] = []
var _road_bbox: Array[Rect2] = []
var _seg_bbox: Array[Rect2] = []


static func create(seed_value: int, p_macro: MacroMap) -> HeightFunction:
	var hf := HeightFunction.new()
	hf._setup(seed_value, p_macro)
	return hf


func _setup(seed_value: int, p_macro: MacroMap) -> void:
	world_seed = seed_value
	macro = p_macro
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	_noise.frequency = 0.012
	_noise2.seed = seed_value + 7
	_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise2.fractal_type = FastNoiseLite.FRACTAL_NONE
	_noise2.frequency = 0.004
	small_lake_level = legacy_raw(SMALL_LAKE_CENTER.x, SMALL_LAKE_CENTER.y) - 1.0
	for p in CLEARING_PADS:
		_clearing_pad_h.append(legacy_raw((p[0] as Vector2).x, (p[0] as Vector2).y))
	for pad in PoiRegistry.PADS:
		var c: Vector2 = pad["center"]
		_pad_c.append(c)
		_pad_r.append(float(pad["radius"]))
		_pad_h.append(base_height(c.x, c.y))
	_build_roads()


# ------------------------------------------------------------------ components
## 1 when d <= inner, 0 when d >= outer, smooth in between (the slice's `_smooth`).
static func smooth(outer: float, inner: float, d: float) -> float:
	var t := clampf((d - outer) / (inner - outer), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Slice noise with the clearing amplitude ramp (the old `raw` of terrain.gd).
func legacy_raw(x: float, z: float) -> float:
	var d := sqrt(x * x + z * z)
	var amp := 0.3 + 0.7 * (1.0 - smooth(CLEAR_AMP_OUTER, CLEAR_AMP_INNER, d))
	return (_noise.get_noise_2d(x, z) * 6.0 + _noise2.get_noise_2d(x, z) * 3.0) * amp


## Natural ground without lakes, pads or roads (road profiles and pad heights are built from it).
func base_height(x: float, z: float) -> float:
	return legacy_raw(x, z) + (macro.height_rel(x, z) if macro != null else 0.0)


func _build_roads() -> void:
	if macro == null:
		return
	for r in macro.roads:
		var pts: PackedVector2Array = r["points"]
		var ri := _road_hw.size()
		_road_hw.append(float(r["width"]) * 0.5)
		_road_kind.append(int(ROAD_KINDS.get(str(r["kind"]), 1)))
		# resample the centreline every ROAD_PROFILE_STEP m and smooth the natural height along it
		var total := 0.0
		for i in pts.size() - 1:
			total += pts[i].distance_to(pts[i + 1])
		var n := int(ceil(total / ROAD_PROFILE_STEP)) + 1
		var raw := PackedFloat32Array()
		raw.resize(n)
		for k in n:
			var p := _point_at(pts, minf(float(k) * ROAD_PROFILE_STEP, total))
			raw[k] = base_height(p.x, p.y)
		var prof := PackedFloat32Array()
		prof.resize(n)
		for k in n:
			var acc := 0.0
			var cnt := 0
			for o in range(-ROAD_PROFILE_SMOOTH, ROAD_PROFILE_SMOOTH + 1):
				var q := clampi(k + o, 0, n - 1)
				acc += raw[q]
				cnt += 1
			prof[k] = acc / float(cnt)
		_road_prof.append(prof)
		var reach := _road_hw[ri] + ROAD_SHOULDER + 1.0
		var bb := Rect2(pts[0], Vector2.ZERO)
		var s0 := 0.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var l := a.distance_to(b)
			_seg.append_array(PackedFloat32Array([a.x, a.y, b.x, b.y, s0, l]))
			_seg_road.append(ri)
			var sb := Rect2(a, Vector2.ZERO).expand(b).grow(reach)
			_seg_bbox.append(sb)
			bb = bb.merge(sb)
			s0 += l
		_road_bbox.append(bb)


static func _point_at(pts: PackedVector2Array, s: float) -> Vector2:
	var acc := 0.0
	for i in pts.size() - 1:
		var l := pts[i].distance_to(pts[i + 1])
		if acc + l >= s or i == pts.size() - 2:
			return pts[i].lerp(pts[i + 1], clampf((s - acc) / maxf(l, 0.001), 0.0, 1.0))
		acc += l
	return pts[pts.size() - 1]


# ------------------------------------------------------------------ query context (per chunk or per point)
## Selects the pads / road segments / lake relevant to `rect` (world metres): the inner loops only see those.
func context(rect: Rect2) -> Dictionary:
	var pads := PackedInt32Array()
	for i in _pad_c.size():
		var r := _pad_r[i]
		if rect.grow(r).has_point(_pad_c[i]):
			pads.append(i)
	var segs := PackedInt32Array()
	for i in _seg_bbox.size():
		if _seg_bbox[i].intersects(rect):
			segs.append(i)
	var lake := PoiRegistry.LAKE_BBOX.grow(SHORE_LIFT + 5.0).intersects(rect)
	var clearing := rect.intersects(Rect2(-200, -200, 400, 400))
	var blk := {}
	if macro != null:
		blk = macro.lattice_block(rect.position.x - 1.0, rect.position.y - 1.0, rect.end.x + 1.0, rect.end.y + 1.0)
	return {"pads": pads, "segs": segs, "lake": lake, "clearing": clearing, "blk": blk}


## Height and surface mask at a world point with a context (exact function; chunk samples use integer x, z).
## Returns Vector3(height, packed surface r | g << 8 | b << 16, road lateral byte a) (bytes 0…255).
func eval(x: float, z: float, ctx: Dictionary) -> Vector3:
	var h := legacy_raw(x, z)
	var surf := 0
	var lat_byte := 0
	if ctx["clearing"]:
		var dl := Vector2(x, z).distance_to(SMALL_LAKE_CENTER)
		if dl < SMALL_LAKE_RADIUS:
			h = lerpf(h, small_lake_level, smooth(SMALL_LAKE_RADIUS, SMALL_LAKE_RADIUS * 0.7, dl))
		for i in CLEARING_PADS.size():
			var r: float = CLEARING_PADS[i][1]
			var d := Vector2(x, z).distance_to(CLEARING_PADS[i][0])
			if d < r:
				h = lerpf(h, _clearing_pad_h[i], smooth(r, r * 0.6, d))
	var blk: Dictionary = ctx["blk"]
	if not blk.is_empty():
		h += MacroMap.height_rel_block(blk, x, z)
	if ctx["lake"]:
		var sdf := PoiRegistry.lake_sdf(x, z)
		if sdf < SHORE_LIFT:
			var lvl := PoiRegistry.LAKE_LEVEL
			if sdf <= 0.0:
				h = lvl
				surf |= 255 << 8
			else:
				var lift := smooth(SHORE_LIFT, 20.0, sdf)
				h += maxf(0.0, lvl + 0.8 - h) * lift
				h = lerpf(h, lvl, smooth(SHORE_BLEND, 0.0, sdf))
				if sdf < 2.0:
					surf |= int(255.0 * (1.0 - sdf * 0.5)) << 8
	var pads: PackedInt32Array = ctx["pads"]
	for i in pads:
		var r := _pad_r[i]
		var d := Vector2(x, z).distance_to(_pad_c[i])
		if d < r:
			h = lerpf(h, _pad_h[i], smooth(r, r * 0.6, d))
	var segs: PackedInt32Array = ctx["segs"]
	if not segs.is_empty():
		var best_d := INF
		var best_s := 0.0
		var best_r := -1
		var best_side := 1.0
		for si in segs:
			var o := si * 6
			var ax := _seg[o]
			var az := _seg[o + 1]
			var dx := _seg[o + 2] - ax
			var dz := _seg[o + 3] - az
			var l2 := dx * dx + dz * dz
			var t := 0.0
			if l2 > 0.0001:
				t = clampf(((x - ax) * dx + (z - az) * dz) / l2, 0.0, 1.0)
			var px := ax + dx * t - x
			var pz := az + dz * t - z
			var d := sqrt(px * px + pz * pz)
			if d < best_d:
				best_d = d
				best_s = _seg[o + 4] + t * _seg[o + 5]
				best_r = _seg_road[si]
				best_side = 1.0 if dx * (z - az) - dz * (x - ax) >= 0.0 else -1.0
		if best_r >= 0:
			var hw := _road_hw[best_r]
			if best_d < hw + ROAD_SHOULDER:
				var prof := _road_prof[best_r]
				var fk := best_s / ROAD_PROFILE_STEP
				var k := clampi(int(floor(fk)), 0, prof.size() - 1)
				var k2 := mini(k + 1, prof.size() - 1)
				var rh := lerpf(prof[k], prof[k2], clampf(fk - float(k), 0.0, 1.0))
				h = lerpf(h, rh, smooth(hw + ROAD_SHOULDER, hw, best_d))
				var m := int(255.0 * smooth(hw + 0.8, hw - 0.4, best_d))
				if m > 0:
					if _road_kind[best_r] == 2:
						surf |= m << 16
					else:
						surf |= m
				if best_d < hw + 2.0:
					lat_byte = clampi(int(round(128.0 + best_side * best_d * 16.0)), 1, 255)
	return Vector3(h, float(surf), float(lat_byte))


# ------------------------------------------------------------------ point queries
## Exact height at a world point (context built on the fly).
func sample(x: float, z: float) -> float:
	return eval(x, z, context(Rect2(x - 0.5, z - 0.5, 1.0, 1.0))).x


## World height: bilinear between the 1 m samples (the surface every chunk mesh / collider shows).
func height_at(x: float, z: float) -> float:
	var x0 := floorf(x)
	var z0 := floorf(z)
	var ctx := context(Rect2(x0 - 0.5, z0 - 0.5, 2.0, 2.0))
	var h00 := eval(x0, z0, ctx).x
	var h10 := eval(x0 + 1.0, z0, ctx).x
	var h01 := eval(x0, z0 + 1.0, ctx).x
	var h11 := eval(x0 + 1.0, z0 + 1.0, ctx).x
	var tx := x - x0
	var tz := z - z0
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Surface mask at the nearest sample (Color r = asphalt, g = ice, b = packed track).
func surface_at(x: float, z: float) -> Color:
	var v := eval(roundf(x), roundf(z), context(Rect2(x - 1.0, z - 1.0, 2.0, 2.0)))
	var s := int(v.y)
	return Color8(s & 255, (s >> 8) & 255, (s >> 16) & 255, int(v.z))


func is_big_lake(x: float, z: float) -> bool:
	return PoiRegistry.LAKE_BBOX.has_point(Vector2(x, z)) and PoiRegistry.lake_sdf(x, z) < 0.0


func is_small_lake(x: float, z: float) -> bool:
	return Vector2(x, z).distance_to(SMALL_LAKE_CENTER) < SMALL_LAKE_RADIUS


## Distance to the nearest road centreline of `kind` ("" = any) and its half width; INF when none is near.
func road_distance(x: float, z: float, max_d: float = 40.0, kind: String = "") -> float:
	var best := INF
	var p := Vector2(x, z)
	for si in _seg_bbox.size():
		if not _seg_bbox[si].grow(max_d).has_point(p):
			continue
		var ri := _seg_road[si]
		if kind != "" and _road_kind[ri] != int(ROAD_KINDS.get(kind, -1)):
			continue
		var o := si * 6
		var a := Vector2(_seg[o], _seg[o + 1])
		var b := Vector2(_seg[o + 2], _seg[o + 3])
		var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) - _road_hw[ri]
		best = minf(best, d)
	return best


## Road segments near a rect, for the scatter: [ax, az, bx, bz, half_width] each.
func road_segments_in(rect: Rect2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for si in _seg_bbox.size():
		if _seg_bbox[si].intersects(rect):
			var o := si * 6
			out.append_array(PackedFloat32Array([_seg[o], _seg[o + 1], _seg[o + 2], _seg[o + 3], _road_hw[_seg_road[si]]]))
	return out


## Pads near a rect: [cx, cz, radius] each.
func pads_in(rect: Rect2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in _pad_c.size():
		if rect.grow(_pad_r[i]).has_point(_pad_c[i]):
			out.append_array(PackedFloat32Array([_pad_c[i].x, _pad_c[i].y, _pad_r[i]]))
	return out


## Samples a block of n × n integer points starting at (x0, z0): heights + surfaces (chunk generation).
func sample_block(x0: int, z0: int, n: int) -> Dictionary:
	var ctx := context(Rect2(float(x0), float(z0), float(n - 1), float(n - 1)))
	var hs := PackedFloat32Array()
	var ss := PackedInt32Array()
	hs.resize(n * n)
	ss.resize(n * n)
	for j in n:
		var z := float(z0 + j)
		for i in n:
			var v := eval(float(x0 + i), z, ctx)
			hs[j * n + i] = v.x
			ss[j * n + i] = int(v.y) | (int(v.z) << 24)
	return {"h": hs, "s": ss}
