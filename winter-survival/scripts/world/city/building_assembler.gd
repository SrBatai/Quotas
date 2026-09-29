class_name BuildingAssembler
extends RefCounted
## City building families of Altavega (C1, doc 09 §4.5 «Familias de edificios», PLAN C26: the generator never
## assembles modules at run time, it stacks already-merged floors). A family is a grammar — zócalo (ground floor) +
## planta tipo × n + coronación — applied to a footprint outline whose edges are typed (street front, patio back,
## party wall, chaflán); a variant fixes the outline (frontage, depth, corner cut) and the features; a lot picks
## (family, variant, floors, palette, enterable ground floor). Everything is built procedurally as cut-ready
## geometry per the city building contract (ARQ v2 §9.7): closed volume, thick outer walls with their inner faces,
## ONE SLAB PER FLOOR at base + ground_h + (k − 1)·floor_h, a partition and an open core per floor (the plan the
## «corte urbano» shows), vertex colours with AO in COLOR.a, a `window` glass surface (→ window_city), a
## ShadowProxy prism (the only caster).
##   casco     casa del casco viejo: 3–4 floors, 6–12 m frontage, render + stone base, balcony doors with iron
##             balconies and shutters, eaves cornice, a tiled pitched roof; variant 4 = soportal (arcaded ground floor)
##   ensanche  edificio de ensanche: 5–8 floors, 4.3 m commercial ground floor (shopfronts, metal shutters,
##             awnings), a continuous balcony on the principal floor, balconies per bay, cornice, set-back ático
##             with its terrace; variant 4 = the chaflán corner (the block corner cut at 45°)
##   bloque    bloque de la barriada: 8–14 floors, 40–60 m slabs of brick with terrace bands, stair-core strips,
##             lift houses and water tanks on the roof; variant 3 = the point block (24 × 24 m)
## Towers (Las Torres) come from TowerAssembler (A1 art) and the hero towers from HeroTower.
## An enterable ground floor (`ent`) opens a door in the street facade and fits a shop / dwelling (counter, shelves,
## a back room) with loot spawns; its door is a KitDoor (M6a) with a deterministic wid, its containers come from
## LootSpawns (M5): nothing is replicated but deltas.
## Pure data generation (`data()`) is thread-safe and cached per key (family, variant, floors, palette, ent): the
## ChunkJob workers build what a chunk needs; the main thread only turns cached arrays into ArrayMesh (once per key).

const FOUNDATION := 0.3
const WALL_T := 0.28
const PARAPET := 1.1
const GLASS_RECESS := 0.14
const GLASS := Color(0.20, 0.25, 0.30)
const COL_SLAB := Color(0.66, 0.66, 0.64)
const COL_INNER := Color(0.76, 0.74, 0.70)
const COL_CORE := Color(0.36, 0.36, 0.38)
const COL_IRON := Color(0.17, 0.18, 0.20)
const COL_SNOW := Color(0.90, 0.93, 0.97)
const COL_ROOF_FLAT := Color(0.52, 0.53, 0.55)
const COL_REVEAL := Color(0.42, 0.40, 0.38)
const COL_SHUTTER_METAL := Color(0.50, 0.52, 0.54)
const COL_WOOD := Color(0.40, 0.29, 0.20)

## Facade edge types (outline edges): street front, patio / garden back, party wall (medianera, blank), chaflán.
enum Edge { FRONT, BACK, SIDE, CHAMFER, END }

## Families: ground_h / floor_h (the struct material grids: 3.3/3.0 = world_vcol_struct.tres, 4.3/3.0 = _4m),
## depth, floors range, skirt (walls continue below the base on sloping lots), bay (m) and the variants.
const FAMILIES := {
	"casco": {"ground_h": 3.3, "floor_h": 3.0, "depth": 11.0, "floors": [3, 4], "skirt": 3.0, "bay": 2.6, "palettes": 6,
		"variants": [{"w": 6.0}, {"w": 8.0}, {"w": 10.0}, {"w": 12.0}, {"w": 10.0, "arcade": true}]},
	"ensanche": {"ground_h": 4.3, "floor_h": 3.0, "depth": 15.0, "floors": [5, 8], "skirt": 2.6, "bay": 3.0, "palettes": 5,
		"variants": [{"w": 15.0}, {"w": 18.0}, {"w": 21.0}, {"w": 24.0}, {"w": 16.5, "d": 16.5, "corner": 8.5}]},
	"bloque": {"ground_h": 3.3, "floor_h": 3.0, "depth": 11.0, "floors": [8, 14], "skirt": 2.6, "bay": 3.2, "palettes": 4,
		"variants": [{"w": 40.0}, {"w": 50.0}, {"w": 60.0}, {"w": 24.0, "d": 24.0, "point": true}]},
	## Control del Puerto (and later checkpoints): a concrete guard hut (garita) and a barrack (barracón); freestanding.
	"caseta": {"ground_h": 3.3, "floor_h": 3.0, "depth": 3.4, "floors": [1, 1], "skirt": 1.2, "bay": 1.7, "palettes": 2,
		"variants": [{"w": 3.4}, {"w": 12.0, "d": 6.0}]},
}
## sRGB palettes per family: [wall, trim (base / cornice / bands), shutters / ironwork accent, roof].
const PALETTES := {
	"casco": [
		[Color("#C9A06A"), Color("#8E8578"), Color("#3E5A44"), Color("#9A5A44")],
		[Color("#E0D2B0"), Color("#8A8276"), Color("#5C4030"), Color("#94553F")],
		[Color("#E6E3DA"), Color("#9A948A"), Color("#4A5A6A"), Color("#A0604A")],
		[Color("#C98E7E"), Color("#86796E"), Color("#3E5A44"), Color("#8E4E3C")],
		[Color("#A3AEB6"), Color("#7E7A74"), Color("#5C4030"), Color("#9A5A44")],
		[Color("#D8B860"), Color("#8E8578"), Color("#4A5A6A"), Color("#96583F")],
	],
	"ensanche": [
		[Color("#CDBFA3"), Color("#8A8276"), Color("#2E3033"), Color("#6E6A62")],
		[Color("#C8A878"), Color("#8E8274"), Color("#2A2C30"), Color("#6A6660")],
		[Color("#B4B0A8"), Color("#7E7C78"), Color("#303236"), Color("#6C6A66")],
		[Color("#CFB2A2"), Color("#8E7E74"), Color("#2E3033"), Color("#6E6660")],
		[Color("#D6CCB6"), Color("#948C7E"), Color("#34302C"), Color("#706A62")],
	],
	"bloque": [
		[Color("#9A5A48"), Color("#B8B4AC"), Color("#3A3C40"), Color("#5E5E5E")],
		[Color("#A8705A"), Color("#BDB8AE"), Color("#3A3C40"), Color("#5E5E5E")],
		[Color("#7E5A4E"), Color("#AEAAA2"), Color("#34363A"), Color("#5A5A5A")],
		[Color("#B8A68C"), Color("#8E8A84"), Color("#3A3C40"), Color("#5E5E5E")],
	],
	"caseta": [
		[Color("#8C8F7A"), Color("#6E705E"), Color("#4A4E3E"), Color("#5E5E58")],
		[Color("#A8A8A0"), Color("#7A7A74"), Color("#4A4E3E"), Color("#5E5E5E")],
	],
}
## Loot tables of an enterable ground floor, by family (a lot hash picks one).
const SHOP_TABLES := {
	"casco": [&"house_kitchen", &"house", &"pharmacy"],
	"ensanche": [&"house", &"pharmacy", &"gas_station", &"house_kitchen"],
	"bloque": [&"house_kitchen", &"house"],
	"caseta": [&"military", &"military", &"police"],
}

static var _cache: Dictionary = {}      # key -> data (pure arrays)
static var _meshes: Dictionary = {}     # key -> {"Base": ArrayMesh, "ShadowProxy": ArrayMesh, "Door": ArrayMesh}
static var _lock := Mutex.new()
static var stats: Dictionary = {"built": 0, "usec": 0, "meshes": 0}


# ------------------------------------------------------------------ specs (pure)
static func has_family(fam: String) -> bool:
	return FAMILIES.has(fam)


static func variant_count(fam: String) -> int:
	return (FAMILIES[fam]["variants"] as Array).size()


## Merged family + variant parameters: w (frontage, x), d (depth, z), ground_h, floor_h, skirt, bay, features.
static func spec(fam: String, vi: int) -> Dictionary:
	var f: Dictionary = FAMILIES[fam]
	var v: Dictionary = (f["variants"] as Array)[clampi(vi, 0, (f["variants"] as Array).size() - 1)]
	var s := {"fam": fam, "vi": vi, "w": float(v["w"]), "d": float(v.get("d", f["depth"])), "ground_h": float(f["ground_h"]),
		"floor_h": float(f["floor_h"]), "skirt": float(f["skirt"]), "bay": float(f["bay"]), "floors": f["floors"]}
	for k in v:
		if not s.has(k):
			s[k] = v[k]
	return s


## Footprint size (m) of a variant in its local frame (x = frontage, z = depth).
static func size_of(fam: String, vi: int) -> Vector2:
	var s := spec(fam, vi)
	return Vector2(float(s["w"]), float(s["d"]))


static func level(k: int, gh: float, fh: float) -> float:
	return FOUNDATION if k <= 0 else gh + float(k - 1) * fh


## Roof slab level (m over the base): the top of the last floor.
static func roof_level(fam: String, vi: int, floors: int) -> float:
	var s := spec(fam, vi)
	return level(floors, float(s["ground_h"]), float(s["floor_h"]))


## Highest point (m over the base): parapet / ridge / ático.
static func top(fam: String, vi: int, floors: int) -> float:
	var r := roof_level(fam, vi, floors)
	if fam == "casco":
		return r + 0.3 + float(spec(fam, vi)["d"]) * 0.5 * tan(deg_to_rad(28.0)) + 0.2
	return r + parapet(fam) + (2.6 if fam == "bloque" else 0.0)


static func parapet(fam: String) -> float:
	return 0.5 if fam == "caseta" else PARAPET


## Footprint outline (plan, local, counter-clockwise seen from above: NW → NE → SE → SW, front = +z) and the edge
## types (edge i goes from p[i] to p[i + 1]).
static func outline(s: Dictionary) -> Array:
	var hw := float(s["w"]) * 0.5
	var hd := float(s["d"]) * 0.5
	var fam := str(s["fam"])
	var street_back := fam == "bloque" or fam == "caseta"   # freestanding: the back faces a street / the park too
	if s.has("corner"):
		var ch := float(s["corner"])
		return [PackedVector2Array([Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd - ch), Vector2(hw - ch, hd), Vector2(-hw, hd)]),
			[Edge.SIDE, Edge.FRONT, Edge.CHAMFER, Edge.FRONT, Edge.SIDE]]
	var sides := Edge.END if (street_back or bool(s.get("point", false))) else Edge.SIDE
	return [PackedVector2Array([Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]),
		[Edge.FRONT if street_back else Edge.BACK, sides, Edge.FRONT, sides]]


static func key(fam: String, vi: int, floors: int, pal: int, ent: bool) -> String:
	return "%s|%d|%d|%d|%d" % [fam, vi, floors, pal, 1 if ent else 0]


# ------------------------------------------------------------------ data (pure, cached, thread-safe)
## Everything a lot needs, from cache or built now (any thread): {"struct": arrays, "glass": arrays, "proxy": arrays,
## "door": arrays, "door_at": [hinge x, z, width, yaw], "spawns": [[Vector3, yaw], …], "roof_level", "top",
## "ground_h", "floor_h", "tris"}.
static func data(fam: String, vi: int, floors: int, pal: int, ent: bool) -> Dictionary:
	var k := key(fam, vi, floors, pal, ent)
	_lock.lock()
	var d: Dictionary = _cache.get(k, {})
	_lock.unlock()
	if not d.is_empty():
		return d
	var t0 := Time.get_ticks_usec()
	d = _build(fam, vi, floors, pal, ent)
	_lock.lock()
	if not _cache.has(k):
		_cache[k] = d
		stats["built"] = int(stats["built"]) + 1
		stats["usec"] = int(stats["usec"]) + Time.get_ticks_usec() - t0
	else:
		d = _cache[k]
	_lock.unlock()
	return d


static func clear_cache() -> void:
	_lock.lock()
	_cache.clear()
	_lock.unlock()
	_meshes.clear()
	_partial.clear()


## Are the ArrayMeshes of this key made already (CityChunk: a new key gets steps of its own before its building)?
static func has_meshes(fam: String, vi: int, floors: int, pal: int, ent: bool) -> bool:
	return _meshes.has(key(fam, vi, floors, pal, ent))


static var _partial: Dictionary = {}    # key -> {"stage": int, "Base": ArrayMesh} (meshes made in stages)


## One stage of the ArrayMeshes of a key (CityChunk's "mesh" steps; each ≤ ~1 ms): 0 the structure surface of
## "Base", 1 its glass surface, 2 "ShadowProxy" and "Door" (then cached). True once the key is complete.
static func mesh_stage(fam: String, vi: int, floors: int, pal: int, ent: bool) -> bool:
	var k := key(fam, vi, floors, pal, ent)
	if _meshes.has(k):
		return true
	var d := data(fam, vi, floors, pal, ent)
	var pm: Dictionary = _partial.get(k, {"stage": 0, "Base": ArrayMesh.new()})
	var base: ArrayMesh = pm["Base"]
	match int(pm["stage"]):
		0:
			if not (d["struct"] as Array).is_empty():
				base.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, d["struct"])
				base.surface_set_material(base.get_surface_count() - 1, Assets.get_shared_material())
		1:
			if not (d["glass"] as Array).is_empty():
				base.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, d["glass"])
				base.surface_set_material(base.get_surface_count() - 1, CityProcedural.glass_material())
		_:
			var proxy := ArrayMesh.new()
			proxy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, d["proxy"])
			proxy.surface_set_material(0, Assets.get_shared_material())
			var out := {"Base": base, "ShadowProxy": proxy, "Door": null}
			if not (d["door"] as Array).is_empty():
				var dm := ArrayMesh.new()
				dm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, d["door"])
				dm.surface_set_material(0, Assets.get_shared_material())
				out["Door"] = dm
			_meshes[k] = out
			_partial.erase(k)
			stats["meshes"] = int(stats["meshes"]) + 1
			return true
	pm["stage"] = int(pm["stage"]) + 1
	_partial[k] = pm
	return false


## ArrayMeshes of a key (main thread; cached): "Base" (struct + glass), "ShadowProxy", "Door" (the leaf, or null).
static func meshes(fam: String, vi: int, floors: int, pal: int, ent: bool) -> Dictionary:
	var k := key(fam, vi, floors, pal, ent)
	if not _meshes.has(k):
		while not mesh_stage(fam, vi, floors, pal, ent):
			pass
	return _meshes[k]


# ------------------------------------------------------------------ colliders (pure; server and clients)
## Collider shapes of a lot, local space of its root: [[centre, size, basis, kind]] (kind "box"; "hull" = [points, …]).
## A closed building is one prism of its outline up to the roof (the chaflán keeps its sidewalk); an enterable ground
## floor is hollow: its walls with the door gap, the slab, the counter, the back partition, a ramp at the door, and
## the closed volume above the ground floor ceiling.
static func colliders(fam: String, vi: int, floors: int, ent: bool) -> Array:
	var s := spec(fam, vi)
	var ol: Array = outline(s)
	var pts: PackedVector2Array = ol[0]
	var gh := float(s["ground_h"])
	var fh := float(s["floor_h"])
	var roof := level(floors, gh, fh)
	var y_top := roof if fam == "casco" else roof + parapet(fam)
	var skirt := float(s["skirt"])
	var out: Array = []
	if not ent:
		out.append(_hull_rec(pts, -skirt, y_top))
		return out
	var ceil_y := level(1, gh, fh) - 0.2
	out.append(_hull_rec(pts, ceil_y, y_top))
	# floor slab (walkable at FOUNDATION) and the walls of the ground floor, with the door gap on the front
	var hw := float(s["w"]) * 0.5
	var hd := float(s["d"]) * 0.5
	out.append([Vector3(0, (FOUNDATION - skirt) * 0.5, 0), Vector3(hw * 2.0 - 0.2, FOUNDATION + skirt, hd * 2.0 - 0.2), Basis.IDENTITY, "box"])
	var door := door_spot(s)
	var wy := (ceil_y + FOUNDATION) * 0.5
	var wh := ceil_y - FOUNDATION
	# front wall (+z) split around the door
	var dx0 := float(door[0])
	var dx1 := dx0 + float(door[2])
	var fz := hd - WALL_T * 0.5
	for span in [[-hw, dx0], [dx1, hw - (float(s["corner"]) if s.has("corner") else 0.0)]]:
		var a := float(span[0])
		var b := float(span[1])
		if b - a > 0.05:
			out.append([Vector3((a + b) * 0.5, wy, fz), Vector3(b - a, wh, WALL_T), Basis.IDENTITY, "box"])
	out.append([Vector3(0, wy, -hd + WALL_T * 0.5), Vector3(hw * 2.0, wh, WALL_T), Basis.IDENTITY, "box"])
	out.append([Vector3(-hw + WALL_T * 0.5, wy, 0), Vector3(WALL_T, wh, hd * 2.0), Basis.IDENTITY, "box"])
	var ex := hd * 2.0 - (float(s["corner"]) if s.has("corner") else 0.0)
	out.append([Vector3(hw - WALL_T * 0.5, wy, -hd + ex * 0.5), Vector3(WALL_T, wh, ex), Basis.IDENTITY, "box"])
	if s.has("corner"):
		var ch := float(s["corner"])
		var c0 := Vector2(hw, hd - ch)
		var c1 := Vector2(hw - ch, hd)
		var mid := (c0 + c1) * 0.5
		var ln := c0.distance_to(c1)
		var dir := (c1 - c0).normalized()
		var inward := Vector2(-1, -1).normalized()
		var cc := mid + inward * WALL_T * 0.5
		out.append([Vector3(cc.x, wy, cc.y), Vector3(ln, wh, WALL_T), Basis(Vector3.UP, -atan2(dir.y, dir.x)), "box"])
	# interior: back room partition (a doorway at x ∈ [0, 1.2]), counter (not in the small huts)
	if _shop(s):
		var pz := _partition_z(s)
		var px0 := -hw + WALL_T
		var px1 := hw - WALL_T
		out.append([Vector3(px0 * 0.5, wy, pz), Vector3(-px0, wh, 0.14), Basis.IDENTITY, "box"])
		out.append([Vector3((1.2 + px1) * 0.5, wy, pz), Vector3(maxf(px1 - 1.2, 0.1), wh, 0.14), Basis.IDENTITY, "box"])
	var counter: Array = _counter(s)
	out.append([counter[0] + Vector3(0, float((counter[1] as Vector3).y) * 0.5, 0), counter[1], Basis.IDENTITY, "box"])
	# entrance ramp from the street (up to 0.5 m below the base on a slope) to the slab
	var rz := hd + 0.45
	var ramp_len := 1.0
	var rise := FOUNDATION + 0.35
	var ang := atan2(rise, ramp_len)
	out.append([Vector3(dx0 + float(door[2]) * 0.5, FOUNDATION - rise * 0.5 - 0.1, rz), Vector3(float(door[2]) + 0.6, 0.2, sqrt(ramp_len * ramp_len + rise * rise)),
		Basis(Vector3.RIGHT, ang), "box"])
	return out


static func _hull_rec(pts: PackedVector2Array, y0: float, y1: float) -> Array:
	var hull := PackedVector3Array()
	for p in pts:
		hull.append(Vector3(p.x, y0, p.y))
		hull.append(Vector3(p.x, y1, p.y))
	if pts.size() == 4:
		var bb := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			bb = bb.expand(p)
		var c := bb.get_center()
		return [Vector3(c.x, (y0 + y1) * 0.5, c.y), Vector3(bb.size.x, y1 - y0, bb.size.y), Basis.IDENTITY, "box"]
	return [Vector3.ZERO, Vector3.ZERO, Basis.IDENTITY, "hull", hull]


## Door of an enterable ground floor on the street facade: [hinge x (left jamb), z (facade), width, bay index].
static func door_spot(s: Dictionary) -> Array:
	var hw := float(s["w"]) * 0.5
	var hd := float(s["d"]) * 0.5
	var width := 1.2
	var x0 := -width * 0.5 - (hw * 0.35 if float(s["w"]) >= 14.0 else 0.0)
	if s.has("corner"):
		x0 = -hw + 3.0
	return [x0, hd, width, 0]


## A shop / dwelling layout (partition + counter) fits the ground floor (not the guard huts).
static func _shop(s: Dictionary) -> bool:
	return str(s["fam"]) != "caseta"


static func _partition_z(s: Dictionary) -> float:
	return float(s["d"]) * 0.5 - minf(float(s["d"]) * 0.62, 8.0)


## Shop counter: [bottom centre, size] (local).
static func _counter(s: Dictionary) -> Array:
	if not _shop(s):
		return [Vector3(0.0, FOUNDATION, -float(s["d"]) * 0.5 + WALL_T + 0.45), Vector3(minf(float(s["w"]) - 1.2, 1.6), 0.8, 0.7)]
	var hw := float(s["w"]) * 0.5
	var hd := float(s["d"]) * 0.5
	var pz := _partition_z(s)
	var zc := pz + (hd - pz) * 0.35
	var len := minf(float(s["w"]) * 0.35, 3.2)
	return [Vector3(hw - WALL_T - 0.8 - len * 0.5 - (float(s["corner"]) if s.has("corner") else 0.0) * 0.5, FOUNDATION, zc), Vector3(len, 0.95, 0.6)]


## Loot spawn points of an enterable ground floor: [[position (local, on the floor), yaw]].
static func spawns(s: Dictionary) -> Array:
	var hw := float(s["w"]) * 0.5
	var hd := float(s["d"]) * 0.5
	var pz := _partition_z(s)
	var ct: Array = _counter(s)
	var cpos: Vector3 = ct[0]
	var out: Array = []
	if not _shop(s):
		out.append([Vector3(-hw + WALL_T + 0.5, FOUNDATION, -hd + WALL_T + 0.45), 0.0])
		if float(s["w"]) >= 6.0:
			out.append([Vector3(hw - WALL_T - 0.5, FOUNDATION, -hd + WALL_T + 0.45), 0.0])
			out.append([Vector3(-hw + WALL_T + 0.5, FOUNDATION, 0.0), PI * 0.5])
		return out
	out.append([Vector3(cpos.x, FOUNDATION, cpos.z - 0.9), PI])                         # behind the counter
	out.append([Vector3(-hw + WALL_T + 0.55, FOUNDATION, pz - 1.4), PI * 0.5])          # back room, against the wall
	if float(s["w"]) >= 12.0:
		out.append([Vector3(-hw + WALL_T + 0.55, FOUNDATION, (pz + hd) * 0.5), PI * 0.5])   # shop floor, side wall
	return out


# ------------------------------------------------------------------ geometry
static func _build(fam: String, vi: int, floors: int, pal_i: int, ent: bool) -> Dictionary:
	var s := spec(fam, vi)
	var pals: Array = PALETTES[fam]
	var pal: Array = pals[posmod(pal_i, pals.size())]
	var m := CityMesh.new()
	var g := CityMesh.new()
	var ol: Array = outline(s)
	var pts: PackedVector2Array = ol[0]
	var types: Array = ol[1]
	var gh := float(s["ground_h"])
	var fh := float(s["floor_h"])
	var skirt := float(s["skirt"])
	var n := pts.size()
	var atico := fam == "ensanche" and floors >= 5
	var inner := _inset(pts, WALL_T)
	var at_pts := _inset_typed(pts, types, 2.0) if atico else pts
	var at_inner := _inset(at_pts, WALL_T) if atico else inner
	var door := door_spot(s) if ent else []
	for k in floors:
		var y0 := level(k, gh, fh)
		var y1 := level(k + 1, gh, fh)
		var wb := y0 - (FOUNDATION + skirt if k == 0 else 0.0)
		var is_atico := atico and k == floors - 1
		var opts: PackedVector2Array = at_pts if is_atico else pts
		var ipts: PackedVector2Array = at_inner if is_atico else inner
		for e in n:
			var a := opts[e]
			var b := opts[(e + 1) % n]
			var o := _out_normal(a, b)
			_facade_band(m, g, s, pal, int(types[e]), a, b, o, k, wb, y0, y1, floors, door if (ent and k == 0 and e == _door_edge(types)) else [])
		# inner faces of the outer walls (sheltered), the slab (the plan) and its underside, partition + core
		for e in n:
			var ia := ipts[e]
			var ib := ipts[(e + 1) % n]
			m.wall(ib, ia, y0, y1 - 0.2, -_out_normal(ia, ib), COL_INNER, 0.45)
		m.floor_poly(ipts, y0, true, COL_SLAB, 0.3)
		if k > 0:
			m.floor_poly(ipts, y0 - 0.2, false, COL_SLAB, 0.3)
		_interior(m, s, ipts, k, y0, y1, ent)
	# ground-floor ceiling underside and the roof
	var roof := level(floors, gh, fh)
	m.floor_poly(at_inner if atico else inner, roof - 0.2, false, COL_SLAB, 0.3)
	if atico:
		_terrace(m, s, pal, pts, at_pts, types, level(floors - 1, gh, fh))
	match fam:
		"casco":
			_pitched_roof(m, s, pal, pts, roof)
		_:
			_flat_roof(m, s, pal, at_pts if atico else pts, roof, fam == "bloque", floors)
	var t := top(fam, vi, floors)
	var proxy := CityMesh.new()
	_prism(proxy, pts, -skirt, t)
	var dm := CityMesh.new()
	var door_at: Array = []
	if ent:
		# the door leaf: hinge at the node origin (building base, y = 0), panel from the slab up (KitDoor's frame)
		var dw := float(door[2])
		dm.box(Vector3(dw * 0.5, FOUNDATION, 0.0), Vector3(dw - 0.04, 2.2, 0.08), COL_WOOD.darkened(0.1), COL_WOOD, 1.0, true)
		dm.box(Vector3(dw - 0.18, FOUNDATION + 1.0, 0.07), Vector3(0.06, 0.06, 0.06), COL_IRON, COL_IRON)
		door_at = [float(door[0]), float(door[1]) - WALL_T * 0.5, dw]
	return {"struct": m.arrays(), "glass": g.arrays(), "proxy": proxy.arrays(), "door": dm.arrays(), "door_at": door_at,
		"spawns": spawns(s) if ent else [], "roof_level": roof, "top": t, "ground_h": gh, "floor_h": fh,
		"tris": m.tris() + g.tris()}


static func _door_edge(types: Array) -> int:
	# the last FRONT edge of the outline is the +z street facade (rectangles: edge 2; the chaflán corner: edge 3)
	var best := -1
	for i in types.size():
		if int(types[i]) == Edge.FRONT:
			best = i
	return best


static func _out_normal(a: Vector2, b: Vector2) -> Vector2:
	var d := (b - a).normalized()
	# counter-clockwise outline seen from above in the x/z plane (z south): the outside is to the left of a→b
	return Vector2(d.y, -d.x)


## Polygon inset by `t` on every edge (convex outlines).
static func _inset(pts: PackedVector2Array, t: float) -> PackedVector2Array:
	var n := pts.size()
	var ins: Array = []
	for i in n:
		ins.append(t)
	return _offset_edges(pts, ins)


## Inset only the street edges (FRONT / CHAMFER) by `t` (the ático set back).
static func _inset_typed(pts: PackedVector2Array, types: Array, t: float) -> PackedVector2Array:
	var ins: Array = []
	for i in pts.size():
		ins.append(t if int(types[i]) in [Edge.FRONT, Edge.CHAMFER] else 0.0)
	return _offset_edges(pts, ins)


## Moves each edge i inward by ins[i] and intersects consecutive edges (convex outlines).
static func _offset_edges(pts: PackedVector2Array, ins: Array) -> PackedVector2Array:
	var n := pts.size()
	var lines: Array = []
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var o := _out_normal(a, b)
		lines.append([a - o * float(ins[i]), (b - a).normalized()])
	var out := PackedVector2Array()
	for i in n:
		var l0: Array = lines[(i - 1 + n) % n]
		var l1: Array = lines[i]
		var p0: Vector2 = l0[0]
		var d0: Vector2 = l0[1]
		var p1: Vector2 = l1[0]
		var d1: Vector2 = l1[1]
		var den := d0.x * d1.y - d0.y * d1.x
		if absf(den) < 1e-6:
			out.append(p1)
			continue
		var tt := ((p1.x - p0.x) * d1.y - (p1.y - p0.y) * d1.x) / den
		out.append(p0 + d0 * tt)
	return out


## Closed prism of an outline from y0 to y1 (the ShadowProxy).
static func _prism(m: CityMesh, pts: PackedVector2Array, y0: float, y1: float) -> void:
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		m.wall(a, b, y0, y1, _out_normal(a, b), Color.WHITE, 1.0)
	m.floor_poly(pts, y1, true, Color.WHITE, 1.0)
	m.floor_poly(pts, y0, false, Color.WHITE, 1.0)


## One floor band of one facade edge: wall with openings (glass recessed, reveals), per-family ornaments.
static func _facade_band(m: CityMesh, g: CityMesh, s: Dictionary, pal: Array, etype: int, a: Vector2, b: Vector2, o: Vector2,
		k: int, wb: float, y0: float, y1: float, floors: int, door: Array) -> void:
	var fam := str(s["fam"])
	var wall_col: Color = pal[0]
	var trim: Color = pal[1]
	var accent: Color = pal[2]
	var length := a.distance_to(b)
	var d := (b - a) / maxf(length, 0.001)
	var band := y1 - y0
	var street := etype == Edge.FRONT or etype == Edge.CHAMFER
	# blank party walls / short ends of the slabs: plain wall (a touch darker), a plinth band at the ground floor
	if etype == Edge.SIDE or (etype == Edge.END and not (fam in ["bloque", "caseta"])):
		m.wall(a, b, wb, y1, o, wall_col.darkened(0.08), 1.0)
		return
	var openings: Array = []   # [u0, u1, sill (m over y0), head (m over y0), kind] ; kind: 0 glass, 1 door gap, 2 metal shutter
	var bay := float(s["bay"])
	var nb := maxi(1, int(round(length / bay)))
	var bw := length / float(nb)
	var gnd := k == 0
	match fam:
		"casco":
			if gnd:
				for i in nb:
					var c := bw * (float(i) + 0.5)
					var arcade := bool(s.get("arcade", false)) and street
					if arcade:
						continue
					if street and i == nb / 2:
						openings.append([c - 0.55, c + 0.55, 0.02, 2.45, 1])   # the house door (a dark recess)
					elif street:
						openings.append([c - 0.5, c + 0.5, 0.9, 2.35, 0])
					else:
						openings.append([c - 0.4, c + 0.4, 1.0, 2.2, 0])
			else:
				for i in nb:
					var c := bw * (float(i) + 0.5)
					if street:
						openings.append([c - 0.5, c + 0.5, 0.05, 2.3, 0])      # balcony doors
					else:
						openings.append([c - 0.4, c + 0.4, 0.95, 2.2, 0])
		"ensanche":
			if gnd:
				if street:
					for i in nb:
						var c := bw * (float(i) + 0.5)
						var hsh := WorldConst.hash64(int(s["vi"]) + 7, i, int(length * 10.0))
						var shutter := WorldConst.unit(hsh) < 0.35
						openings.append([c - bw * 0.5 + 0.35, c + bw * 0.5 - 0.35, 0.35, 3.3, 2 if shutter else 0])
				else:
					for i in nb:
						var c := bw * (float(i) + 0.5)
						openings.append([c - 0.5, c + 0.5, 1.2, 3.2, 0])
			else:
				for i in nb:
					var c := bw * (float(i) + 0.5)
					if street:
						openings.append([c - 0.55, c + 0.55, 0.05, 2.45, 0])
					else:
						openings.append([c - 0.5, c + 0.5, 0.9, 2.3, 0])
		"caseta":
			for i in nb:
				var c := bw * (float(i) + 0.5)
				openings.append([c - 0.45, c + 0.45, 1.0, 2.2, 0])
		"bloque":
			var point := bool(s.get("point", false))
			for i in nb:
				var c := bw * (float(i) + 0.5)
				var core := not point and etype == Edge.BACK and i % 6 == 3
				if etype == Edge.END:
					if point:
						openings.append([c - 0.7, c + 0.7, 0.9, 2.3, 0])
					continue
				if gnd:
					if etype == Edge.FRONT and i % 6 == 3 and not point:
						openings.append([c - 1.0, c + 1.0, 0.02, 2.6, 1])   # portal
					else:
						openings.append([c - 0.7, c + 0.7, 0.9, 2.3, 0])
				elif core:
					openings.append([c - 0.6, c + 0.6, 0.15, band - 0.1, 0])   # stairwell strip
				else:
					openings.append([c - 0.75, c + 0.75, 0.9, 2.35, 0])
	# the enterable ground floor's door: replaces the openings it overlaps
	if not door.is_empty():
		# the +z facade runs from +x to −x (counter-clockwise outline): along-edge u = a.x − x
		var u0 := a.x - (float(door[0]) + float(door[2]))
		var u1 := u0 + float(door[2])
		var kept: Array = []
		for op in openings:
			if float(op[1]) < u0 - 0.15 or float(op[0]) > u1 + 0.15:
				kept.append(op)
		kept.append([u0, u1, 0.0, 2.55, 1])
		openings = kept
	openings.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	# plinth colour on the ground floor (stone), the wall above
	var base_col := trim if (gnd and fam != "bloque") else wall_col
	var col_for := func(y: float) -> Color: return base_col if y < y0 + 0.9 and gnd else (trim if (gnd and fam == "ensanche") else wall_col)
	_wall_with_openings(m, g, a, d, o, length, wb, y0, y1, openings, col_for, wall_col, trim, accent, fam, gnd, street)
	# ornaments
	match fam:
		"casco":
			if street and not gnd:
				for op in openings:
					var u0 := float(op[0]) - 0.35
					var u1 := float(op[1]) + 0.35
					var pa := a + d * u0
					var pb := a + d * u1
					m.slab_along(pa, pb, o, 0.6, y0 - 0.12, y0 + 0.02, trim, trim, 1.0)                       # balcony slab
					m.slab_along(pa + o * 0.56, pb + o * 0.56, o, 0.04, y0 + 0.02, y0 + 1.0, accent.darkened(0.35), accent.darkened(0.35), 1.0)   # railing
					# shutters (open, against the wall)
					m.slab_along(a + d * (float(op[0]) - 0.52), a + d * (float(op[0]) - 0.02), o, 0.05, y0 + 0.05, y0 + 2.3, accent, accent, 1.0)
					m.slab_along(a + d * (float(op[1]) + 0.02), a + d * (float(op[1]) + 0.52), o, 0.05, y0 + 0.05, y0 + 2.3, accent, accent, 1.0)
			if street and gnd and bool(s.get("arcade", false)):
				_arcade(m, s, pal, a, b, d, o, length, wb, y0, y1)
			if k == floors - 1 and etype != Edge.SIDE:
				m.slab_along(a - d * 0.3, b + d * 0.3, o, 0.45, y1 + 0.0, y1 + 0.3, trim, trim, 1.0)   # eaves cornice
		"ensanche":
			if street:
				if gnd:
					m.slab_along(a, b, o, 0.25, y1 - 0.35, y1 - 0.05, trim, trim, 1.0)                    # impost band
					for op in openings:
						if int(op[4]) == 0 and WorldConst.unit(WorldConst.hash64(int(float(op[0]) * 10.0), int(length * 10.0), 3)) < 0.45:
							# awning (toldo): a sloped canvas over the shopfront
							var pa := a + d * float(op[0])
							var pb := a + d * float(op[1])
							var ytop := y0 + float(op[3]) + 0.35
							m.quad(Vector3(pa.x, ytop, pa.y), Vector3(pb.x, ytop, pb.y), Vector3(pb.x + o.x * 1.3, ytop - 0.55, pb.y + o.y * 1.3),
								Vector3(pa.x + o.x * 1.3, ytop - 0.55, pa.y + o.y * 1.3), Vector3(o.x * 0.4, 1.0, o.y * 0.4), accent.lightened(0.35), 1.0)
							m.quad(Vector3(pa.x, ytop, pa.y), Vector3(pb.x, ytop, pb.y), Vector3(pb.x + o.x * 1.3, ytop - 0.55, pb.y + o.y * 1.3),
								Vector3(pa.x + o.x * 1.3, ytop - 0.55, pa.y + o.y * 1.3), Vector3(-o.x * 0.4, -1.0, -o.y * 0.4), accent.lightened(0.1), 0.7)
				elif k == 1:
					m.slab_along(a, b, o, 0.9, y0 - 0.15, y0 + 0.03, trim, trim, 1.0)                           # continuous balcony
					m.slab_along(a + o * 0.86, b + o * 0.86, o, 0.04, y0 + 0.03, y0 + 1.0, COL_IRON, COL_IRON, 1.0)
				elif k < floors - 1 or floors < 5:
					for op in openings:
						var pa := a + d * (float(op[0]) - 0.3)
						var pb := a + d * (float(op[1]) + 0.3)
						m.slab_along(pa, pb, o, 0.55, y0 - 0.12, y0 + 0.03, trim, trim, 1.0)
						m.slab_along(pa + o * 0.51, pb + o * 0.51, o, 0.04, y0 + 0.03, y0 + 1.0, COL_IRON, COL_IRON, 1.0)
				if k == floors - 2 and floors >= 5:
					m.slab_along(a, b, o, 0.5, y1 - 0.1, y1 + 0.25, trim, trim, 1.0)                           # main cornice
		"bloque":
			if not gnd and etype == Edge.FRONT and not bool(s.get("point", false)):
				m.slab_along(a, b, o, 1.1, y0 - 0.15, y0 + 0.02, trim, trim, 1.0)                               # terrace band
				m.slab_along(a + o * 1.0, b + o * 1.0, o, 0.1, y0 + 0.02, y0 + 1.0, trim.darkened(0.05), trim, 1.0)   # its parapet
			if gnd:
				m.slab_along(a, b, o, 0.08, y1 - 0.25, y1, trim, trim, 1.0)


## A wall face with rectangular openings along a→(a + d·length), from wb to y1: horizontal strips + piers, glass
## recessed with reveals; door gaps are dark recesses (the enterable door is a real hole: no fill).
static func _wall_with_openings(m: CityMesh, g: CityMesh, a: Vector2, d: Vector2, o: Vector2, length: float, wb: float, y0: float, y1: float,
		openings: Array, col_for: Callable, wall_col: Color, trim: Color, accent: Color, fam: String, gnd: bool, street: bool) -> void:
	var lo := y0 + 0.9 if gnd else y0
	# the plinth strip [wb, lo] runs under everything except door gaps
	var cursor := 0.0
	for op in openings:
		var u0 := clampf(float(op[0]), 0.0, length)
		var u1 := clampf(float(op[1]), 0.0, length)
		var sill := y0 + float(op[2])
		var head := minf(y0 + float(op[3]), y1 - 0.05)
		var kind := int(op[4])
		# pier before the opening, full height
		if u0 > cursor + 0.001:
			_wall_split(m, a + d * cursor, a + d * u0, o, wb, y1, lo, col_for)
		# under the opening (spandrel / plinth) and over it (lintel)
		if kind != 1 and sill > wb + 0.001:
			_wall_split(m, a + d * u0, a + d * u1, o, wb, sill, lo, col_for)
		elif kind == 1 and y0 > wb + 0.001:
			_wall_split(m, a + d * u0, a + d * u1, o, wb, y0, lo, col_for)
		if head < y1 - 0.001:
			m.wall(a + d * u0, a + d * u1, head, y1, o, wall_col if not gnd else (trim if fam == "ensanche" else wall_col), 1.0)
		# the recessed fill + reveals
		var r := GLASS_RECESS if kind != 1 else WALL_T
		var bottom := sill if kind != 1 else y0
		var pa := a + d * u0
		var pb := a + d * u1
		var ia := pa - o * r
		var ib := pb - o * r
		m.wall(pa, ia, bottom, head, d, COL_REVEAL, 0.8)            # left jamb (faces +d)
		m.wall(ib, pb, bottom, head, -d, COL_REVEAL, 0.8)           # right jamb
		m.quad(Vector3(pa.x, head, pa.y), Vector3(pb.x, head, pb.y), Vector3(ib.x, head, ib.y), Vector3(ia.x, head, ia.y), Vector3.DOWN, COL_REVEAL, 0.7)
		if kind != 1:
			m.quad(Vector3(pa.x, sill, pa.y), Vector3(pb.x, sill, pb.y), Vector3(ib.x, sill, ib.y), Vector3(ia.x, sill, ia.y), Vector3.UP, trim, 1.0)
		match kind:
			0:
				g.wall(ia, ib, bottom, head, o, GLASS, 1.0)
				# a mullion on wide glass (shopfronts)
				if u1 - u0 > 1.8:
					var mid := (ia + ib) * 0.5
					m.slab_along(mid - d * 0.04, mid + d * 0.04, o, 0.06, bottom, head, COL_IRON, COL_IRON, 1.0)
			2:
				m.wall(ia, ib, bottom, head, o, COL_SHUTTER_METAL, 1.0)
				# ribs of the rolled-down metal shutter
				var yy := bottom + 0.35
				while yy < head - 0.2:
					m.slab_along(ia + o * 0.0, ib, o, 0.03, yy, yy + 0.04, COL_SHUTTER_METAL.darkened(0.25), COL_SHUTTER_METAL, 1.0)
					yy += 0.45
			1:
				pass   # a hole (enterable door) or the dark porch of a closed door (casco / portal: filled below)
		if kind == 1 and not street:
			m.wall(ia, ib, bottom, head, o, COL_WOOD, 0.8)
		cursor = u1
	if cursor < length - 0.001:
		_wall_split(m, a + d * cursor, a + d * length, o, wb, y1, lo, col_for)


## Wall strip that changes colour at `split` (the stone plinth of a ground floor).
static func _wall_split(m: CityMesh, a: Vector2, b: Vector2, o: Vector2, y0: float, y1: float, split: float, col_for: Callable) -> void:
	if split > y0 and split < y1:
		m.wall(a, b, y0, split, o, col_for.call(y0), 1.0)
		m.wall(a, b, split, y1, o, col_for.call(split + 0.01), 1.0)
	else:
		m.wall(a, b, y0, y1, o, col_for.call(y0), 1.0)


## Casco soportal: the ground floor front set back 2.4 m behind stone columns carrying the upper floors.
static func _arcade(m: CityMesh, s: Dictionary, pal: Array, a: Vector2, b: Vector2, d: Vector2, o: Vector2, length: float, wb: float, y0: float, y1: float) -> void:
	var trim: Color = pal[1]
	var back := 2.4
	var ia := a - o * back
	var ib := b - o * back
	# recessed wall with a door and two windows
	m.wall(ia, ib, wb, y1, o, trim, 0.75)
	var c := length * 0.5
	m.wall(ia + d * (c - 0.55), ia + d * (c + 0.55), y0 + 0.02, y0 + 2.4, o * 1.0, COL_WOOD, 0.7)
	# the arcade ceiling (underside of floor 1) and the paving
	m.quad(Vector3(a.x, y1 - 0.2, a.y), Vector3(b.x, y1 - 0.2, b.y), Vector3(ib.x, y1 - 0.2, ib.y), Vector3(ia.x, y1 - 0.2, ia.y), Vector3.DOWN, trim, 0.55)
	m.quad(Vector3(a.x, y0 - 0.02, a.y), Vector3(b.x, y0 - 0.02, b.y), Vector3(ib.x, y0 - 0.02, ib.y), Vector3(ia.x, y0 - 0.02, ia.y), Vector3.UP, Color(0.6, 0.58, 0.55), 0.8)
	# columns at the street line, a lintel beam over them
	var n := maxi(2, int(round(length / 3.0)) + 1)
	for i in n:
		var u := lerpf(0.35, length - 0.35, float(i) / float(n - 1))
		var p := a + d * u - o * 0.3
		m.box(Vector3(p.x, wb, p.y), Vector3(0.5, y1 - 0.5 - wb, 0.5), trim, trim, 1.0)
	m.slab_along(a, b, -o, 0.6, y1 - 0.55, y1, trim, trim, 0.9)
	# side walls closing the arcade at the lot ends
	m.wall(a, ia, wb, y1, -d, trim, 0.8)
	m.wall(ib, b, wb, y1, d, trim, 0.8)


## Interior of one floor: a partition across the depth and a stair / lift core (open box: black in the cut); the
## enterable ground floor gets its shop (counter, shelves) and back-room partition instead.
static func _interior(m: CityMesh, s: Dictionary, ipts: PackedVector2Array, k: int, y0: float, y1: float, ent: bool) -> void:
	var bb := Rect2(ipts[0], Vector2.ZERO)
	for p in ipts:
		bb = bb.expand(p)
	var h := y1 - 0.2 - y0
	if ent and k == 0 and not _shop(s):
		var ct0: Array = _counter(s)
		m.box(ct0[0], ct0[1], Color(0.36, 0.38, 0.32), Color(0.42, 0.44, 0.38), 0.45)
		return
	if str(s["fam"]) == "caseta":
		return
	if ent and k == 0:
		var hw := float(s["w"]) * 0.5
		var pz := _partition_z(s)
		# back-room partition with a doorway (x ∈ [0, 1.2])
		_open_wall(m, Vector2(bb.position.x, pz), Vector2(0.0, pz), y0, y0 + h, COL_INNER, 0.5)
		_open_wall(m, Vector2(1.2, pz), Vector2(bb.end.x, pz), y0, y0 + h, COL_INNER, 0.5)
		var ct: Array = _counter(s)
		m.box(ct[0], ct[1], COL_WOOD, COL_WOOD.lightened(0.2), 0.45)
		# shelves along the side wall of the shop floor (not on the chaflán corner: that wall is the cut) and the back room
		if not s.has("corner"):
			m.box(Vector3(bb.end.x - 0.3, y0, (pz + bb.end.y) * 0.5), Vector3(0.45, 1.9, maxf(bb.end.y - pz - 3.0, 0.8)), COL_WOOD.darkened(0.2), COL_WOOD, 0.4)
		m.box(Vector3((bb.position.x + 0.0) * 0.5, y0, bb.position.y + 0.35), Vector3(maxf(-bb.position.x - 1.0, 0.8), 1.8, 0.45), COL_WOOD.darkened(0.2), COL_WOOD, 0.4)
		return
	# partition across the depth (long buildings: every ~14 m) and a core box
	var w := bb.size.x
	var cuts := maxi(1, int(w / 14.0))
	for i in cuts:
		var x := bb.position.x + w * float(i + 1) / float(cuts + 1)
		_open_wall(m, Vector2(x, bb.position.y), Vector2(x, bb.end.y), y0, y0 + h, COL_INNER, 0.45)
	var core_x := bb.position.x + w * 0.5 / float(cuts + 1)
	var cs := Vector2(2.4, 3.0) if bb.size.y > 8.0 else Vector2(2.0, 2.2)
	_core(m, Vector3(core_x, y0, bb.get_center().y), cs, h)


## A thin double-faced interior wall along a→b (0.12 m), from y0 to y1.
static func _open_wall(m: CityMesh, a: Vector2, b: Vector2, y0: float, y1: float, col: Color, ao: float) -> void:
	if a.distance_to(b) < 0.1:
		return
	var o := _out_normal(a, b) * 0.06
	m.wall(a + o, b + o, y0, y1, o, col, ao)
	m.wall(b - o, a - o, y0, y1, -o, col, ao)


## Open-topped core box (walls both faces, dark inside).
static func _core(m: CityMesh, base: Vector3, size: Vector2, h: float) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var c := [Vector2(base.x - hx, base.z - hz), Vector2(base.x + hx, base.z - hz), Vector2(base.x + hx, base.z + hz), Vector2(base.x - hx, base.z + hz)]
	for i in 4:
		var a: Vector2 = c[i]
		var b: Vector2 = c[(i + 1) % 4]
		var o := _out_normal(a, b)
		m.wall(a, b, base.y, base.y + h, o, COL_INNER, 0.45)
		m.wall(b, a, base.y, base.y + h, -o, COL_CORE, 0.25)


## Flat roof: roof slab (open sky), parapet with coping, roof furniture (bloque: lift houses and water tanks; others:
## chimney stacks and a skylight).
static func _flat_roof(m: CityMesh, s: Dictionary, pal: Array, pts: PackedVector2Array, roof: float, bloque: bool, floors: int) -> void:
	var trim: Color = pal[1]
	var wall_col: Color = pal[0]
	m.floor_poly(pts, roof, true, COL_ROOF_FLAT, 1.0)
	var n := pts.size()
	var ins := _inset(pts, 0.3)
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var ia := ins[i]
		var ib := ins[(i + 1) % n]
		var o := _out_normal(a, b)
		var ph := parapet(str(s["fam"]))
		m.wall(a, b, roof - 0.2, roof + ph, o, wall_col if not bloque else trim, 1.0)
		m.wall(ib, ia, roof, roof + ph, -o, trim, 0.85)
		m.quad(Vector3(a.x, roof + ph, a.y), Vector3(b.x, roof + ph, b.y), Vector3(ib.x, roof + ph, ib.y), Vector3(ia.x, roof + ph, ia.y), Vector3.UP, trim, 1.0)
	var bb := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		bb = bb.expand(p)
	var seed_v := int(bb.size.x * 13.0 + bb.size.y * 7.0) + floors
	if str(s["fam"]) == "caseta":
		return
	if bloque:
		var cores := maxi(1, int(bb.size.x / 20.0))
		for i in cores:
			var x := bb.position.x + bb.size.x * (float(i) + 0.5) / float(cores)
			m.box(Vector3(x, roof, bb.get_center().y - 1.0), Vector3(3.2, 2.6, 3.4), trim, COL_ROOF_FLAT, 1.0)       # lift / stair house
			m.box(Vector3(x + 2.8, roof, bb.get_center().y + 1.6), Vector3(1.8, 1.4, 1.8), Color(0.62, 0.64, 0.66), COL_ROOF_FLAT, 1.0)   # water tank
			m.box(Vector3(x - 2.6, roof, bb.get_center().y + 2.2), Vector3(0.08, 3.2, 0.08), COL_IRON, COL_IRON, 1.0)   # antenna mast
	else:
		for i in 3:
			var h := WorldConst.hash64(seed_v, 91, i)
			var x := bb.position.x + 1.5 + WorldConst.unit(h) * maxf(bb.size.x - 3.0, 0.1)
			var z := bb.position.y + 1.5 + WorldConst.unit(WorldConst.hash64(h, 1)) * maxf(bb.size.y - 3.0, 0.1)
			if i == 0:
				m.box(Vector3(x, roof, z), Vector3(2.2, 1.9, 2.2), trim, COL_ROOF_FLAT, 1.0)   # stair house
			else:
				m.box(Vector3(x, roof, z), Vector3(0.6, 1.3, 0.9), wall_col.darkened(0.15), COL_ROOF_FLAT, 1.0)   # chimney stack


## Ensanche ático terrace: the roof of the floor below between the facade and the set-back ático + its railing.
static func _terrace(m: CityMesh, s: Dictionary, pal: Array, pts: PackedVector2Array, at_pts: PackedVector2Array, types: Array, y: float) -> void:
	var trim: Color = pal[1]
	var n := pts.size()
	for i in n:
		if not (int(types[i]) in [Edge.FRONT, Edge.CHAMFER]):
			continue
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var aa := at_pts[i]
		var ab := at_pts[(i + 1) % n]
		m.quad(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(ab.x, y, ab.y), Vector3(aa.x, y, aa.y), Vector3.UP, COL_ROOF_FLAT, 1.0)
		var o := _out_normal(a, b)
		m.slab_along(a - o * 0.05, b - o * 0.05, o * -1.0, 0.18, y - 0.1, y + 0.45, trim, trim, 1.0)
		m.slab_along(a - o * 0.08, b - o * 0.08, o * -1.0, 0.05, y + 0.45, y + 1.05, COL_IRON, COL_IRON, 1.0)


## Casco tiled roof: two slopes (ridge along the frontage, 28°), overhanging front and back, gable walls at the ends,
## the attic slab at roof level; a chimney.
static func _pitched_roof(m: CityMesh, s: Dictionary, pal: Array, pts: PackedVector2Array, roof: float) -> void:
	var tile: Color = pal[3]
	var wall_col: Color = pal[0]
	var hw := float(s["w"]) * 0.5
	var hd := float(s["d"]) * 0.5
	var eave := roof + 0.3
	var over := 0.45
	var ridge := eave + hd * tan(deg_to_rad(28.0))
	var ze := hd + over
	var ye := eave - over * tan(deg_to_rad(28.0))
	# attic slab (roof level) and the wall band up to the eaves
	m.floor_poly(pts, roof, true, COL_SLAB, 0.3)
	for e in [[Vector2(-hw, -hd), Vector2(hw, -hd)], [Vector2(hw, -hd), Vector2(hw, hd)], [Vector2(hw, hd), Vector2(-hw, hd)], [Vector2(-hw, hd), Vector2(-hw, -hd)]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		m.wall(a, b, roof, eave, _out_normal(a, b), wall_col, 1.0)
	# slopes (front +z, back −z): top faces tiled (the snow shader whitens them), undersides (eaves soffit)
	var x0 := -hw - 0.05
	var x1 := hw + 0.05
	for sgn: float in [1.0, -1.0]:
		var fa := Vector3(x0, ridge, 0.0)
		var fb := Vector3(x1, ridge, 0.0)
		var fc := Vector3(x1, ye, sgn * ze)
		var fd := Vector3(x0, ye, sgn * ze)
		var nrm := Vector3(0.0, 1.0, sgn * tan(deg_to_rad(28.0))).normalized()
		m.quad(fa, fb, fc, fd, nrm, tile, 1.0)
		m.quad(fa - Vector3(0, 0.12, 0), fb - Vector3(0, 0.12, 0), fc - Vector3(0, 0.12, 0), fd - Vector3(0, 0.12, 0), -nrm, tile.darkened(0.3), 0.5)
		# the fascia (edge of the tiles)
		m.quad(fd, fc, fc - Vector3(0, 0.14, 0), fd - Vector3(0, 0.14, 0), Vector3(0, 0, sgn), tile.darkened(0.2), 1.0)
	# gable triangles (party walls up to the ridge)
	for sx: float in [-1.0, 1.0]:
		var x := sx * hw
		m.tri(Vector3(x, eave, -hd), Vector3(x, eave, hd), Vector3(x, ridge, 0.0), Vector3(sx, 0, 0), wall_col.darkened(0.08), 1.0)
		m.tri(Vector3(x, eave, hd), Vector3(x, eave, -hd), Vector3(x, ridge, 0.0), Vector3(-sx, 0, 0), COL_INNER, 0.35)
	# a chimney stack through the back slope
	var cx := hw * 0.45
	m.box(Vector3(cx, ridge - 1.2, -hd * 0.35), Vector3(0.7, 2.0, 0.7), wall_col.darkened(0.2), COL_ROOF_FLAT, 1.0)


# ------------------------------------------------------------------ nodes
## The root of a lot (not in the tree): Base / ShadowProxy (visual only) + the contract metadata; enterable ground
## floors add the `Door_0` leaf (a MeshInstance3D on clients, a bare Node3D on the server: same transform, the same
## KitDoor box from its default leaf AABB) and `Spawn_Container_<n>` empties (extras table). `item` = a CityLots
## BUILDING item.
static func build(item: Dictionary, visual: bool) -> Node3D:
	var fam := str(item["fam"])
	var vi := int(item["var"])
	var floors := int(item["floors"])
	var pal := int(item.get("pal", 0))
	var ent := bool(item.get("ent", false))
	var s := spec(fam, vi)
	var root := Node3D.new()
	root.name = "bldg_%d" % int(item["id"])
	root.set_meta("floor_h", float(s["floor_h"]))
	root.set_meta("ground_h", float(s["ground_h"]))
	root.set_meta("foundation", FOUNDATION)
	root.set_meta("floors", floors)
	root.set_meta("generator", bool(item.get("generator", false)))
	root.set_meta("enterable", ent)
	root.set_meta("kind", fam)
	root.set_meta("family", fam)
	root.set_meta("wid", int(item["wid"]))
	var d := data(fam, vi, floors, pal, ent)
	if visual:
		var ms := meshes(fam, vi, floors, pal, ent)
		for nm in ["Base", "ShadowProxy"]:
			var mi := MeshInstance3D.new()
			mi.name = nm
			mi.mesh = ms[nm]
			root.add_child(mi)
	if ent:
		var da: Array = d["door_at"]
		var leaf: Node3D
		if visual:
			var lm := MeshInstance3D.new()
			lm.mesh = meshes(fam, vi, floors, pal, ent)["Door"]
			leaf = lm
		else:
			leaf = Node3D.new()
		leaf.name = "Door_0"
		leaf.position = Vector3(float(da[0]), 0.0, float(da[1]))
		leaf.set_meta("extras", {"kind": "door", "exterior": true, "hinge": "L", "width": float(da[2]), "cut_group": "Walls0_S", "floor": 0})
		root.add_child(leaf)
		var tables: Array = SHOP_TABLES.get(fam, [&"house"])
		var sp: Array = d["spawns"]
		for i in sp.size():
			var e := Node3D.new()
			e.name = "Spawn_Container_%d" % i
			e.position = sp[i][0]
			e.rotation.y = float(sp[i][1])
			var tbl: StringName = tables[posmod(int(WorldConst.hash64(int(item["wid"]), 17, i) & 0xFFFF), tables.size())]
			e.set_meta("extras", {"table": String(tbl)})
			root.add_child(e)
	return root
