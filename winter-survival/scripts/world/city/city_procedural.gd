class_name CityProcedural
extends RefCounted
## Procedural city geometry of C0 (provisional art in code, PLAN C0 «Arte»; C1 replaces it with the urban kit):
##   * `building()`: a closed, cut-ready building per the city contract (ARQ v2 §9.7): `Base` (every floor a closed
##     volume with thick walls, one slab per floor, a partition and an open core: the plan the «corte urbano» shows),
##     `Roof` (roof slab, thick parapet, plant boxes, snow), `ShadowProxy` (closed box). Pieces at y = 0, vertex
##     colours (AO in COLOR.a) on the shared `world_vcol` + a `window` glass surface, which CityBuilding swaps for the
##     city materials. Used for the non-enterable podiums and, without the A1 art (the Web build), as the tower
##     fallback;
##   * `stair_mesh()`: the exterior stair up to a podium roof (the provisional mirador's access);
##   * `bridge_segment()`: one chunk of the provisional Puente de Hierro (deck on its profile, stone embankments,
##     a Warren truss over the ice, masonry piers, parapets) as mesh arrays built in the ChunkJob worker;
##   * `fallback_prop()`: a box stand-in for a missing A1 prop / car (Web build: the city .glb are not exported).
## Everything is deterministic (no RNG but WorldConst.hash64 of fixed ids).

const FOUNDATION := 0.3
const SKIRT := 1.2          # walls continue this far below the base (the base sits on the lowest corner)
const WALL_T := 0.25
const PARAPET := 1.1
const COL_SLAB := Color(0.66, 0.66, 0.64)
const COL_INNER := Color(0.74, 0.72, 0.68)
const COL_CORE := Color(0.40, 0.40, 0.42)
const COL_SNOW := Color(0.90, 0.93, 0.97)
const COL_STONE := Color(0.55, 0.53, 0.50)
const COL_IRON := Color(0.27, 0.28, 0.31)
const COL_ASPHALT := Color(0.66, 0.69, 0.74)   # the road bed under packed snow, like the terrain's road beds
const COL_KERB := Color(0.62, 0.62, 0.60)

static var _glass: StandardMaterial3D


## The `window` exception material the art exports (CityBuilding swaps it for window_city of the family).
static func glass_material() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.resource_name = "window"
		_glass.vertex_color_use_as_albedo = true
	return _glass


static func palette(style: String, h: int) -> Dictionary:
	var t := float(posmod(h, 97)) / 97.0
	match style:
		"glass":
			return {"wall": Color(0.46 + t * 0.08, 0.50 + t * 0.06, 0.56), "spandrel": Color(0.30, 0.33, 0.38), "band": true}
		"brick":
			return {"wall": Color(0.52 + t * 0.1, 0.33, 0.27), "spandrel": Color(0.44, 0.29, 0.24), "band": false}
		"ensanche":
			return {"wall": Color(0.78, 0.70 + t * 0.05, 0.58), "spandrel": Color(0.70, 0.62, 0.50), "band": false}
	return {"wall": Color(0.62 + t * 0.06, 0.62, 0.60), "spandrel": Color(0.52, 0.52, 0.51), "band": true}


# ------------------------------------------------------------------ cut-ready building (contract)
## Pieces of a closed box building (local space, origin = footprint centre at street level). Returns
## {"Base": ArrayMesh, "Shafts": [[floor_from, floor_to, ArrayMesh], …], "Roof": ArrayMesh, "ShadowProxy": ArrayMesh,
##  "roof_level": float, "top": float}. `podium_floors` floors go into Base, the rest in groups of 4 (Shaft_<n>).
## `opening` = [face, from, to] of a parapet gap on the roof (the stair landing), local metres along that face.
static func building(sx: float, sz: float, floors: int, ground_h: float, floor_h: float, style: String, seed_id: int,
		podium_floors: int = -1, opening: Array = []) -> Dictionary:
	var pal := palette(style, seed_id)
	var base_floors := floors if podium_floors < 0 else mini(floors, podium_floors)
	var out := {"Shafts": []}
	out["Base"] = _floors_mesh(sx, sz, 0, base_floors, ground_h, floor_h, pal, true)
	var f := base_floors
	while f < floors:
		var to := mini(f + 4, floors)
		(out["Shafts"] as Array).append([f, to - 1, _floors_mesh(sx, sz, f, to, ground_h, floor_h, pal, false)])
		f = to
	var top := level(floors, ground_h, floor_h)
	out["roof_level"] = top
	out["top"] = top + PARAPET
	out["Roof"] = _roof_mesh(sx, sz, top, pal, seed_id, opening)
	out["ShadowProxy"] = box_mesh(Vector3(0, (top + PARAPET) * 0.5, 0), Vector3(sx, top + PARAPET, sz))
	return out


## Walkable level of floor k (0 = ground floor at the foundation; the roof slab is floor `floors`).
static func level(k: int, ground_h: float, floor_h: float) -> float:
	return FOUNDATION if k <= 0 else ground_h + float(k - 1) * floor_h


static func _floors_mesh(sx: float, sz: float, f0: int, f1: int, gh: float, fh: float, pal: Dictionary, base: bool) -> ArrayMesh:
	var st := _st()
	var gl := _st()
	var hx := sx * 0.5
	var hz := sz * 0.5
	var wall: Color = pal["wall"]
	var spandrel: Color = pal["spandrel"]
	var t := WALL_T
	for k in range(f0, f1):
		var y0 := level(k, gh, fh) - (FOUNDATION + SKIRT if k == 0 else 0.0)
		var y1 := level(k + 1, gh, fh)
		var fl := level(k, gh, fh)
		var hgt := y1 - fl
		var sill := 0.9 if k > 0 else 0.5
		var win_top := hgt - 0.5
		_walls(st, hx, hz, y0, fl + sill, spandrel, 1.0)
		_walls(st, hx, hz, fl + win_top, y1, spandrel, 1.0)
		if bool(pal["band"]) or k == 0:
			_walls(gl, hx, hz, fl + sill, fl + win_top, Color(0.2, 0.25, 0.3), 1.0)
		else:
			_bays(st, gl, hx, hz, fl + sill, fl + win_top, wall)
		# inner face (plaster, sheltered), thick wall; slab top (the plan) + underside
		_walls(st, hx - t, hz - t, fl, y1 - 0.2, COL_INNER, 0.45, true)
		quad_h(st, hx - t, hz - t, fl, true, COL_SLAB, 0.3)
		if k > 0:
			quad_h(st, hx - t, hz - t, fl - 0.2, false, COL_SLAB, 0.3)
		# partition across the long axis + a stair / lift core (open top: reads black in the cut)
		if sx >= sz:
			_box_open(st, Vector3(0, fl, 0), Vector2(0.12, hz - t), y1 - 0.2 - fl, COL_INNER, 0.45)
			_box_open(st, Vector3(hx * 0.35, fl, 0), Vector2(2.0, 3.0), y1 - 0.2 - fl, COL_CORE, 0.3)
		else:
			_box_open(st, Vector3(0, fl, 0), Vector2(hx - t, 0.12), y1 - 0.2 - fl, COL_INNER, 0.45)
			_box_open(st, Vector3(0, fl, hz * 0.35), Vector2(3.0, 2.0), y1 - 0.2 - fl, COL_CORE, 0.3)
	return _commit(st, gl)


static func _roof_mesh(sx: float, sz: float, top: float, pal: Dictionary, seed_id: int, opening: Array) -> ArrayMesh:
	var st := _st()
	var hx := sx * 0.5
	var hz := sz * 0.5
	var wall: Color = pal["spandrel"]
	# roof slab (snowy: open sky, AO 1) + its underside at the ceiling of the last floor
	quad_h(st, hx, hz, top, true, Color(0.55, 0.56, 0.58), 1.0)
	quad_h(st, hx - WALL_T, hz - WALL_T, top - 0.2, false, COL_SLAB, 0.3)
	# parapet: outer faces from the slab to the coping, inner faces, coping; a gap where `opening` says
	var c := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
	var faces := ["n", "e", "s", "w"]
	for k in 4:
		var a: Vector2 = c[k]
		var b: Vector2 = c[(k + 1) % 4]
		var spans := [[0.0, a.distance_to(b)]]
		if not opening.is_empty() and str(opening[0]) == faces[k]:
			spans = _span_minus(a, b, faces[k], float(opening[1]), float(opening[2]))
		var d := (b - a).normalized()
		var inward := Vector2(-d.y, d.x)   # corners run counter-clockwise seen from above: left of a→b is inside
		var outn := Vector3(-inward.x, 0.0, -inward.y)
		for sp in spans:
			var p0: Vector2 = a + d * float(sp[0])
			var p1: Vector2 = a + d * float(sp[1])
			if p0.distance_to(p1) < 0.05:
				continue
			var i0 := p0 + inward * 0.3
			var i1 := p1 + inward * 0.3
			var yt := top + PARAPET
			_q(st, Vector3(p0.x, top - 0.2, p0.y), Vector3(p1.x, top - 0.2, p1.y), Vector3(p1.x, yt, p1.y), Vector3(p0.x, yt, p0.y), outn, wall, 1.0)
			_q(st, Vector3(i0.x, top, i0.y), Vector3(i1.x, top, i1.y), Vector3(i1.x, yt, i1.y), Vector3(i0.x, yt, i0.y), -outn, wall, 0.8)
			_q(st, Vector3(p0.x, yt, p0.y), Vector3(p1.x, yt, p1.y), Vector3(i1.x, yt, i1.y), Vector3(i0.x, yt, i0.y), Vector3.UP, COL_SNOW, 1.0)
			# jambs where the parapet stops at the gap
			for e in [p0, p1]:
				var ep: Vector2 = e
				if ep.distance_to(a) < 0.05 or ep.distance_to(b) < 0.05:
					continue
				var ei := ep + inward * 0.3
				var jn := Vector3(d.x, 0.0, d.y) * (-1.0 if ep == p1 else 1.0) * -1.0
				_q(st, Vector3(ep.x, top, ep.y), Vector3(ei.x, top, ei.y), Vector3(ei.x, yt, ei.y), Vector3(ep.x, yt, ep.y), jn, wall, 1.0)
	# plant boxes + a water tank, kept to the east / north ends (the mirador terrace is the west end)
	for i in 3:
		var h := WorldConst.hash64(seed_id, 77, i)
		var w := 1.5 + WorldConst.unit(h) * 2.0
		var d := 1.5 + WorldConst.unit(WorldConst.hash64(h, 1)) * 1.5
		var bx := hx * (0.35 + 0.45 * WorldConst.unit(WorldConst.hash64(h, 2)))
		var bz := (hz - 2.5) * (WorldConst.unit(WorldConst.hash64(h, 3)) * 2.0 - 1.0)
		block(st, Vector3(bx, top, bz), Vector3(w, 1.2 + WorldConst.unit(WorldConst.hash64(h, 4)) * 1.2, d), Color(0.5, 0.52, 0.55), COL_SNOW)
	return _commit(st, null)


## Parts of the parapet segment a→b (distances from a) left after removing the opening [from, to] (local metres
## along the face's axis: z for the w / e faces, x for the n / s faces).
static func _span_minus(a: Vector2, b: Vector2, face: String, from: float, to: float) -> Array:
	var length := a.distance_to(b)
	var d := (b - a) / length
	var along_z := face == "w" or face == "e"
	var q0 := Vector2(a.x, from) if along_z else Vector2(from, a.y)
	var q1 := Vector2(a.x, to) if along_z else Vector2(to, a.y)
	var t0 := clampf((q0 - a).dot(d), 0.0, length)
	var t1 := clampf((q1 - a).dot(d), 0.0, length)
	return [[0.0, minf(t0, t1)], [maxf(t0, t1), length]]


# ------------------------------------------------------------------ podium stair (mirador access)
## Exterior stair along a podium face: from street level at local `bottom` to the roof `rise` at local `top`
## (metres along the face, +z for the w/e faces), `width` wide, outside the wall. Local space of the podium.
## Returns {"mesh": ArrayMesh, "ramp": [centre, size, basis] (collider), "rail": [centre, size, basis], "landing": …}.
static func stair(face: String, half: Vector2, bottom: float, top: float, width: float, rise: float) -> Dictionary:
	var st := _st()
	var landing := CityLots.LANDING
	var run := absf(top - bottom) - landing
	var dir := signf(top - bottom)
	var steps := maxi(4, int(round(rise / 0.3)))
	var tread := run / float(steps)
	var riser := rise / float(steps)
	# the stair runs along local z on a w/e face (x outside the wall), along x on n/s faces
	var sidex := -1.0 if face == "w" else 1.0
	var along_z := face == "w" or face == "e"
	var wall_off := (half.x if along_z else half.y)
	var out_c := wall_off + width * 0.5 + 0.02
	var to_world := func(u: float, v: float, y: float) -> Vector3:
		# u = along the run (local z or x), v = outward offset from the wall
		if along_z:
			return Vector3(sidex * v, y, u)
		return Vector3(u, y, (-1.0 if face == "n" else 1.0) * v)
	var up := Vector3.UP
	var back := Vector3(0, 0, -dir) if along_z else Vector3(-dir, 0, 0)
	var outv := Vector3(sidex, 0, 0) if along_z else Vector3(0, 0, -1.0 if face == "n" else 1.0)
	for s in steps:
		var u0 := bottom + dir * tread * float(s)
		var u1 := u0 + dir * tread
		var y0 := riser * float(s)
		var y1 := y0 + riser
		var va := wall_off + 0.02
		var vb := wall_off + width
		# tread (snowy), riser, outer stringer
		_q(st, to_world.call(u0, va, y1), to_world.call(u0, vb, y1), to_world.call(u1, vb, y1), to_world.call(u1, va, y1), up, COL_SNOW, 1.0)
		_q(st, to_world.call(u0, va, y0), to_world.call(u0, vb, y0), to_world.call(u0, vb, y1), to_world.call(u0, va, y1), back, COL_STONE, 0.9)
		_q(st, to_world.call(u0, vb, y0 - 0.4), to_world.call(u1, vb, y1 - 0.4), to_world.call(u1, vb, y1), to_world.call(u0, vb, y0), outv, COL_STONE, 0.9)
	# landing slab at roof level + its outer face
	var ul0 := top - dir * landing
	_q(st, to_world.call(ul0, wall_off + 0.02, rise), to_world.call(ul0, wall_off + width, rise), to_world.call(top, wall_off + width, rise), to_world.call(top, wall_off + 0.02, rise), up, COL_SNOW, 1.0)
	_q(st, to_world.call(ul0, wall_off + width, rise - 0.4), to_world.call(top, wall_off + width, rise - 0.4), to_world.call(top, wall_off + width, rise), to_world.call(ul0, wall_off + width, rise), outv, COL_STONE, 0.9)
	# handrail on the outer edge: posts every 2 m + a rail
	var n_posts := int(ceil(absf(top - bottom) / 2.0)) + 1
	for i in n_posts:
		var u := bottom + dir * minf(absf(top - bottom), 2.0 * float(i))
		var y := rise * clampf(absf(u - bottom) / maxf(run, 0.1), 0.0, 1.0)
		var p: Vector3 = to_world.call(u, wall_off + width - 0.08, y)
		block(st, p, Vector3(0.08, 1.0, 0.08), COL_IRON, COL_IRON)
	# colliders: the ramp (rotated box along the run), the landing and the rail
	var slope := atan2(rise, run)
	var mid_u := bottom + dir * run * 0.5
	var ramp_len := sqrt(run * run + rise * rise)
	var bas := Basis(Vector3.RIGHT, -dir * slope) if along_z else Basis(Vector3.BACK, dir * slope)
	var rc: Vector3 = to_world.call(mid_u, out_c - 0.02, rise * 0.5 - 0.1)
	var ramp_size := Vector3(width, 0.2, ramp_len) if along_z else Vector3(ramp_len, 0.2, width)
	var land_c: Vector3 = to_world.call(top - dir * landing * 0.5, out_c, rise - 0.15)
	var land_size := Vector3(width, 0.3, landing) if along_z else Vector3(landing, 0.3, width)
	var rail_c: Vector3 = to_world.call(bottom + dir * absf(top - bottom) * 0.5, wall_off + width + 0.05, rise * 0.5 + 0.5)
	var rail_size := Vector3(0.1, rise + 1.0, absf(top - bottom)) if along_z else Vector3(absf(top - bottom), rise + 1.0, 0.1)
	return {"mesh": _commit(st, null), "ramp": [rc, ramp_size, bas], "landing": [land_c, land_size, Basis.IDENTITY],
		"rail": [rail_c, rail_size, Basis.IDENTITY]}


# ------------------------------------------------------------------ bridge (provisional Puente de Hierro)
## Mesh arrays (surface 0: stone / deck / snow, world_vcol; surface 1: iron truss, capsule-cut) and collider boxes of
## the bridge between x0 and x1 (world). `b` = the lot file's bridge record, `ends` = terrain at its ends.
## Colliders: [[centre, size, basis], …] in world space.
static func bridge_segment(b: Dictionary, x0: float, x1: float, ends: Vector2) -> Dictionary:
	var st := _st()
	var ir := _st()
	var zc := CityLots.cm(b["axis_z"])
	var hw := CityLots.cm(b["width"]) * 0.5
	var road := CityLots.cm(b["road"]) * 0.5
	var t0 := CityLots.cm(b["truss_from"])
	var t1 := CityLots.cm(b["truss_to"])
	var th := CityLots.cm(b["truss_h"])
	var par := CityLots.cm(b.get("parapet_h", 110))
	var thick := CityLots.cm(b.get("deck_thickness", 140))
	var bottom := -7.5
	var cols: Array = []
	# profile breakpoints inside the segment
	var xs: Array = [x0]
	for bx in [CityLots.cm(b["x_from"]) + CityLots.cm(b["ramp"]), CityLots.cm(b["x_to"]) - CityLots.cm(b["ramp"]), t0, t1]:
		if bx > x0 + 0.01 and bx < x1 - 0.01:
			xs.append(bx)
	xs.append(x1)
	xs.sort()
	for i in xs.size() - 1:
		var xa: float = xs[i]
		var xb: float = xs[i + 1]
		var ya := CityLots.deck_profile(xa, ends)
		var yb := CityLots.deck_profile(xb, ends)
		var truss := xa >= t0 - 0.01 and xb <= t1 + 0.01
		# deck: road (asphalt under packed snow) and the two sidewalks (snow), flush
		_q(st, Vector3(xa, ya, zc + road), Vector3(xb, yb, zc + road), Vector3(xb, yb, zc - road), Vector3(xa, ya, zc - road), Vector3.UP, COL_ASPHALT, 1.0)
		for sgn: float in [-1.0, 1.0]:
			var za := zc + sgn * road
			var zb := zc + sgn * hw
			_q(st, Vector3(xa, ya, za), Vector3(xb, yb, za), Vector3(xb, yb, zb), Vector3(xa, ya, zb), Vector3.UP, COL_SNOW, 1.0)
		# side faces: stone embankment down to below the ice, or the deck edge girder over the truss span
		var low_a := bottom if not truss else ya - thick
		var low_b := bottom if not truss else yb - thick
		var side_col := COL_STONE if not truss else COL_IRON
		_q(st, Vector3(xa, low_a, zc + hw), Vector3(xb, low_b, zc + hw), Vector3(xb, yb, zc + hw), Vector3(xa, ya, zc + hw), Vector3.BACK, side_col, 0.9)
		_q(st, Vector3(xa, low_a, zc - hw), Vector3(xb, low_b, zc - hw), Vector3(xb, yb, zc - hw), Vector3(xa, ya, zc - hw), Vector3.FORWARD, side_col, 0.9)
		if truss:
			_q(st, Vector3(xa, ya - thick, zc - hw), Vector3(xb, yb - thick, zc - hw), Vector3(xb, yb - thick, zc + hw), Vector3(xa, ya - thick, zc + hw), Vector3.DOWN, COL_IRON, 0.5)
		# parapets: stone on the embankments, an iron rail inside the truss
		for sgn: float in [-1.0, 1.0]:
			var zp := zc + sgn * (hw - 0.2)
			if truss:
				block_x(ir, xa, xb, ya + par - 0.1, yb + par - 0.1, zp, 0.08, 0.1, COL_IRON)
			else:
				block_x(st, xa, xb, ya, yb, zp, 0.4, par, COL_STONE)
		# colliders: the deck strip (a slab following the slope; embankments reach below the ice) + parapets
		var mid := Vector3((xa + xb) * 0.5, (ya + yb) * 0.5, zc)
		var slope := atan2(yb - ya, xb - xa)
		var length := sqrt((xb - xa) * (xb - xa) + (yb - ya) * (yb - ya))
		var bas := Basis(Vector3.BACK, slope)
		var depth := thick if truss else (mid.y - bottom)
		cols.append([mid + bas * Vector3(0, -depth * 0.5, 0), Vector3(length, depth, hw * 2.0), bas])
		for sgn: float in [-1.0, 1.0]:
			cols.append([mid + Vector3(0, par * 0.5, sgn * (hw - 0.2)), Vector3(length, par, 0.4), bas])
	# the truss (Warren, panels of 8 m) and portal bracing, over [t0, t1] ∩ [x0, x1]
	var ta := maxf(x0, t0)
	var tb := minf(x1, t1)
	if tb - ta > 0.01:
		var deck := CityLots.cm(b["deck_y"])
		var panel := 8.0
		for sgn: float in [-1.0, 1.0]:
			var zt := zc + sgn * (hw + 0.3)
			block_x(ir, ta, tb, deck - 0.2, deck - 0.2, zt, 0.5, 0.7, COL_IRON)                  # bottom chord
			block_x(ir, ta, tb, deck + th - 0.5, deck + th - 0.5, zt, 0.5, 0.6, COL_IRON)       # top chord
			var k0 := int(ceil((ta - t0) / panel))
			var k1 := int(floor((tb - t0) / panel))
			for k in range(k0, k1 + 1):
				var px := t0 + float(k) * panel
				block(ir, Vector3(px, deck - 0.2, zt), Vector3(0.35, th, 0.35), COL_IRON, COL_SNOW)   # post
				if k < k1 or px + panel <= tb + 0.01:
					var up := k % 2 == 0
					var xa2 := px
					var xb2 := minf(px + panel, tb)
					strut(ir, Vector3(xa2, deck + (0.2 if up else th - 0.6), zt), Vector3(xb2, deck + (th - 0.6 if up else 0.2), zt), 0.3, COL_IRON)
				if k % 2 == 0:
					# portal bracing overhead: a cross beam between the two top chords
					if sgn > 0.0:
						block(ir, Vector3(px, deck + th - 0.6, zc), Vector3(0.4, 0.5, hw * 2.0 + 0.6), COL_IRON, COL_SNOW)
			cols.append([Vector3((ta + tb) * 0.5, deck + th * 0.5, zt), Vector3(tb - ta, th, 0.6), Basis.IDENTITY])
		# piers (masonry) at the listed x
		for pxv in b.get("piers", []):
			var pxm := CityLots.cm(pxv)
			if pxm >= x0 and pxm < x1:
				block(st, Vector3(pxm, bottom, zc), Vector3(4.0, deck - CityLots.cm(b.get("deck_thickness", 140)) - bottom, hw * 2.0 + 2.0), COL_STONE, COL_SNOW)
				cols.append([Vector3(pxm, (deck + bottom) * 0.5, zc), Vector3(4.0, deck - bottom, hw * 2.0 + 2.0), Basis.IDENTITY])
	# abutment faces where the truss meets the embankments
	for ax in [t0, t1]:
		if ax >= x0 - 0.01 and ax <= x1 + 0.01:
			var y := CityLots.deck_profile(ax, ends)
			var facing := Vector3.RIGHT if ax == t0 else Vector3.LEFT
			_q(st, Vector3(ax, bottom, zc - hw), Vector3(ax, bottom, zc + hw), Vector3(ax, y, zc + hw), Vector3(ax, y, zc - hw), facing, COL_STONE, 0.8)
	return {"arrays": st.commit_to_arrays(), "iron": ir.commit_to_arrays(), "cols": cols}


# ------------------------------------------------------------------ fallbacks (no A1 art: the Web build)
## A stand-in for a missing A1 model: a vehicle-like double box, a pole or a box of the model's size, vertex
## coloured (surface 0) — one mesh per model, cached by the caller.
static func fallback_prop(model: String, size: Vector3, colour: Color, vehicle: bool) -> ArrayMesh:
	var st := _st()
	if vehicle:
		block(st, Vector3(0, 0.15, 0), Vector3(size.x, size.y * 0.55, size.z), colour, COL_SNOW)
		block(st, Vector3(0, 0.15 + size.y * 0.55, -size.z * 0.08), Vector3(size.x * 0.86, size.y * 0.4, size.z * 0.5), colour.darkened(0.25), COL_SNOW)
	elif size.x < 0.4 and size.z < 0.4 and size.y > 2.0:
		block(st, Vector3.ZERO, Vector3(0.22, size.y, 0.22), colour, colour)
		block(st, Vector3(0, size.y - 0.2, 1.1), Vector3(0.14, 0.14, 2.3), colour, colour)
	else:
		block(st, Vector3.ZERO, size, colour, COL_SNOW)
	return _commit(st, null)


# ------------------------------------------------------------------ geometry helpers
static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat normals (the default group 0 averages shared corners)
	return st


## ArrayMesh with the structure surface (shared world_vcol) and, when `gl` has triangles, the glass one.
static func _commit(st: SurfaceTool, gl: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	var mesh := st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, Assets.get_shared_material())
	if gl != null:
		gl.generate_normals()
		var n0 := mesh.get_surface_count()
		gl.commit(mesh)
		if mesh.get_surface_count() > n0:
			mesh.surface_set_material(n0, glass_material())
	return mesh


## A closed box mesh (12 triangles) of `size` centred at `centre` (the ShadowProxy / colliders' visual).
static func box_mesh(centre: Vector3, size: Vector3) -> ArrayMesh:
	var bm := BoxMesh.new()
	bm.size = size
	var arr := bm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] += centre
	arr[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, Assets.get_shared_material())
	return am


static func _bays(st: SurfaceTool, gl: SurfaceTool, hx: float, hz: float, y0: float, y1: float, col: Color) -> void:
	var c := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
	for k in 4:
		var a: Vector2 = c[k]
		var b: Vector2 = c[(k + 1) % 4]
		var length := a.distance_to(b)
		var n := maxi(1, int(round(length / 2.4)))
		var bay := length / float(n)
		var dir := (b - a) / length
		for i in n:
			var s0 := a + dir * (bay * i)
			var s1 := s0 + dir * 0.5
			var s2 := s0 + dir * (bay - 0.5)
			var s3 := s0 + dir * bay
			_wall_quad(st, s0, s1, y0, y1, col, 1.0)
			_wall_quad(gl, s1, s2, y0, y1, Color(0.2, 0.25, 0.3), 1.0)
			_wall_quad(st, s2, s3, y0, y1, col, 1.0)


static func _walls(st: SurfaceTool, hx: float, hz: float, y0: float, y1: float, col: Color, ao: float, inward: bool = false) -> void:
	var c := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
	for k in 4:
		var a: Vector2 = c[k]
		var b: Vector2 = c[(k + 1) % 4]
		if inward:
			_wall_quad(st, b, a, y0, y1, col, ao)
		else:
			_wall_quad(st, a, b, y0, y1, col, ao)


## Outward-facing wall quad from a to b (counter-clockwise seen from outside).
static func _wall_quad(st: SurfaceTool, a: Vector2, b: Vector2, y0: float, y1: float, col: Color, ao: float) -> void:
	_quad(st, Vector3(b.x, y0, b.y), Vector3(a.x, y0, a.y), Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), col, ao)


static func _box_open(st: SurfaceTool, centre: Vector3, half: Vector2, h: float, col: Color, ao: float) -> void:
	var c := [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]
	for k in 4:
		var a: Vector2 = c[k] + Vector2(centre.x, centre.z)
		var b: Vector2 = c[(k + 1) % 4] + Vector2(centre.x, centre.z)
		_wall_quad(st, a, b, centre.y, centre.y + h, col, ao)


static func quad_h(st: SurfaceTool, hx: float, hz: float, y: float, up: bool, col: Color, ao: float) -> void:
	if up:
		_quad(st, Vector3(-hx, y, hz), Vector3(hx, y, hz), Vector3(hx, y, -hz), Vector3(-hx, y, -hz), col, ao)
	else:
		_quad(st, Vector3(-hx, y, -hz), Vector3(hx, y, -hz), Vector3(hx, y, hz), Vector3(-hx, y, hz), col, ao)


## Quad a-b-c-d wound like the bench's (_quad): visible from the side where a→b→c turns clockwise.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, ao: float) -> void:
	var lin := col.srgb_to_linear()
	lin.a = ao
	for v in [a, c, b, a, d, c]:
		st.set_color(lin)
		st.add_vertex(v)


## Quad a-b-c-d (a closed loop, either winding) made visible from the side `facing` points to.
static func _q(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3, col: Color, ao: float) -> void:
	if (b - a).cross(c - a).dot(facing) >= 0.0:
		_quad(st, a, b, c, d, col, ao)
	else:
		_quad(st, a, d, c, b, col, ao)


## Closed box sitting on `base` (centre of its bottom face): sides + top (top colour `top_col`).
static func block(st: SurfaceTool, base: Vector3, size: Vector3, col: Color, top_col: Color) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var c := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
	for k in 4:
		var a: Vector2 = c[k] + Vector2(base.x, base.z)
		var b: Vector2 = c[(k + 1) % 4] + Vector2(base.x, base.z)
		_wall_quad(st, a, b, base.y, base.y + size.y, col, 1.0)
	var y := base.y + size.y
	_quad(st, Vector3(base.x - hx, y, base.z + hz), Vector3(base.x + hx, y, base.z + hz), Vector3(base.x + hx, y, base.z - hz), Vector3(base.x - hx, y, base.z - hz), top_col, 1.0)


## A beam along x from (xa, ya) to (xb, yb) at z, `w` wide (z) and `h` tall, on top of the line (sloped ends).
static func block_x(st: SurfaceTool, xa: float, xb: float, ya: float, yb: float, z: float, w: float, h: float, col: Color) -> void:
	var z0 := z - w * 0.5
	var z1 := z + w * 0.5
	_q(st, Vector3(xa, ya, z1), Vector3(xb, yb, z1), Vector3(xb, yb + h, z1), Vector3(xa, ya + h, z1), Vector3.BACK, col, 1.0)
	_q(st, Vector3(xa, ya, z0), Vector3(xb, yb, z0), Vector3(xb, yb + h, z0), Vector3(xa, ya + h, z0), Vector3.FORWARD, col, 1.0)
	_q(st, Vector3(xa, ya + h, z1), Vector3(xb, yb + h, z1), Vector3(xb, yb + h, z0), Vector3(xa, ya + h, z0), Vector3.UP, COL_SNOW, 1.0)
	_q(st, Vector3(xa, ya, z0), Vector3(xa, ya, z1), Vector3(xa, ya + h, z1), Vector3(xa, ya + h, z0), Vector3.LEFT, col, 1.0)
	_q(st, Vector3(xb, yb, z0), Vector3(xb, yb, z1), Vector3(xb, yb + h, z1), Vector3(xb, yb + h, z0), Vector3.RIGHT, col, 1.0)


## A square-section strut between two points (truss diagonals), `s` thick.
static func strut(st: SurfaceTool, a: Vector3, b: Vector3, s: float, col: Color) -> void:
	var d := (b - a).normalized()
	var side := Vector3(0, 0, 1)
	var up := d.cross(side).normalized() * s * 0.5
	var sz := side * s * 0.5
	var p := [a - up - sz, a + up - sz, a + up + sz, a - up + sz]
	var q := [b - up - sz, b + up - sz, b + up + sz, b - up + sz]
	for k in 4:
		var k1 := (k + 1) % 4
		_quad(st, p[k], q[k], q[k1], p[k1], col, 1.0)
		_quad(st, p[k], p[k1], q[k1], q[k], col, 1.0)
