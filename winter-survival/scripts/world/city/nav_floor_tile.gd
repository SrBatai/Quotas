class_name NavFloorTile
extends RefCounted
## One navigation tile of one floor of an enterable city building (C1, doc 09 §4.4 «Navmesh a escala de ciudad»,
## level «Planta de edificio»; R17). Server only. The street navmesh (NavBaker, per chunk) never bakes the upper
## floors of a hero tower (their colliders live in `FloorsCol`, outside the group nav_static); instead each floor k ≥ 1
## is baked on its own, lazily, only while a player is in the building or near its door, and only floors k−1 … k+1
## of each such player (CityNav). The tile holds the floor's slab and the stair up to just below the next slab (the
## height band [level_k − 0.5, level_{k+1} − 0.35]); a NavigationLink3D (`link`, created by CityNav when both tiles
## exist) joins the top of the flight to the landing of floor k + 1 — «las escaleras como enlaces». Bakes run in a
## WorkerThreadPool task from plain face arrays (2–8 ms each), at most CityNav.MAX_PER_SECOND per second.

var hero_id: int = 0
var floor_k: int = 0
var faces := PackedVector3Array()
var aabb := AABB()
var cell: float = 0.25
var nm: NavigationMesh
var region: RID
var task_id: int = -1
var usec: int = 0
var cancelled: bool = false
var last_wanted: float = 0.0


## Bake inputs from the tower (main thread): the world-space faces of the FloorsCol boxes that reach the band.
static func make(tower: HeroTower, k: int, p_cell: float) -> NavFloorTile:
	var t := NavFloorTile.new()
	t.hero_id = tower.hero_id
	t.floor_k = k
	t.cell = p_cell
	var y0 := HeroTower.level(k, tower.gh, tower.fh) - 0.5
	var y1 := HeroTower.level(k + 1, tower.gh, tower.fh) - 0.35
	var hx := tower.size.x * 0.5 + 1.0
	var hz := tower.size.y * 0.5 + 1.0
	var xf := tower.global_transform
	# the band in world space (the tower only turns about Y)
	var corners: Array[Vector3] = []
	for c in [Vector3(-hx, y0, -hz), Vector3(hx, y0, -hz), Vector3(hx, y0, hz), Vector3(-hx, y0, hz)]:
		corners.append(xf * c)
	var bb := AABB(corners[0], Vector3.ZERO)
	for c in corners:
		bb = bb.expand(c)
	bb = bb.expand(xf * Vector3(0, y1, 0))
	t.aabb = AABB(Vector3(bb.position.x, xf.origin.y + y0, bb.position.z), Vector3(bb.size.x, y1 - y0, bb.size.z))
	var body := tower.get_node_or_null("FloorsCol") as StaticBody3D
	if body == null:
		return t
	for cs in body.get_children():
		var shape := (cs as CollisionShape3D).shape as BoxShape3D
		if shape == null:
			continue
		var lxf := (cs as CollisionShape3D).transform
		var he := shape.size * 0.5
		# local vertical extent of the box (rotated ramps included)
		var lo := INF
		var hi := -INF
		for i in 8:
			var v := lxf * Vector3(he.x if i & 1 else -he.x, he.y if i & 2 else -he.y, he.z if i & 4 else -he.z)
			lo = minf(lo, v.y)
			hi = maxf(hi, v.y)
		if hi < y0 - 0.3 or lo > y1 + 2.5:
			continue
		t.faces.append_array(NavBaker.box_faces(xf * lxf, he))
	return t


func run() -> void:
	var t0 := Time.get_ticks_usec()
	var src := NavigationMeshSourceGeometryData3D.new()
	src.add_faces(faces, Transform3D.IDENTITY)
	nm = NavigationMesh.new()
	nm.cell_size = cell
	nm.cell_height = NavBaker.CELL_HEIGHT
	nm.agent_radius = maxf(NavBaker.AGENT_RADIUS, cell)
	nm.agent_height = NavBaker.AGENT_HEIGHT
	nm.agent_max_climb = NavBaker.MAX_CLIMB
	nm.agent_max_slope = NavBaker.MAX_SLOPE
	nm.region_min_size = 1.0
	nm.edge_max_error = 1.0
	nm.filter_baking_aabb = aabb
	if not cancelled:
		NavigationServer3D.bake_from_source_geometry_data(nm, src)
	usec = Time.get_ticks_usec() - t0


func polygon_count() -> int:
	return nm.get_polygon_count() if nm != null else 0
