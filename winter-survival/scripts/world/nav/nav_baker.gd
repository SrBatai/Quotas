class_name NavBaker
extends Node
## Server-only navigation mesh per chunk (ARQ v2 §10.1, PLAN C16, M4). When the streamer finishes a chunk on the
## server (dedicated or offline), its source geometry is gathered and baked by Recast off the main thread, then
## handed to NavigationServer3D as one region of the world's navigation map. The bake is clipped to the chunk
## (the Recast border lies outside it, so the polygons reach the seams) and neighbouring regions are stitched to the
## same seam vertices (NavTile), which NavigationServer3D merges exactly; the margin-based edge connections are off.
##
## Source geometry (built in code, never parsed from visual meshes):
##   - terrain: the 1 m height samples of the chunk + 3 m around it (HeightFunction.sample_block, pure);
##   - scatter colliders (trees, rocks, logs) of the chunk and of its loaded neighbours within the border, as
##     projected obstructions (eroded by the agent radius like any geometry);
##   - static colliders of hand-placed nodes (group `nav_static`: the clearing's cabin, A-frame, truck, fences,
##     signpost) and forest POIs (group `poi_prop`): boxes, convex hulls and trimeshes become faces (walls block,
##     floors and porches stay walkable), round shapes become obstructions.
## The main thread only collects compact arrays (≤ 4 ms); the worker builds the source data and bakes (20–85 ms per
## chunk at 0.25 m cells), one at a time, only while the streamer is idle (streaming first on shared cores) and not
## around a player moving at vehicle speed (FAST_SPEED). Felled trees mark their chunk dirty: re-baked after a 2 s
## cooldown. Only chunks of the ring around a player are baked (BAKE_RADIUS). Web (nothreads): 0.5 m cells, one
## synchronous bake per REBAKE_WEB_GAP s on the main thread.
## No NavigationAgent3D: ZombieSystem queries paths through NavQueryQueue.

signal chunk_baked(key: int)

const CELL := 0.25
const CELL_WEB := 0.5
const CELL_HEIGHT := 0.2
const AGENT_RADIUS := 0.5          # 0.4 m of the spec, ceiled to whole cells by Recast (2 × 0.25)
const AGENT_HEIGHT := 1.8
const MAX_CLIMB := 0.4
const MAX_SLOPE := 45.0
## Recast tile border = agent radius + 3 cells (the Recast tiled-mesh rule), and the baking AABB is the chunk grown
## by it (Godot keeps the non-navigable border inside `filter_baking_aabb`): the walkable-area erosion ends inside
## the border and the polygons reach the chunk edge, so neighbouring regions meet on the seam and the edge
## connections join them. Before (AABB = chunk, border = radius) the edges were eroded 0.5 m on both sides: a 1 m
## gap > the 0.5 m connection margin, no route crossed a chunk seam.
const BORDER_CELLS := 3
const EDGE_MARGIN := 0.5
const TERRAIN_PAD := 3             # metres of terrain baked around the chunk (≥ the border: 1.25 m, web 2 m)
const REBAKE_COOLDOWN := 2.0
const REBAKE_WEB_GAP := 0.3
## Only the chunks whose centre is within BAKE_RADIUS m of a player get a region (the ring around each player: the
## L0 zombies live within 40 m); the other loaded chunks wait in the queue. Smaller map, fewer bakes and map
## rebuilds (every region added or removed makes NavigationServer3D rebuild the map's polygons and connections).
const BAKE_RADIUS := 96.0
## Players faster than this (m/s: a vehicle; a runner zombie does 5.5) do not get their ring baked until they slow.
const FAST_SPEED := 8.0
const MAX_RUNNING := 1

static var instance: NavBaker

var enabled: bool = true
var map: RID
var cell: float = CELL
var world: World
## key -> RID of the chunk's navigation region.
var regions: Dictionary = {}
## Stats (tests / perf): bakes done, total/max worker µs, main-thread gather µs max.
var stats: Dictionary = {"baked": 0, "bake_usec": 0, "bake_usec_max": 0, "gather_usec_max": 0, "polygons": 0}

var _queue: Dictionary = {}        # key -> time (s) when it may be baked
var _running: Dictionary = {}      # key -> BakeJob
var _web_t: float = 0.0
var _static_cache: Dictionary = {} # node instance id -> Array of shape records
var _tiles: Dictionary = {}        # key -> NavTile (the editable copy of the region's mesh, seam stitching)
var _to_free: Array[RID] = []


## One chunk bake (worker): inputs are plain arrays, the output a NavigationMesh.
class BakeJob:
	extends RefCounted
	var key: int
	var cx: int
	var cz: int
	var hf: HeightFunction
	var cell: float
	var faces := PackedVector3Array()
	var obstructions: Array = []        # [PackedVector3Array poly (y ignored), elevation, height]
	var task_id: int = -1
	var nm: NavigationMesh
	var tile: NavTile
	var usec: int = 0
	var cancelled: bool = false

	func run() -> void:
		var t0 := Time.get_ticks_usec()
		var src := NavigationMeshSourceGeometryData3D.new()
		var n := WorldConst.SAMPLES + TERRAIN_PAD * 2 + 1
		var x0 := WorldConst.chunk_origin_i(cx) - TERRAIN_PAD
		var z0 := WorldConst.chunk_origin_i(cz) - TERRAIN_PAD
		var blk := hf.sample_block(x0, z0, n)
		var h: PackedFloat32Array = blk["h"]
		var tri := PackedVector3Array()
		tri.resize((n - 1) * (n - 1) * 6)
		var k := 0
		var ymin := INF
		var ymax := -INF
		for j in n - 1:
			for i in n - 1:
				var fx := float(x0 + i)
				var fz := float(z0 + j)
				var a := Vector3(fx, h[j * n + i], fz)
				var b := Vector3(fx + 1.0, h[j * n + i + 1], fz)
				var c := Vector3(fx, h[(j + 1) * n + i], fz + 1.0)
				var d := Vector3(fx + 1.0, h[(j + 1) * n + i + 1], fz + 1.0)
				tri[k] = a
				tri[k + 1] = b
				tri[k + 2] = c
				tri[k + 3] = b
				tri[k + 4] = d
				tri[k + 5] = c
				k += 6
				ymin = minf(ymin, a.y)
				ymax = maxf(ymax, a.y)
		src.add_faces(tri, Transform3D.IDENTITY)
		if not faces.is_empty():
			src.add_faces(faces, Transform3D.IDENTITY)
			for f in faces:
				ymax = maxf(ymax, f.y)
		for o in obstructions:
			src.add_projected_obstruction(o[0], float(o[1]), float(o[2]), false)
		if cancelled:
			return
		nm = NavigationMesh.new()
		nm.cell_size = cell
		nm.cell_height = CELL_HEIGHT
		nm.agent_radius = maxf(AGENT_RADIUS, cell)
		nm.agent_height = AGENT_HEIGHT
		nm.agent_max_climb = MAX_CLIMB
		nm.agent_max_slope = MAX_SLOPE
		nm.border_size = maxf(AGENT_RADIUS, cell) + BORDER_CELLS * cell
		nm.region_min_size = 4.0
		nm.edge_max_error = 1.0   # ≤ 1 keeps the simplified contours on the tile edges (NavigationMesh.border_size)
		nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		var o := WorldConst.chunk_origin(cx, cz)
		# Godot keeps the border inside the baking AABB: grow the AABB by it so the polygons end on the chunk edge;
		# the AABB floor sits on the global cell_height lattice so neighbours quantise heights alike
		var bd := nm.border_size
		var yb := floorf((ymin - 4.0) / CELL_HEIGHT) * CELL_HEIGHT
		nm.filter_baking_aabb = AABB(Vector3(o.x - bd, yb, o.y - bd), Vector3(WorldConst.CHUNK_SIZE + 2.0 * bd, ymax - yb + 8.0, WorldConst.CHUNK_SIZE + 2.0 * bd))
		NavigationServer3D.bake_from_source_geometry_data(nm, src)
		tile = NavTile.from_mesh(key, nm, o.x, o.y)
		usec = Time.get_ticks_usec() - t0


## A chunk's baked polygons kept editable for the seam stitching (ARQ v2 §10.7). Sides: 0 west (x = x0), 1 east
## (x = x0 + CHUNK_SIZE), 2 north (z = z0), 3 south (z = z0 + CHUNK_SIZE).
##
## Why: NavigationServer3D's `edge_connection_margin` search compares every free edge of the map with every other
## one (every tree hole is outlined by free edges): 150–230 ms per map rebuild with 9 chunks, and the map is rebuilt
## on every region change. Exact edge merging is ~1 ms but needs both sides of a seam to have the same vertices:
## after a bake, each seam of the new tile and of its baked neighbour get the union of both vertex sets (collinear
## vertices inserted into the seam edges; coincident ones copied bit-exact), then both regions are updated.
class NavTile:
	extends RefCounted
	const SNAP := 0.02
	var key: int
	var nm: NavigationMesh
	var verts: PackedVector3Array
	var polys: Array = []              # PackedInt32Array per polygon
	var x0: float
	var z0: float
	var side_polys: Array = [[], [], [], []]

	static func from_mesh(p_key: int, p_nm: NavigationMesh, ox: float, oz: float) -> NavTile:
		var t := NavTile.new()
		t.key = p_key
		t.nm = p_nm
		t.x0 = ox
		t.z0 = oz
		var x1 := ox + WorldConst.CHUNK_SIZE
		var z1 := oz + WorldConst.CHUNK_SIZE
		t.verts = p_nm.vertices
		for i in t.verts.size():
			var v := t.verts[i]
			if absf(v.x - ox) < SNAP:
				v.x = ox
			elif absf(v.x - x1) < SNAP:
				v.x = x1
			if absf(v.z - oz) < SNAP:
				v.z = oz
			elif absf(v.z - z1) < SNAP:
				v.z = z1
			t.verts[i] = v
		for pi in p_nm.get_polygon_count():
			var poly := p_nm.get_polygon(pi)
			t.polys.append(poly)
			for side in 4:
				for k in poly.size():
					if t.on_side(t.verts[poly[k]], side) and t.on_side(t.verts[poly[(k + 1) % poly.size()]], side):
						t.side_polys[side].append(pi)
						break
		return t

	func seam_coord(side: int) -> float:
		match side:
			0: return x0
			1: return x0 + WorldConst.CHUNK_SIZE
			2: return z0
		return z0 + WorldConst.CHUNK_SIZE

	func on_side(v: Vector3, side: int) -> bool:
		return (v.x if side < 2 else v.z) == seam_coord(side)

	static func along(v: Vector3, side: int) -> float:
		return v.z if side < 2 else v.x

	## Vertex index per seam point on `side`, keyed by the coordinate along the seam (mm).
	func seam_points(side: int) -> Dictionary:
		var out := {}
		for pi in side_polys[side]:
			for vi in polys[pi]:
				if on_side(verts[vi], side):
					out[roundi(along(verts[vi], side) * 1000.0)] = vi
		return out

	## Inserts the positions `pts` (on the seam, not yet in this tile) into the seam edges that span them.
	func insert(side: int, pts: Array) -> int:
		if pts.is_empty():
			return 0
		var added := 0
		var index := {}
		for pi in side_polys[side]:
			var poly: PackedInt32Array = polys[pi]
			var out := PackedInt32Array()
			var n := poly.size()
			for k in n:
				var a := poly[k]
				var b := poly[(k + 1) % n]
				out.append(a)
				var va := verts[a]
				var vb := verts[b]
				if not (on_side(va, side) and on_side(vb, side)):
					continue
				var ca := along(va, side)
				var cb := along(vb, side)
				var lo := minf(ca, cb) + 0.001
				var hi := maxf(ca, cb) - 0.001
				var mid: Array = []
				for q in pts:
					var cq := along(q, side)
					if cq > lo and cq < hi:
						mid.append(q)
				if mid.is_empty():
					continue
				mid.sort_custom(func(p: Vector3, r: Vector3) -> bool: return (along(p, side) < along(r, side)) == (ca < cb))
				for q in mid:
					var qk := roundi(along(q, side) * 1000.0)
					if not index.has(qk):
						verts.append(q)
						index[qk] = verts.size() - 1
						added += 1
					out.append(int(index[qk]))
			polys[pi] = out
		return added

	func publish() -> void:
		nm.vertices = verts
		nm.set("polygons", polys)


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null
	for k in _running:
		var j: BakeJob = _running[k]
		j.cancelled = true
		if j.task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(j.task_id)
	_running.clear()
	for k in regions:
		NavigationServer3D.free_rid(regions[k])
	regions.clear()
	_tiles.clear()
	for rid in _to_free:
		NavigationServer3D.free_rid(rid)
	_to_free.clear()


## Called by ZombieSystem (server) once the world is configured.
func setup(p_world: World) -> void:
	world = p_world
	cell = CELL_WEB if (OS.has_feature("web") or not WorldStreamer.threads_ok()) else CELL
	map = world.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, cell)
	NavigationServer3D.map_set_cell_height(map, CELL_HEIGHT)
	NavigationServer3D.map_set_edge_connection_margin(map, EDGE_MARGIN)
	# seams are stitched to exact vertices (NavTile): no margin search over every free edge of the map
	NavigationServer3D.map_set_use_edge_connections(map, false)
	world.streamer.chunk_loaded.connect(_on_chunk_loaded)
	world.streamer.chunk_unloaded.connect(_on_chunk_unloaded)
	for k in world.streamer.loaded_keys():
		_on_chunk_loaded(k)


func _on_chunk_loaded(key: int) -> void:
	if enabled:
		_queue[key] = 0.0


func _on_chunk_unloaded(key: int) -> void:
	_queue.erase(key)
	if _running.has(key):
		(_running[key] as BakeJob).cancelled = true
	_tiles.erase(key)
	if regions.has(key):
		_to_free.append(regions[key])   # freed from _process: streamer callbacks stay O(1)
		regions.erase(key)


## Geometry changed around `pos` (a tree felled, a structure placed): re-bake its chunk after the cooldown.
func mark_dirty(pos: Vector3) -> void:
	mark_dirty_key(WorldConst.key_of(pos))


func mark_dirty_key(key: int) -> void:
	if world != null and world.streamer.chunks.has(key):
		_queue[key] = Time.get_ticks_msec() / 1000.0 + REBAKE_COOLDOWN


func has_region(key: int) -> bool:
	return regions.has(key)


## True when the chunk under `pos` has a baked region (paths are meaningful there).
func ready_at(pos: Vector3) -> bool:
	return regions.has(WorldConst.key_of(pos))


func is_idle() -> bool:
	return _queue.is_empty() and _running.is_empty()


func _process(delta: float) -> void:
	if not _to_free.is_empty():
		for rid in _to_free:
			NavigationServer3D.free_rid(rid)
		_to_free.clear()
	if world == null or not enabled:
		return
	_collect()
	if _queue.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var threaded := WorldStreamer.threads_ok()
	if not threaded:
		_web_t -= delta
		if _web_t > 0.0:
			return
	# nearest chunks to a player first
	var best_k := -1
	var best_d := INF
	for k in _queue:
		if float(_queue[k]) > now or _running.has(k):
			continue
		var d := _player_dist(k)
		if d < best_d:
			best_d = d
			best_k = k
	if best_k < 0 or (threaded and (_running.size() >= MAX_RUNNING or world.streamer.is_busy())):
		return   # streaming first: a bake never starts while chunks are generated or instantiated (shared cores)
	if best_d > BAKE_RADIUS:
		return   # nobody near: stays queued (web: each bake is a 20–55 ms hitch on the only thread)
	if _fast_near(best_k):
		return   # a vehicle-speed player (> FAST_SPEED): zombies cannot follow; the ring is baked once it slows
	var job := _make_job(best_k)
	_queue.erase(best_k)
	if job == null:
		return
	if threaded:
		job.task_id = WorkerThreadPool.add_task(job.run, false, "nav %d,%d" % [job.cx, job.cz])
		_running[best_k] = job
	else:
		_web_t = REBAKE_WEB_GAP
		job.run()
		_apply(job)


## True when every player within BAKE_RADIUS of the chunk moves faster than FAST_SPEED (driving, M7; the perf walk).
func _fast_near(key: int) -> bool:
	var c := WorldConst.chunk_center(WorldConst.key_cx(key), WorldConst.key_cz(key))
	var players := world.get_node_or_null("Players")
	if players == null:
		return false
	var any := false
	for p in players.get_children():
		var pl := p as Player
		if pl == null or Vector2(c.x - pl.global_position.x, c.z - pl.global_position.z).length() > BAKE_RADIUS:
			continue
		if Vector2(pl.velocity.x, pl.velocity.z).length() <= FAST_SPEED:
			return false
		any = true
	return any


func _player_dist(key: int) -> float:
	var c := WorldConst.chunk_center(WorldConst.key_cx(key), WorldConst.key_cz(key))
	var best := INF
	var players := world.get_node_or_null("Players")
	if players != null:
		for p in players.get_children():
			if p is Node3D:
				best = minf(best, Vector2(c.x - (p as Node3D).global_position.x, c.z - (p as Node3D).global_position.z).length())
	return best


func _collect() -> void:
	for k in _running.keys():
		var j: BakeJob = _running[k]
		if WorkerThreadPool.is_task_completed(j.task_id):
			WorkerThreadPool.wait_for_task_completion(j.task_id)
			_running.erase(k)
			if not j.cancelled and world.streamer.chunks.has(k):
				_apply(j)


func _apply(j: BakeJob) -> void:
	if j.nm == null or j.tile == null:
		return
	var rid: RID = regions.get(j.key, RID())
	if not rid.is_valid():
		rid = NavigationServer3D.region_create()
		NavigationServer3D.region_set_map(rid, map)
		NavigationServer3D.region_set_use_edge_connections(rid, false)
		regions[j.key] = rid
	var t0 := Time.get_ticks_usec()
	_tiles[j.key] = j.tile
	var touched := _stitch(j.tile)
	j.tile.publish()
	NavigationServer3D.region_set_navigation_mesh(rid, j.nm)
	for nk in touched:
		var nt: NavTile = _tiles[nk]
		nt.publish()
		NavigationServer3D.region_set_navigation_mesh(regions[nk], nt.nm)
	stats["stitch_usec_max"] = maxi(int(stats.get("stitch_usec_max", 0)), Time.get_ticks_usec() - t0)
	stats["baked"] = int(stats["baked"]) + 1
	stats["bake_usec"] = int(stats["bake_usec"]) + j.usec
	stats["bake_usec_max"] = maxi(int(stats["bake_usec_max"]), j.usec)
	stats["polygons"] = int(stats["polygons"]) + j.nm.get_polygon_count()
	chunk_baked.emit(j.key)


## Gives the seams of `t` and of its baked neighbours the same vertices (see NavTile). Returns the neighbour keys
## whose polygons changed (their regions are updated too).
func _stitch(t: NavTile) -> Array:
	var touched: Array = []
	var cx := WorldConst.key_cx(t.key)
	var cz := WorldConst.key_cz(t.key)
	# side of t → (neighbour, its facing side)
	var nb := [[WorldConst.key(cx - 1, cz), 1], [WorldConst.key(cx + 1, cz), 0], [WorldConst.key(cx, cz - 1), 3], [WorldConst.key(cx, cz + 1), 2]]
	for side in 4:
		var nk: int = nb[side][0]
		var ns: int = nb[side][1]
		var n: NavTile = _tiles.get(nk)
		if n == null:
			continue
		var pt := t.seam_points(side)
		var pn := n.seam_points(ns)
		var to_t: Array = []
		var to_n: Array = []
		var changed := false
		for k in pn:
			if pt.has(k):
				# the same point on both sides: copy it bit-exact (float noise would split the merge key)
				var vt: Vector3 = t.verts[pt[k]]
				var vn: Vector3 = n.verts[pn[k]]
				if absf(vt.y - vn.y) < 0.35 and vt != vn:
					n.verts[pn[k]] = vt
					changed = true
			else:
				to_t.append(n.verts[pn[k]])
		for k in pt:
			if not pn.has(k):
				to_n.append(t.verts[pt[k]])
		t.insert(side, to_t)
		if n.insert(ns, to_n) > 0 or changed:
			touched.append(nk)
	return touched


## Synchronous bake of the chunks around `pos` (tests / tools): returns how many were baked.
func bake_now(pos: Vector3, radius: int = 1) -> int:
	var n := 0
	for k in WorldConst.ring_keys(WorldConst.chunk_of(pos.x), WorldConst.chunk_of(pos.z), radius):
		if not world.streamer.chunks.has(k):
			continue
		if _running.has(k):
			var r: BakeJob = _running[k]
			WorkerThreadPool.wait_for_task_completion(r.task_id)
			_running.erase(k)
			_apply(r)
			n += 1
			continue
		if regions.has(k) and not _queue.has(k):
			continue
		var j := _make_job(k)
		_queue.erase(k)
		if j != null:
			j.run()
			_apply(j)
			n += 1
	return n


# ------------------------------------------------------------------ source gathering (main thread)
func _make_job(key: int) -> BakeJob:
	var t0 := Time.get_ticks_usec()
	var ch: WorldChunk = world.streamer.chunks.get(key)
	if ch == null or ch.data == null:
		return null
	var j := BakeJob.new()
	j.key = key
	j.cx = WorldConst.key_cx(key)
	j.cz = WorldConst.key_cz(key)
	j.hf = world.hf
	j.cell = cell
	var rect := WorldConst.chunk_rect(j.cx, j.cz).grow(float(TERRAIN_PAD))
	# scatter colliders of this chunk and its loaded neighbours
	for k in WorldConst.ring_keys(j.cx, j.cz, 1):
		var c: WorldChunk = world.streamer.chunks.get(k)
		if c == null or c.data == null:
			continue
		var n := c.data.entries.size()
		for i in n:
			if c.removed[i] == 1:
				continue
			var e: Dictionary = c.data.entries[i]
			var x := float(e["x"])
			var z := float(e["z"])
			if not rect.grow(3.5).has_point(Vector2(x, z)):
				continue
			_add_entry_obstruction(j, e)
	# static colliders of hand-placed nodes / POIs
	for g in ["nav_static", "poi_prop"]:
		for node in get_tree().get_nodes_in_group(g):
			if node is Node3D and (node as Node3D).is_inside_tree():
				_add_static(j, node as Node3D, rect)
	stats["gather_usec_max"] = maxi(int(stats["gather_usec_max"]), Time.get_ticks_usec() - t0)
	return j


func _add_entry_obstruction(j: BakeJob, e: Dictionary) -> void:
	var v := int(e["v"])
	if v < 0:
		return
	var var_d := ScatterCatalog.variant(v)
	if int(var_d["layer"]) & 1 == 0:
		return
	var col: Dictionary = var_d["col"]
	var t := str(col.get("t", ""))
	if t == "":
		return
	var s := float(e["s"])
	var sz: Array = col.get("s", [])
	var cpos: Vector3 = col.get("c", Vector3.ZERO)
	var yaw := float(e["yaw"])
	var base := Vector3(float(e["x"]), float(e["y"]), float(e["z"]))
	var center := base + Basis(Vector3.UP, yaw) * (cpos * s)
	match t:
		"cyl", "sphere":
			var r := float(sz[0]) * s
			var height := float(sz[1]) * s if t == "cyl" else r * 2.0
			j.obstructions.append([_circle(center, r), center.y - height * 0.5 - 0.3, height + 0.6])
		"box":
			var hx := float(sz[0]) * s * 0.5
			var hy := float(sz[1]) * s
			var hz := float(sz[2]) * s * 0.5
			var poly := PackedVector3Array()
			var bas := Basis(Vector3.UP, yaw)
			for p in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]:
				poly.append(center + bas * p)
			j.obstructions.append([poly, center.y - hy * 0.5 - 0.3, hy + 0.6])


static func _circle(c: Vector3, r: float) -> PackedVector3Array:
	var poly := PackedVector3Array()
	for q in 8:
		var a := TAU * float(q) / 8.0
		poly.append(Vector3(c.x + cos(a) * r, c.y, c.z + sin(a) * r))
	return poly


## Shape records of a static node, cached (static bodies do not move): [shape, global transform, world AABB].
func _shapes_of(node: Node3D) -> Array:
	var id := node.get_instance_id()
	if _static_cache.has(id):
		return _static_cache[id]
	var out: Array = []
	_find_shapes(node, out)
	_static_cache[id] = out
	node.tree_exiting.connect(func() -> void: _static_cache.erase(id), CONNECT_ONE_SHOT)
	return out


func _find_shapes(n: Node, out: Array) -> void:
	if n is CollisionShape3D and n.get_parent() is StaticBody3D:
		var body := n.get_parent() as StaticBody3D
		var cs := n as CollisionShape3D
		if cs.shape != null and not cs.disabled and (body.collision_layer & 1) != 0 and not (cs.shape is HeightMapShape3D):
			var xf := cs.global_transform
			out.append([cs.shape, xf, xf * _local_aabb(cs.shape)])
	for c in n.get_children():
		if c is Area3D or c is CharacterBody3D or c is RigidBody3D:
			continue
		_find_shapes(c, out)


static func _local_aabb(sh: Shape3D) -> AABB:
	if sh is BoxShape3D:
		var s := (sh as BoxShape3D).size
		return AABB(-s * 0.5, s)
	if sh is ConvexPolygonShape3D:
		var pts := (sh as ConvexPolygonShape3D).points
		var a := AABB(pts[0], Vector3.ZERO) if pts.size() > 0 else AABB()
		for p in pts:
			a = a.expand(p)
		return a
	if sh is ConcavePolygonShape3D:
		var f := (sh as ConcavePolygonShape3D).get_faces()
		var a := AABB(f[0], Vector3.ZERO) if f.size() > 0 else AABB()
		for p in f:
			a = a.expand(p)
		return a
	if sh is CylinderShape3D:
		var c := sh as CylinderShape3D
		return AABB(Vector3(-c.radius, -c.height * 0.5, -c.radius), Vector3(c.radius * 2, c.height, c.radius * 2))
	if sh is SphereShape3D:
		var r := (sh as SphereShape3D).radius
		return AABB(Vector3(-r, -r, -r), Vector3(r, r, r) * 2.0)
	if sh is CapsuleShape3D:
		var cp := sh as CapsuleShape3D
		return AABB(Vector3(-cp.radius, -cp.height * 0.5, -cp.radius), Vector3(cp.radius * 2, cp.height, cp.radius * 2))
	return AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)


func _add_static(j: BakeJob, node: Node3D, rect: Rect2) -> void:
	for rec in _shapes_of(node):
		var ab: AABB = rec[2]
		if not Rect2(ab.position.x, ab.position.z, ab.size.x, ab.size.z).intersects(rect):
			continue
		var sh: Shape3D = rec[0]
		var xf: Transform3D = rec[1]
		if sh is BoxShape3D:
			j.faces.append_array(box_faces(xf, (sh as BoxShape3D).size * 0.5))
		elif sh is ConvexPolygonShape3D:
			j.faces.append_array(hull_faces(xf, (sh as ConvexPolygonShape3D).points))
		elif sh is ConcavePolygonShape3D:
			for p in (sh as ConcavePolygonShape3D).get_faces():
				j.faces.append(xf * p)
		else:
			var r := maxf(ab.size.x, ab.size.z) * 0.5
			j.obstructions.append([_circle(ab.get_center(), r), ab.position.y - 0.3, ab.size.y + 0.6])


## 12 triangles of an oriented box (half extents `he`) in world space.
static func box_faces(xf: Transform3D, he: Vector3) -> PackedVector3Array:
	var c: Array[Vector3] = []
	for i in 8:
		c.append(xf * Vector3(he.x if i & 1 else -he.x, he.y if i & 2 else -he.y, he.z if i & 4 else -he.z))
	var quads := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	var out := PackedVector3Array()
	for q in quads:
		out.append_array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]])
	return out


## Faces of the convex hull of a small point set (brute force: fine for the ≤ 16-point collision hulls of the kit).
static func hull_faces(xf: Transform3D, pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := pts.size()
	for a in n:
		for b in range(a + 1, n):
			for c in range(b + 1, n):
				var nrm := (pts[b] - pts[a]).cross(pts[c] - pts[a])
				if nrm.length_squared() < 1e-8:
					continue
				var pos := false
				var neg := false
				for d in n:
					var s := nrm.dot(pts[d] - pts[a])
					if s > 1e-4:
						pos = true
					elif s < -1e-4:
						neg = true
				if pos and neg:
					continue
				out.append_array([xf * pts[a], xf * pts[b], xf * pts[c]])
	return out
