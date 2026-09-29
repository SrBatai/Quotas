class_name HeroTower
extends Node3D
## Enterable hero tower of Las Torres (C1, doc 09 §4.5 «2 torres héroe con escalera, 4–6 plantas amuebladas y
## azotea»; PLAN v3.8.2 C1): Torre Albo (40 floors, helipad, mirador) and the Edificio Meridiano (24 floors, tanks).
## The node IS the building root of the city contract (ARQ v2 §9.7): `Base` (floors 0–3), `Shaft_<n>` (groups of 4
## floors, floor_from / floor_to), `Roof` (the crown: parapet, stair house, helipad or tanks), `ShadowProxy`; the
## «corte urbano» cuts it as the player's own building (CityCut: floors above the player's hidden shadow-preserving,
## the shader removes everything over the ceiling of their floor in the footprint).
## Every floor is a real floor: a slab at base + ground_h + (k − 1)·floor_h with the stairwell opening, the fire stair
## (two flights and a half landing, ramp colliders a CharacterBody walks up), the lift shaft, the curtain wall; the
## `furnished` floors add offices (partitions, desks), a stair door and office doors (KitDoor, deterministic wids:
## server-authoritative, replicated as chunk deltas) and loot containers (LootSpawns). The stair reaches the roof
## through a stair house with a door. Built the same on the server and every client (colliders, door leaves,
## spawns); the meshes only on visual clients. On clients the build is a list of small steps (build_step: the lobby
## colliders, 4 doors, 3 containers, 60 floor colliders, one piece mesh or instance, CityBuilding.attach) that
## CityChunk runs one per streaming step; the server runs them all in setup.
## Colliders: `ColBody` (group nav_static: the lobby floor, the walls up to the first slab — the street navmesh
## carves them) and `FloorsCol` (everything above: NavFloorTile bakes it floor by floor, never the chunk bake).

const FOUNDATION := 0.3
const WALL := 0.25
const SLAB := 0.25
const PARAPET := 1.2
const FLIGHT_W := 1.5
const RUN := 3.2
const LANDING := 1.5
const GLASS := Color(0.18, 0.24, 0.30)
const COL_SLAB := Color(0.64, 0.64, 0.63)
const COL_INNER := Color(0.78, 0.77, 0.74)
const COL_CORE := Color(0.55, 0.55, 0.56)
const COL_STAIR := Color(0.60, 0.60, 0.61)
const COL_IRON := Color(0.17, 0.18, 0.20)
const COL_DESK := Color(0.48, 0.42, 0.36)
const STYLES := {
	"glass": {"spandrel": Color("#4E5968"), "mullion": Color("#3A424E"), "base": Color("#6E7680"), "roof": Color("#5A5E64")},
	"concrete": {"spandrel": Color("#9A968E"), "mullion": Color("#7A766E"), "base": Color("#86827A"), "roof": Color("#5E5E5C")},
}
const GEN_HERO := 0x4845524F   # "HERO"

static var _data: Dictionary = {}     # hero id -> pure piece arrays
static var _meshes: Dictionary = {}   # hero id -> {piece name: ArrayMesh}
static var _lock := Mutex.new()

var rec: Dictionary = {}
var item: Dictionary = {}
var hero_id: int = 0
var visual: bool = true
var floors: int = 1
var gh: float = 4.3
var fh: float = 3.8
var size := Vector2(30, 30)
var doors: Array[KitDoor] = []
var containers: int = 0
var built: bool = false
## Client: the upper-floor colliders being built outside the tree (FLOORS_BATCH shapes per step); doors and loot
## containers DOORS_PER_STEP / LOOT_PER_STEP per step (≈ 0.1 ms each).
const FLOORS_BATCH := 60
const DOORS_PER_STEP := 4
const LOOT_PER_STEP := 3
var loot: Array[LootContainer] = []
var _todo: Array = []
var _todo_i: int = 0
var _seed: int = 0
var _spawns: Array[Node3D] = []
var _floors_body: StaticBody3D
var _floors_boxes: Array = []
var _floors_done: int = 0


# ------------------------------------------------------------------ layout (pure)
static func level(k: int, p_gh: float, p_fh: float) -> float:
	return FOUNDATION if k <= 0 else p_gh + float(k - 1) * p_fh


## The stairwell (local plan): {x0, x1, z0, z1} — flight A on the west half rising −z, the half landing at z0, flight
## B on the east half rising +z to the floor landing at z1 (where the stair door is, in the core's south wall).
static func stairwell(sz: Vector2) -> Dictionary:
	var zc := -1.0 if sz.y <= 22.0 else -2.0
	var z1 := zc + 3.1
	var z0 := z1 - (LANDING + RUN + LANDING)
	return {"x0": -4.8, "x1": -1.2, "z0": z0, "z1": z1, "lift_x0": -0.8, "lift_x1": 4.8}


static func rec_of(id: int) -> Dictionary:
	return CityLots.hero(id)


## Floors with offices, doors and loot.
static func furnished(r: Dictionary) -> Array:
	var out: Array = []
	for f in r.get("furnished", []):
		out.append(int(f))
	return out


# ------------------------------------------------------------------ pure geometry (cached per hero)
## Builds (or reads) the piece arrays of a hero: {"Base": [struct, glass], "Shaft_<n>": …, "Roof": …, "ShadowProxy":
## arrays, "ranges": {piece: [from, to]}, "door": arrays (a leaf at y 0)}. Thread-safe.
static func prepare(id: int) -> Dictionary:
	_lock.lock()
	var d: Dictionary = _data.get(id, {})
	_lock.unlock()
	if not d.is_empty():
		return d
	var r := rec_of(id)
	if r.is_empty():
		return {}
	d = _build_data(r)
	_lock.lock()
	if not _data.has(id):
		_data[id] = d
	else:
		d = _data[id]
	_lock.unlock()
	return d


static func clear_cache() -> void:
	_lock.lock()
	_data.clear()
	_lock.unlock()
	_meshes.clear()


static func _build_data(r: Dictionary) -> Dictionary:
	var n := int(r["floors"])
	var p_gh := CityLots.cm(r.get("ground_h", 430))
	var p_fh := CityLots.cm(r.get("floor_h", 380))
	var sz := CityLots.v2(r["size"])
	var st: Dictionary = STYLES.get(str(r.get("style", "glass")), STYLES["glass"])
	var furn := furnished(r)
	var out := {"ranges": {}}
	var groups: Array = [["Base", 0, mini(3, n - 1)]]
	var f := 4
	var gi := 0
	while f < n:
		groups.append(["Shaft_%d" % gi, f, mini(f + 3, n - 1)])
		f += 4
		gi += 1
	for g in groups:
		var m := CityMesh.new()
		var gl := CityMesh.new()
		for k in range(int(g[1]), int(g[2]) + 1):
			_floor(m, gl, k, n, p_gh, p_fh, sz, st, furn.has(k))
		out[g[0]] = [m.arrays(), gl.arrays()]
		(out["ranges"] as Dictionary)[g[0]] = [int(g[1]), int(g[2])]
	var rm := CityMesh.new()
	var rg := CityMesh.new()
	_roof(rm, rg, n, p_gh, p_fh, sz, st, str(r.get("crown", "")))
	out["Roof"] = [rm.arrays(), rg.arrays()]
	var top := level(n, p_gh, p_fh) + PARAPET
	var pm := CityMesh.new()
	pm.box(Vector3(0, -1.0, 0), Vector3(sz.x, top + 1.0 + 3.0, sz.y), Color.WHITE, Color.WHITE, 1.0, true)
	out["ShadowProxy"] = pm.arrays()
	var dm := CityMesh.new()
	dm.box(Vector3(0.5, 0.0, 0.0), Vector3(0.96, 2.2, 0.08), Color(0.46, 0.48, 0.50), Color(0.5, 0.52, 0.54), 1.0, true)
	out["door_unit"] = dm.arrays()
	out["top"] = top
	return out


## One floor band: curtain wall (spandrels, glass, mullions), its inner face, the slab (with the stairwell hole),
## the ceiling, the core (stairwell walls with the door gap, lift shaft with its doors), the stair flights and, on a
## furnished floor, offices.
static func _floor(m: CityMesh, g: CityMesh, k: int, n: int, p_gh: float, p_fh: float, sz: Vector2, st: Dictionary, furn: bool) -> void:
	var y0 := level(k, p_gh, p_fh)
	var y1 := level(k + 1, p_gh, p_fh)
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	var sw := stairwell(sz)
	var spandrel: Color = st["spandrel"]
	var mullion: Color = st["mullion"]
	var base_col: Color = st["base"]
	var wb := y0 - (FOUNDATION + 1.5 if k == 0 else 0.0)
	var corners := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
	for e in 4:
		var a: Vector2 = corners[e]
		var b: Vector2 = corners[(e + 1) % 4]
		var d := (b - a).normalized()
		var o := Vector2(d.y, -d.x)
		var length := a.distance_to(b)
		if k == 0:
			# lobby: a stone base band and tall glass; the entrance (front, +z) is a gap with glass doors
			m.wall(a, b, wb, y0 + 0.4, o, base_col, 1.0)
			var panels := int(round(length / 3.0))
			for i in panels:
				var u0 := length * float(i) / float(panels)
				var u1 := length * float(i + 1) / float(panels)
				var pa := a + d * u0
				var pb := a + d * u1
				var entrance := e == 2 and absf((u0 + u1) * 0.5 - length * 0.5) < 2.0
				if entrance:
					continue
				m.wall(pa, pa + d * 0.15, y0 + 0.4, y1, o, mullion, 1.0)
				g.wall(pa + d * 0.15 - o * 0.1, pb - o * 0.1, y0 + 0.4, y1 - 0.5, o, GLASS, 1.0)
			m.wall(a, b, y1 - 0.5, y1, o, spandrel, 1.0)
		else:
			m.wall(a, b, y0, y0 + 0.95, o, spandrel, 1.0)
			m.wall(a, b, y1 - 0.35, y1, o, spandrel, 1.0)
			var panels := int(round(length / 1.6))
			for i in panels:
				var u0 := length * float(i) / float(panels)
				var u1 := length * float(i + 1) / float(panels)
				var pa := a + d * u0
				var pb := a + d * u1
				m.slab_along(pa, pa + d * 0.12, o, 0.08, y0 + 0.95, y1 - 0.35, mullion, mullion, 1.0)
				g.wall(pa + d * 0.12 - o * 0.06, pb - o * 0.06, y0 + 0.95, y1 - 0.35, o, GLASS, 1.0)
		# inner face (sheltered) behind the curtain wall
		var ia := a - o * WALL + d * WALL
		var ib := b - o * WALL - d * WALL
		m.wall(ib, ia, y0, y1 - SLAB, -o, COL_INNER, 0.45)
	# slab (top face = the plan) with the stairwell hole for k > 0; the ceiling underside
	var ix := hx - WALL
	var iz := hz - WALL
	var hole := k > 0
	_slab_top(m, ix, iz, y0, sw if hole else {}, COL_SLAB, 0.3)
	_slab_bottom(m, ix, iz, y1 - SLAB, sw, COL_SLAB, 0.3)
	# core: stairwell walls (N, W, E) and the south wall with the door gap; the lift shaft box with its doors
	var x0 := float(sw["x0"])
	var x1 := float(sw["x1"])
	var z0 := float(sw["z0"])
	var z1 := float(sw["z1"])
	var lx1 := float(sw["lift_x1"])
	var h := y1 - SLAB - y0
	_twin_wall(m, Vector2(x0 - 0.2, z0 - 0.2), Vector2(lx1 + 0.2, z0 - 0.2), y0, y0 + h)          # north
	_twin_wall(m, Vector2(x0 - 0.2, z1 + 0.2), Vector2(x0 - 0.2, z0 - 0.2), y0, y0 + h)          # west
	_twin_wall(m, Vector2(lx1 + 0.2, z0 - 0.2), Vector2(lx1 + 0.2, z1 + 0.2), y0, y0 + h)        # east (lift)
	_twin_wall(m, Vector2(x1 + 0.2, z0 - 0.2), Vector2(x1 + 0.2, z1 + 0.2), y0, y0 + h)          # stair | lift
	# south wall: the stair door gap x ∈ [x0 + 0.2, x0 + 1.2]; the lift doors (closed)
	_twin_wall(m, Vector2(x0 - 0.2, z1 + 0.2), Vector2(x0 + 0.2, z1 + 0.2), y0, y0 + h)
	_twin_wall(m, Vector2(x0 + 1.2, z1 + 0.2), Vector2(lx1 + 0.2, z1 + 0.2), y0, y0 + h)
	_twin_wall(m, Vector2(x0 + 0.2, z1 + 0.2), Vector2(x0 + 1.2, z1 + 0.2), y0 + 2.2, y0 + h)
	var lm := Vector2((float(sw["lift_x0"]) + lx1) * 0.5, z1 + 0.32)
	m.wall(lm - Vector2(1.0, 0), lm + Vector2(1.0, 0), y0 + 0.02, y0 + 2.1, Vector2(0, 1), Color(0.58, 0.60, 0.62), 1.0)
	m.wall(lm - Vector2(0.02, 0), lm + Vector2(0.02, 0), y0 + 0.02, y0 + 2.1, Vector2(0, 1), COL_IRON, 1.0)
	# the dark lift shaft floor (seen through a cut)
	m.floor_poly(PackedVector2Array([Vector2(float(sw["lift_x0"]), z0), Vector2(lx1, z0), Vector2(lx1, z1), Vector2(float(sw["lift_x0"]), z1)]),
		y0 + 0.01, true, Color(0.12, 0.12, 0.13), 0.2)
	# stair flights (steps) and the half landing, to the next floor
	if k < n:
		_stairs(m, sw, y0, y1)
	if furn:
		_offices(m, k, sz, sw, y0, y1)
	elif k == 0:
		_lobby(m, sz, sw, y0)


static func _twin_wall(m: CityMesh, a: Vector2, b: Vector2, y0: float, y1: float) -> void:
	var d := (b - a).normalized()
	var o := Vector2(d.y, -d.x) * 0.1
	m.wall(a + o, b + o, y0, y1, o, COL_CORE, 0.5)
	m.wall(b - o, a - o, y0, y1, -o, COL_CORE, 0.35)


## Slab top face over the inner rect, minus the stairwell (x0…x1, z0…z1 − landing) when `sw` is given.
static func _slab_top(m: CityMesh, ix: float, iz: float, y: float, sw: Dictionary, col: Color, ao: float) -> void:
	if sw.is_empty():
		m.floor_poly(PackedVector2Array([Vector2(-ix, -iz), Vector2(ix, -iz), Vector2(ix, iz), Vector2(-ix, iz)]), y, true, col, ao)
		return
	for r in _slab_rects(ix, iz, sw):
		var rr: Rect2 = r
		m.floor_poly(PackedVector2Array([rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)]), y, true, col, ao)


static func _slab_bottom(m: CityMesh, ix: float, iz: float, y: float, sw: Dictionary, col: Color, ao: float) -> void:
	for r in _slab_rects(ix, iz, sw):
		var rr: Rect2 = r
		m.floor_poly(PackedVector2Array([rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)]), y, false, col, ao)


## The slab around the stairwell hole [x0, x1] × [z0, z1 − LANDING]: 4 rects (plan).
static func _slab_rects(ix: float, iz: float, sw: Dictionary) -> Array:
	var x0 := float(sw["x0"])
	var x1 := float(sw["x1"])
	var z0 := float(sw["z0"])
	var zh := float(sw["z1"]) - LANDING
	return [Rect2(-ix, -iz, ix * 2.0, z0 - (-iz)),            # north of the hole
		Rect2(-ix, zh, ix * 2.0, iz - zh),                   # south of the hole
		Rect2(-ix, z0, x0 - (-ix), zh - z0),                 # west
		Rect2(x1, z0, ix - x1, zh - z0)]                     # east


## Two flights and the half landing from y0 to y1 (steps: tread + riser quads; stringers).
static func _stairs(m: CityMesh, sw: Dictionary, y0: float, y1: float) -> void:
	var x0 := float(sw["x0"])
	var x1 := float(sw["x1"])
	var z0 := float(sw["z0"])
	var z1 := float(sw["z1"])
	var half := (y1 - y0) * 0.5
	var steps := 11
	var tread := RUN / float(steps)
	var riser := half / float(steps)
	# flight A: x0 … x0 + FLIGHT_W, from z1 − LANDING (y0) toward −z (up)
	for i in steps:
		var za := z1 - LANDING - tread * float(i)
		var zb := za - tread
		var ya := y0 + riser * float(i)
		var yb := ya + riser
		m.quad(Vector3(x0, yb, za), Vector3(x0 + FLIGHT_W, yb, za), Vector3(x0 + FLIGHT_W, yb, zb), Vector3(x0, yb, zb), Vector3.UP, COL_STAIR, 0.5)
		m.quad(Vector3(x0, ya, za), Vector3(x0 + FLIGHT_W, ya, za), Vector3(x0 + FLIGHT_W, yb, za), Vector3(x0, yb, za), Vector3(0, 0, 1), COL_STAIR.darkened(0.15), 0.45)
	# half landing (full stairwell width) at y0 + half
	m.floor_poly(PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z0 + LANDING), Vector2(x0, z0 + LANDING)]), y0 + half, true, COL_STAIR, 0.45)
	m.floor_poly(PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z0 + LANDING), Vector2(x0, z0 + LANDING)]), y0 + half - 0.2, false, COL_STAIR, 0.3)
	# flight B: x1 − FLIGHT_W … x1, from z0 + LANDING (y0 + half) toward +z (up)
	for i in steps:
		var za := z0 + LANDING + tread * float(i)
		var zb := za + tread
		var ya := y0 + half + riser * float(i)
		var yb := ya + riser
		m.quad(Vector3(x1 - FLIGHT_W, yb, za), Vector3(x1, yb, za), Vector3(x1, yb, zb), Vector3(x1 - FLIGHT_W, yb, zb), Vector3.UP, COL_STAIR, 0.5)
		m.quad(Vector3(x1 - FLIGHT_W, ya, za), Vector3(x1, ya, za), Vector3(x1, yb, za), Vector3(x1 - FLIGHT_W, yb, za), Vector3(0, 0, -1), COL_STAIR.darkened(0.15), 0.45)
	# a low wall in the stair's eye between the flights
	var ex := x0 + FLIGHT_W
	var ex1 := x1 - FLIGHT_W
	m.box(Vector3((ex + ex1) * 0.5, y0, (z0 + LANDING + z1 - LANDING) * 0.5), Vector3(ex1 - ex, y1 - y0 - 0.3, RUN), COL_CORE, COL_CORE, 0.4)


## Lobby of the ground floor: a reception desk and benches.
static func _lobby(m: CityMesh, sz: Vector2, sw: Dictionary, y0: float) -> void:
	var hz := sz.y * 0.5
	m.box(Vector3(4.0, y0, hz - 7.0), Vector3(4.0, 1.1, 0.8), Color(0.30, 0.30, 0.32), Color(0.62, 0.60, 0.56), 0.5)
	m.box(Vector3(-8.0, y0, hz - 5.0), Vector3(3.0, 0.45, 0.6), COL_DESK, COL_DESK, 0.5)
	m.box(Vector3(9.0, y0, hz - 4.0), Vector3(3.0, 0.45, 0.6), COL_DESK, COL_DESK, 0.5)


## Offices of a furnished floor: partitions in the east / west wings (with door gaps), desks.
static func _offices(m: CityMesh, k: int, sz: Vector2, sw: Dictionary, y0: float, y1: float) -> void:
	var hx := sz.x * 0.5 - WALL
	var hz := sz.y * 0.5 - WALL
	var h := y1 - SLAB - y0
	for wall in office_walls(sz, sw):
		var a: Vector2 = wall[0]
		var b: Vector2 = wall[1]
		_twin_wall(m, a, b, y0, y0 + h)
	for dk in desks(sz, k):
		var p: Vector3 = dk
		m.box(Vector3(p.x, y0, p.z), Vector3(1.6, 0.75, 0.8), COL_DESK, COL_DESK.lightened(0.15), 0.5)


## Office partitions of a furnished floor (plan segments; the doors sit in the gaps): a wall across each wing.
static func office_walls(sz: Vector2, sw: Dictionary) -> Array:
	var hx := sz.x * 0.5 - WALL
	var hz := sz.y * 0.5 - WALL
	var out: Array = []
	# west wing: a wall at x = −(hx * 0.55) from the north facade to the south facade, with a door gap at z ∈ [1, 2]
	var xw := -hx * 0.62
	out.append([Vector2(xw, -hz), Vector2(xw, 1.0)])
	out.append([Vector2(xw, 2.0), Vector2(xw, hz)])
	var xe := hx * 0.62
	out.append([Vector2(xe, -hz), Vector2(xe, 1.0)])
	out.append([Vector2(xe, 2.0), Vector2(xe, hz)])
	return out


## Office doors of a furnished floor: [hinge (local plan), yaw of the leaf frame] in the partition gaps.
static func office_doors(sz: Vector2) -> Array:
	var hx := sz.x * 0.5 - WALL
	return [[Vector2(-hx * 0.62, 1.0), -PI * 0.5], [Vector2(hx * 0.62, 1.0), -PI * 0.5]]


static func desks(sz: Vector2, k: int) -> Array:
	var hx := sz.x * 0.5 - WALL
	var hz := sz.y * 0.5 - WALL
	var out: Array = []
	for sx: float in [-1.0, 1.0]:
		for j in 3:
			var x := sx * (hx * 0.62 + (hx * 0.38) * 0.5)
			var z := -hz + 2.0 + float(j) * (hz * 2.0 - 4.0) / 2.0
			if (j + k) % 2 == 0:
				out.append(Vector3(x, 0, z))
	out.append(Vector3(3.0, 0, hz - 3.0))
	out.append(Vector3(-7.0, 0, hz - 3.0))
	return out


## Crown: roof slab with the stairwell's stair house (door on its south side), parapet, helipad or water tanks, mast.
static func _roof(m: CityMesh, g: CityMesh, n: int, p_gh: float, p_fh: float, sz: Vector2, st: Dictionary, crown: String) -> void:
	var y := level(n, p_gh, p_fh)
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	var sw := stairwell(sz)
	var spandrel: Color = st["spandrel"]
	var roofc: Color = st["roof"]
	# roof slab (open sky) with the stairwell opening under the stair house
	for r in _slab_rects(hx, hz, sw):
		var rr: Rect2 = r
		m.floor_poly(PackedVector2Array([rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)]), y, true, roofc, 1.0)
	# parapet
	var corners := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
	for e in 4:
		var a: Vector2 = corners[e]
		var b: Vector2 = corners[(e + 1) % 4]
		var d := (b - a).normalized()
		var o := Vector2(d.y, -d.x)
		m.wall(a, b, y - SLAB, y + PARAPET, o, spandrel, 1.0)
		m.wall(b - o * 0.3, a - o * 0.3, y, y + PARAPET, -o, spandrel.lightened(0.1), 0.85)
		m.quad(Vector3(a.x, y + PARAPET, a.y), Vector3(b.x, y + PARAPET, b.y), Vector3(b.x - o.x * 0.3, y + PARAPET, b.y - o.y * 0.3),
			Vector3(a.x - o.x * 0.3, y + PARAPET, a.y - o.y * 0.3), Vector3.UP, spandrel.lightened(0.2), 1.0)
	# stair house over the stairwell + the lift machine room: walls, a door gap on the south side, a roof
	var x0 := float(sw["x0"]) - 0.2
	var x1 := float(sw["lift_x1"]) + 0.2
	var z0 := float(sw["z0"]) - 0.2
	var z1 := float(sw["z1"]) + 0.2
	var hh := 3.0
	_twin_wall(m, Vector2(x0, z0), Vector2(x1, z0), y, y + hh)
	_twin_wall(m, Vector2(x0, z1), Vector2(x0, z0), y, y + hh)
	_twin_wall(m, Vector2(x1, z0), Vector2(x1, z1), y, y + hh)
	_twin_wall(m, Vector2(x0, z1), Vector2(x0 + 0.4, z1), y, y + hh)
	_twin_wall(m, Vector2(x0 + 1.4, z1), Vector2(x1, z1), y, y + hh)
	_twin_wall(m, Vector2(x0 + 0.4, z1), Vector2(x0 + 1.4, z1), y + 2.2, y + hh)
	m.box(Vector3((x0 + x1) * 0.5, y + hh, (z0 + z1) * 0.5), Vector3(x1 - x0 + 0.4, 0.3, z1 - z0 + 0.4), spandrel, roofc, 1.0)
	match crown:
		"helipad":
			# a raised deck on the front half with its H and the edge lights
			var dz := hz * 0.45
			m.box(Vector3(0, y, dz), Vector3(minf(sz.x - 4.0, 18.0), 0.6, minf(hz - 1.5, 12.0)), Color(0.30, 0.31, 0.33), Color(0.32, 0.33, 0.35), 1.0)
			var yh := y + 0.61
			for bar in [[Vector3(-2.2, yh, dz), Vector3(0.5, 0.02, 4.0)], [Vector3(2.2, yh, dz), Vector3(0.5, 0.02, 4.0)], [Vector3(0, yh, dz), Vector3(4.0, 0.02, 0.5)]]:
				m.box(bar[0], bar[1], Color(0.92, 0.92, 0.9), Color(0.92, 0.92, 0.9), 1.0)
			m.box(Vector3(hx - 3.0, y, -hz + 3.0), Vector3(0.3, 14.0, 0.3), Color(0.72, 0.22, 0.18), Color(0.72, 0.22, 0.18), 1.0)
		_:
			for i in 3:
				m.box(Vector3(-hx + 5.0 + float(i) * 3.2, y, hz - 4.0), Vector3(2.4, 2.6, 2.4), Color(0.60, 0.62, 0.64), roofc, 1.0)
			m.box(Vector3(hx - 3.0, y, hz - 3.0), Vector3(0.2, 8.0, 0.2), COL_IRON, COL_IRON, 1.0)


# ------------------------------------------------------------------ colliders (local; server and clients)
## [[centre, size, basis, "box"]] of the tower. `ground` = the ColBody part (nav_static: the lobby), else FloorsCol.
static func collider_boxes(r: Dictionary, ground: bool) -> Array:
	var n := int(r["floors"])
	var p_gh := CityLots.cm(r.get("ground_h", 430))
	var p_fh := CityLots.cm(r.get("floor_h", 380))
	var sz := CityLots.v2(r["size"])
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	var sw := stairwell(sz)
	var out: Array = []
	var y1 := level(1, p_gh, p_fh)
	var top := level(n, p_gh, p_fh) + PARAPET
	var bx := func(c: Vector3, s: Vector3) -> void: out.append([c, s, Basis.IDENTITY, "box"])
	if ground:
		# lobby slab, the four facades up to the first slab (the entrance gap in the front: 4 m in the middle)
		bx.call(Vector3(0, (FOUNDATION - 1.5) * 0.5, 0), Vector3(sz.x, FOUNDATION + 1.5, sz.y))
		var wy := (FOUNDATION + y1) * 0.5
		var wh := y1 - FOUNDATION
		bx.call(Vector3(0, wy, -hz + WALL * 0.5), Vector3(sz.x, wh, WALL))
		bx.call(Vector3(-hx + WALL * 0.5, wy, 0), Vector3(WALL, wh, sz.y))
		bx.call(Vector3(hx - WALL * 0.5, wy, 0), Vector3(WALL, wh, sz.y))
		bx.call(Vector3((-hx - 2.0) * 0.5, wy, hz - WALL * 0.5), Vector3(hx - 2.0, wh, WALL))
		bx.call(Vector3((hx + 2.0) * 0.5, wy, hz - WALL * 0.5), Vector3(hx - 2.0, wh, WALL))
		_core_boxes(bx, sw, FOUNDATION, y1 - SLAB)
		_stair_boxes(out, sw, FOUNDATION, y1)   # the first flight belongs to the lobby's (street) navmesh
		# the lobby's reception desk
		bx.call(Vector3(4.0, FOUNDATION + 0.55, hz - 7.0), Vector3(4.0, 1.1, 0.8))
		return out
	# facades above the first slab (one box per face)
	var fy := (y1 + top) * 0.5
	var fhh := top - y1
	bx.call(Vector3(0, fy, -hz + WALL * 0.5), Vector3(sz.x, fhh, WALL))
	bx.call(Vector3(0, fy, hz - WALL * 0.5), Vector3(sz.x, fhh, WALL))
	bx.call(Vector3(-hx + WALL * 0.5, fy, 0), Vector3(WALL, fhh, sz.y))
	bx.call(Vector3(hx - WALL * 0.5, fy, 0), Vector3(WALL, fhh, sz.y))
	var furn := furnished(r)
	for k in range(0, n + 1):
		var y := level(k, p_gh, p_fh)
		if k >= 1:
			# slab around the stairwell hole (the roof too)
			for rr in _slab_rects(hx - WALL, hz - WALL, sw):
				var q: Rect2 = rr
				bx.call(Vector3(q.get_center().x, y - SLAB * 0.5, q.get_center().y), Vector3(q.size.x, SLAB, q.size.y))
		if k >= 1 and k < n:
			_core_boxes(bx, sw, y, level(k + 1, p_gh, p_fh) - SLAB)
		if k >= 1 and k < n:
			_stair_boxes(out, sw, y, level(k + 1, p_gh, p_fh))
		if furn.has(k) and k > 0 and k < n:
			for wall in office_walls(sz, sw):
				var a: Vector2 = wall[0]
				var b: Vector2 = wall[1]
				var c := (a + b) * 0.5
				var yy := level(k + 1, p_gh, p_fh) - SLAB
				bx.call(Vector3(c.x, (y + yy) * 0.5, c.y), Vector3(maxf(absf(b.x - a.x), 0.2), yy - y, maxf(absf(b.y - a.y), 0.2)))
			for dk in desks(sz, k):
				var p: Vector3 = dk
				bx.call(Vector3(p.x, y + 0.375, p.z), Vector3(1.6, 0.75, 0.8))
	# roof: the stair house walls (door gap south), its roof
	var yr := level(n, p_gh, p_fh)
	_core_boxes(bx, sw, yr, yr + 3.0)
	var x0 := float(sw["x0"]) - 0.2
	var x1 := float(sw["lift_x1"]) + 0.2
	var z0 := float(sw["z0"]) - 0.2
	var z1 := float(sw["z1"]) + 0.2
	bx.call(Vector3((x0 + x1) * 0.5, yr + 3.15, (z0 + z1) * 0.5), Vector3(x1 - x0 + 0.4, 0.3, z1 - z0 + 0.4))
	return out


## Core walls between y0 and y1: north, west, east, the stair | lift wall, the south wall around the stair door gap
## (x ∈ [x0 + 0.2, x0 + 1.2]) and its lintel; the lift shaft is solid.
static func _core_boxes(bx: Callable, sw: Dictionary, y0: float, y1: float) -> void:
	var x0 := float(sw["x0"]) - 0.2
	var x1 := float(sw["x1"]) + 0.2
	var lx1 := float(sw["lift_x1"]) + 0.2
	var z0 := float(sw["z0"]) - 0.2
	var z1 := float(sw["z1"]) + 0.2
	var yc := (y0 + y1) * 0.5
	var h := y1 - y0
	bx.call(Vector3((x0 + lx1) * 0.5, yc, z0), Vector3(lx1 - x0 + 0.2, h, 0.2))
	bx.call(Vector3(x0, yc, (z0 + z1) * 0.5), Vector3(0.2, h, z1 - z0))
	bx.call(Vector3(lx1, yc, (z0 + z1) * 0.5), Vector3(0.2, h, z1 - z0))
	bx.call(Vector3((x1 + lx1) * 0.5, yc, (z0 + z1) * 0.5), Vector3(lx1 - x1, h, z1 - z0))   # the lift shaft (solid)
	bx.call(Vector3(x0 + 0.2, yc, z1), Vector3(0.4, h, 0.2))
	bx.call(Vector3((x0 + 1.4 + x1) * 0.5, yc, z1), Vector3(x1 - (x0 + 1.4), h, 0.2))
	if h > 2.3:
		bx.call(Vector3(x0 + 0.9, (y0 + 2.2 + y1) * 0.5, z1), Vector3(1.0, y1 - (y0 + 2.2), 0.2))


## Ramp colliders of the two flights and the half landing from y0 to y1 (a CharacterBody walks up the ramps).
static func _stair_boxes(out: Array, sw: Dictionary, y0: float, y1: float) -> void:
	var x0 := float(sw["x0"])
	var x1 := float(sw["x1"])
	var z0 := float(sw["z0"])
	var z1 := float(sw["z1"])
	var half := (y1 - y0) * 0.5
	var ang := atan2(half, RUN)
	var ln := sqrt(RUN * RUN + half * half)
	# flight A rises toward −z: rotate about +x by +ang (its +z end goes down)
	var ca := Vector3(x0 + FLIGHT_W * 0.5, y0 + half * 0.5 - 0.1, z1 - LANDING - RUN * 0.5)
	out.append([ca, Vector3(FLIGHT_W, 0.2, ln), Basis(Vector3.RIGHT, ang), "box"])
	out.append([Vector3((x0 + x1) * 0.5, y0 + half - 0.1, z0 + LANDING * 0.5), Vector3(x1 - x0, 0.2, LANDING), Basis.IDENTITY, "box"])
	var cb := Vector3(x1 - FLIGHT_W * 0.5, y0 + half * 1.5 - 0.1, z0 + LANDING + RUN * 0.5)
	out.append([cb, Vector3(FLIGHT_W, 0.2, ln), Basis(Vector3.RIGHT, -ang), "box"])
	# the stair's eye (between the flights)
	var ex := x0 + FLIGHT_W
	var ex1 := x1 - FLIGHT_W
	out.append([Vector3((ex + ex1) * 0.5, (y0 + y1 - 0.3) * 0.5, (z0 + LANDING + z1 - LANDING) * 0.5), Vector3(ex1 - ex, y1 - y0 - 0.3, RUN), Basis.IDENTITY, "box"])


# ------------------------------------------------------------------ doors and spawns (both sides)
## Door leaves of the tower: [[name, hinge local Vector3 (y = 0), yaw, exterior, floor]] — the stair door and two
## office doors on every furnished floor above the lobby, the roof door of the stair house.
static func door_list(r: Dictionary) -> Array:
	var n := int(r["floors"])
	var sz := CityLots.v2(r["size"])
	var sw := stairwell(sz)
	var out: Array = []
	var i := 0
	for k in furnished(r):
		if k <= 0 or k >= n:
			continue
		out.append(["Door_%d" % i, Vector3(float(sw["x0"]) + 0.2, 0.0, float(sw["z1"]) + 0.2), 0.0, false, k])
		i += 1
		for od in office_doors(sz):
			var hp: Vector2 = od[0]
			out.append(["Door_%d" % i, Vector3(hp.x, 0.0, hp.y), float(od[1]), false, k])
			i += 1
	out.append(["Door_%d" % i, Vector3(float(sw["x0"]) + 0.2, 0.0, float(sw["z1"]) + 0.2), 0.0, true, n])
	return out


## Loot spawns: [[name, local position (on the floor), yaw, table]] — desks' drawers and a cabinet per furnished floor.
static func spawn_list(r: Dictionary) -> Array:
	var sz := CityLots.v2(r["size"])
	var p_gh := CityLots.cm(r.get("ground_h", 430))
	var p_fh := CityLots.cm(r.get("floor_h", 380))
	var n := int(r["floors"])
	var out: Array = []
	var i := 0
	var tables := [&"house", &"house_kitchen", &"pharmacy", &"police"]
	for k in furnished(r):
		var y := level(k, p_gh, p_fh)
		var ds := desks(sz, k)
		for j in mini(3, ds.size()):
			var p: Vector3 = ds[j]
			var tbl: StringName = tables[(k + j) % tables.size()]
			if k == n - 1:
				tbl = &"military"   # the command post that held out on the top floor
			out.append(["Spawn_Container_%02d" % i, Vector3(p.x, y, p.z + 0.85), PI, String(tbl)])
			i += 1
	return out


# ------------------------------------------------------------------ node
## `e` = the CityLots HERO item (pos, yaw, y, wid, seed).
func setup(e: Dictionary, p_visual: bool) -> void:
	item = e
	hero_id = int(e["id"])
	visual = p_visual
	rec = rec_of(hero_id)
	floors = int(rec["floors"])
	gh = CityLots.cm(rec.get("ground_h", 430))
	fh = CityLots.cm(rec.get("floor_h", 380))
	size = CityLots.v2(rec["size"])
	name = "hero_%d" % hero_id
	var p: Vector2 = e["pos"]
	position = Vector3(p.x, float(e["y"]), p.y)
	rotation.y = deg_to_rad(float(e["yaw"]))
	set_meta("floor_h", fh)
	set_meta("ground_h", gh)
	set_meta("foundation", FOUNDATION)
	set_meta("floors", floors)
	set_meta("generator", bool(rec.get("generator", false)))
	set_meta("enterable", true)
	set_meta("kind", "hero")
	set_meta("wid", int(e["wid"]))
	add_to_group("hero_tower")
	_seed = int(e.get("seed", 0))
	set_process(false)
	# the build as a list of small steps (CityChunk runs one per streaming step on clients: each ≤ ~1 ms; the
	# server runs them all now — its navigation and residents need the floors at once)
	_todo = [["lobby"]]
	var nd := door_list(rec).size()
	for i0 in range(0, nd, DOORS_PER_STEP):
		_todo.append(["doors", i0])
	_todo.append(["spawns"])
	for i0 in range(0, spawn_list(rec).size(), LOOT_PER_STEP):
		_todo.append(["loot", i0])
	if visual:
		var d := prepare(hero_id)
		var pieces: Array = ["ShadowProxy", "Base"]
		var ranges: Dictionary = d.get("ranges", {})
		for k in ranges:
			if str(k) != "Base":
				pieces.append(str(k))
		pieces.append("Roof")
		for nm in pieces:
			_todo.append(["mesh", nm])    # (a no-op once the piece's ArrayMesh is cached)
			_todo.append(["piece", nm])
		_todo.append(["attach"])
		# the upper-floor colliders after CityBuilding.attach: its walks over the geometries (materials, ranges,
		# cut groups) then never go through the 400–700 shapes of FloorsCol
		_floors_boxes = collider_boxes(rec, false)
		_floors_body = _body("FloorsCol", [], false)
		for i0 in range(0, _floors_boxes.size(), FLOORS_BATCH):
			_todo.append(["floors"])
	else:
		_todo.append(["floors_now"])
	if not visual:
		finish_now()


## Runs the next build step; true when the tower is complete (CityChunk calls it once per streaming step).
func build_step() -> bool:
	if _todo_i >= _todo.size():
		built = true
		return true
	var st: Array = _todo[_todo_i]
	_todo_i += 1
	match str(st[0]):
		"lobby":
			add_child(_body("ColBody", collider_boxes(rec, true), true))
		"floors_now":
			add_child(_body("FloorsCol", collider_boxes(rec, false), false))
		"doors":
			_add_doors(int(st[1]), DOORS_PER_STEP)
		"spawns":
			for sp in spawn_list(rec):
				var n := Node3D.new()
				n.name = str(sp[0])
				n.position = sp[1]
				n.rotation.y = float(sp[2])
				n.set_meta("extras", {"table": str(sp[3])})
				add_child(n)
				_spawns.append(n)
			_spawns.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name) < String(b.name))
		"loot":
			_add_loot(int(st[1]), LOOT_PER_STEP)
		"floors":
			_step_floors()
		"mesh":
			_piece_mesh(hero_id, str(st[1]))
		"piece":
			_add_piece(str(st[1]))
		"attach":
			CityBuilding.attach(self)
	if _todo_i >= _todo.size():
		built = true
	return built


## Kind of the next build step (the streamer keeps one cost estimate per kind: "hero:<kind>").
func next_kind() -> String:
	return str(_todo[_todo_i][0]) if _todo_i < _todo.size() else "done"


## Door leaves (the same mesh everywhere: KitDoor sizes its box from the leaf) and their KitDoors, `count` from i0.
func _add_doors(i0: int, count: int) -> void:
	var dl := door_list(rec)
	for i in range(i0, mini(i0 + count, dl.size())):
		var d: Array = dl[i]
		var leaf := MeshInstance3D.new()
		leaf.name = str(d[0])
		leaf.visible = visual
		var y := level(int(d[4]), gh, fh)
		# the leaf's vertices sit at the floor level; its node stays at y = 0 (the city shader reads the base there)
		leaf.mesh = _door_mesh_at(y)
		leaf.position = d[1]
		leaf.rotation.y = float(d[2])
		leaf.set_meta("extras", {"kind": "door", "exterior": bool(d[3]), "hinge": "L", "width": 1.0, "cut_group": "Walls%d_S" % int(d[4]), "floor": int(d[4])})
		add_child(leaf)
		var kd := KitDoor.new()
		kd.setup(leaf, KitDoor.wid_for(_seed, int(item["wid"]), i))
		add_child(kd)
		doors.append(kd)


## Loot containers `count` from i0 — exactly what LootSpawns.attach(self, self, wid, seed) makes (the spawns sorted by
## name, wid hash64(seed, GEN_LOOT, tower wid, i + 1), the spawn's table, its yaw), a few per step.
func _add_loot(i0: int, count: int) -> void:
	for i in range(i0, mini(i0 + count, _spawns.size())):
		var s: Node3D = _spawns[i]
		var extras: Dictionary = s.get_meta("extras", {})
		var c := LootContainer.new()
		c.setup(WorldConst.hash64(_seed, Loot.GEN_LOOT, int(item["wid"]), i + 1), StringName(str(extras.get("table", "campsite"))), false)
		c.transform = Transform3D(Basis(Vector3.UP, s.rotation.y), s.position)
		add_child(c)
		loot.append(c)
		containers += 1


func _ready() -> void:
	set_process(false)


## Client: FLOORS_BATCH more shapes into the (detached) FloorsCol body; the body enters the tree with the last batch.
func _step_floors() -> void:
	if _floors_body == null:
		return
	var n := mini(FLOORS_BATCH, _floors_boxes.size() - _floors_done)
	for i in n:
		_floors_body.add_child(_shape(_floors_boxes[_floors_done + i]))
	_floors_done += n
	if _floors_done >= _floors_boxes.size():
		add_child(_floors_body)
		_floors_body = null
		_floors_boxes = []


func _add_piece(nm: String) -> void:
	var mesh := _piece_mesh(hero_id, nm)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	var d := prepare(hero_id)
	var ranges: Dictionary = d.get("ranges", {})
	if nm.begins_with("Shaft_") and ranges.has(nm):
		mi.set_meta("floor_from", int(ranges[nm][0]))
		mi.set_meta("floor_to", int(ranges[nm][1]))
	add_child(mi)


## Builds every piece at once (tests, screenshots).
func finish_now() -> void:
	while not built:
		build_step()


func release() -> void:
	var cb := get_node_or_null("CityBuilding")
	if cb != null:
		CityCut.unregister(cb as CityBuilding)
	if _floors_body != null:
		_floors_body.free()   # never entered the tree
		_floors_body = null
	# (the ~900 nodes are freed by the chunk's teardown: CityChunk.free_last detaches the tower and CityWorld frees
	# it a few nodes per frame)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _floors_body != null:
		_floors_body.free()   # a tower freed before its upper colliders entered the tree
		_floors_body = null


## The ArrayMesh of one piece of a hero tower (Base, Shaft_<n>, Roof, ShadowProxy), made the first time it is
## asked for and cached (main thread; the arrays come from `prepare`, built in the ChunkJob worker). One piece per
## streaming step: making all of them at once is ≈ 25 ms.
static func _piece_mesh(id: int, nm: String) -> Mesh:
	var cache: Dictionary = _meshes.get(id, {})
	if cache.has(nm):
		return cache[nm]
	var d := prepare(id)
	if not d.has(nm):
		return null
	var mesh := ArrayMesh.new()
	if nm == "ShadowProxy":
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, d["ShadowProxy"])
		mesh.surface_set_material(0, Assets.get_shared_material())
	else:
		var pair: Array = d[nm]
		if not (pair[0] as Array).is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pair[0])
			mesh.surface_set_material(mesh.get_surface_count() - 1, Assets.get_shared_material())
		if not (pair[1] as Array).is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pair[1])
			mesh.surface_set_material(mesh.get_surface_count() - 1, CityProcedural.glass_material())
	cache[nm] = mesh
	_meshes[id] = cache
	return mesh


static var _door_meshes: Dictionary = {}


## A 1 m door leaf whose vertices start at `y` (hinge at x = 0, y = 0 of the node).
static func _door_mesh_at(y: float) -> ArrayMesh:
	var k := int(round(y * 100.0))
	if _door_meshes.has(k):
		return _door_meshes[k]
	var m := CityMesh.new()
	m.box(Vector3(0.5, y, 0.0), Vector3(0.96, 2.2, 0.08), Color(0.46, 0.48, 0.50), Color(0.5, 0.52, 0.54), 1.0, true)
	m.box(Vector3(0.85, y + 1.0, 0.07), Vector3(0.05, 0.05, 0.06), COL_IRON, COL_IRON)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.arrays())
	am.surface_set_material(0, Assets.get_shared_material())
	_door_meshes[k] = am
	return am


func _body(nm: String, boxes: Array, nav: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = nm
	body.collision_layer = CityChunk.LAYER
	body.collision_mask = 0
	if nav:
		body.add_to_group("nav_static")
	else:
		body.add_to_group("nav_floor")
	for b in boxes:
		body.add_child(_shape(b))
	return body


static func _shape(b: Array) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = b[1]
	cs.shape = bs
	cs.transform = Transform3D(b[2], b[0])
	return cs


# ------------------------------------------------------------------ queries
## World height of the walkable level of floor k (k = floors: the roof).
func floor_y(k: int) -> float:
	return global_position.y + level(k, gh, fh)


## Floor index at a world height (the half-metre tolerance of the city shader).
func floor_at_y(y: float) -> int:
	return clampi(int(ceil((y + 0.5 - global_position.y - gh) / fh)), 0, floors)


## Is the world point inside the tower's footprint (any floor, below the roof parapet + 3 m)?
func contains_point(p: Vector3) -> bool:
	var l := global_transform.affine_inverse() * p
	return absf(l.x) < size.x * 0.5 and absf(l.z) < size.y * 0.5 and l.y > -1.0 and l.y < level(floors, gh, fh) + 3.0


## A world point on floor k near the stair landing (tests, bots, the net scenario).
func landing_point(k: int, ahead: float = 1.5) -> Vector3:
	var sw := stairwell(size)
	var lp := Vector3(float(sw["x0"]) + 0.7, level(k, gh, fh) + 0.05, float(sw["z1"]) + 0.2 + ahead)
	return global_transform * lp
