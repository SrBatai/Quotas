class_name WorldChunk
extends Node3D
## One loaded 64 m chunk (ARQ v2 §8.3–8.6): built from a ChunkJob in small main-thread steps (the streamer
## calls `step()` inside its 2 ms/frame budget). Holds the terrain collider (HeightMapShape3D), the terrain mesh
## (client), the scatter physics (one StaticBody3D per collision layer with a shape owner per entry), the
## MultiMeshes (client, one per 32 m block × variant) and the node objects (pickups, berry bushes, POI props,
## stumps). Choppable scatter entries are materialized into a real ChoppableTree only when needed (hover, a
## request, an event); the MultiMesh instance is hidden meanwhile and the collision shape disabled.

## Scenes are loaded lazily (not preloaded): World → WorldChunk → tree.tscn → interactable.gd → Player → World
## would be a preload cycle.
const TREE_PATH := "res://scenes/world/tree.tscn"
const STUMP_PATH := "res://scenes/world/stump.tscn"
const PICKUP_PATH := "res://scenes/world/pickup.tscn"
const BUSH_PATH := "res://scenes/world/berry_bush.tscn"
static var _scenes: Dictionary = {}
const N := WorldConst.SAMPLES
const NODES_PER_STEP := 1
const MM_PER_STEP := 1
## Scatter shapes per build step (each step builds its own bodies off-tree, then adds them).
const SHAPES_PER_STEP := 24
## Untouched materialized trees go back to the MultiMesh after this many seconds (hover sweeps).
const DEMATERIALIZE_AFTER := 6.0

enum State { BUILDING, LOADED }

static var _index_cache := PackedInt32Array()
static var _shapes: Dictionary = {}

var cx: int = 0
var cz: int = 0
var key: int = 0
var data: ChunkJob
var visual: bool = true
var with_nodes: bool = true
var state: int = State.BUILDING
var region: String = ""
var build_usec: int = 0
var terrain_body: StaticBody3D
var terrain_mesh: MeshInstance3D           # first quadrant (compat for callers); all four in terrain_meshes
var terrain_meshes: Array[MeshInstance3D] = []
var _mesh_cursor: int = 0
var objects: Node3D
## entry -> [mm key, instance] (-1 when not in a MultiMesh)
var entry_mm := PackedInt32Array()
var entry_inst := PackedInt32Array()
## entry -> shape owner id (-1 none) and its body index (0 solid 65, 1 blocker 64, 2 ground 1)
var entry_owner := PackedInt32Array()
var entry_body := PackedByteArray()
var removed := PackedByteArray()
## wid -> entry index (choppable entries only)
var wid_index: Dictionary = {}
var materialized: Dictionary = {}       # entry -> ChoppableTree
var _touched: Dictionary = {}           # entry -> last time it was needed (s)
var _bodies: Array[StaticBody3D] = []
var _owner_entry_by_body: Dictionary = {}   # body -> {owner id: entry}
var _entry_body_ref: Dictionary = {}        # entry -> body
var _shape_cursor: int = 0
var _mmis: Dictionary = {}              # mm key -> MultiMeshInstance3D
var _steps: Array[Callable] = []
var _step_i: int = 0
var _node_cursor: int = 0
var _mm_cursor: int = 0
var _sweep_t: float = 0.0


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


func setup(job: ChunkJob, p_visual: bool, p_with_nodes: bool) -> void:
	data = job
	cx = job.cx
	cz = job.cz
	key = job.key
	visual = p_visual
	with_nodes = p_with_nodes
	region = job.region
	name = "c_%d_%d" % [cx, cz]
	var n := data.entries.size()
	entry_mm.resize(n)
	entry_mm.fill(-1)
	entry_inst.resize(n)
	entry_inst.fill(-1)
	entry_owner.resize(n)
	entry_owner.fill(-1)
	entry_body.resize(n)
	removed.resize(n)
	for i in n:
		var e: Dictionary = data.entries[i]
		if ScatterCatalog.is_choppable(int(e["v"])):
			wid_index[int(e["wid"])] = i
		if bool(e["felled"]):
			removed[i] = 1
	_steps = [_step_deltas, _step_collision]
	if visual:
		_steps.append(_step_mesh)
	_steps.append(_step_shapes)
	if visual:
		_steps.append(_step_multimesh)
	if with_nodes:
		_steps.append(_step_nodes)
	_steps.append(_step_done)


## Runs the next build step; returns true when the chunk is fully built.
func step() -> bool:
	if state == State.LOADED:
		return true
	var t0 := Time.get_ticks_usec()
	var advance: bool = _steps[_step_i].call()
	build_usec += Time.get_ticks_usec() - t0
	if advance:
		_step_i += 1
	return state == State.LOADED


## Unloading (streamer): hidden and inert at once, then freed a few nodes per frame (teardown_step).
func begin_teardown() -> void:
	visible = false
	set_process(false)
	for b in _bodies:
		b.collision_layer = 0
	if objects != null:
		for o in objects.get_children():
			WorldRegistry.unregister(o)


## Frees children, then the chunk data piece by piece, until `budget_usec` is spent; true when nothing is left
## (the streamer then frees the empty chunk node).
func teardown_step(budget_usec: int) -> bool:
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < budget_usec:
		var n := get_child_count()
		if n > 0:
			var c := get_child(n - 1)
			if c == objects and objects.get_child_count() > 0:
				objects.get_child(objects.get_child_count() - 1).free()
				continue
			remove_child(c)
			c.free()
			continue
		# big arrays / dictionaries released one at a time (freeing a whole chunk's data at once costs ms)
		if data == null:
			return true
		if not data.entries.is_empty():
			data.entries = data.entries.slice(0, maxi(data.entries.size() - 64, 0))
		elif not data.occluders.is_empty():
			data.occluders = []
		elif not data.quad_verts.is_empty():
			data.quad_verts.pop_back()
			data.quad_normals.pop_back()
			data.quad_custom.pop_back()
			data.quad_colors.pop_back()
		elif not data.mm.is_empty():
			data.mm = {}
		else:
			wid_index = {}
			_owner_entry_by_body = {}
			_entry_body_ref = {}
			materialized = {}
			data = null
	return get_child_count() == 0 and data == null


## Name of the next build step (streaming budget statistics).
func step_kind() -> String:
	return String(_steps[_step_i].get_method()) if _step_i < _steps.size() else "done"


func build_all() -> void:
	while not step():
		pass


# ------------------------------------------------------------------ build steps (each returns true when finished)
## Trees felled since the job snapshot: hide + AO before the mesh is uploaded.
func _step_deltas() -> bool:
	objects = Node3D.new()
	objects.name = "Objects"
	add_child(objects)
	var nw := NetWorld.instance
	if nw == null:
		return true
	for w in wid_index:
		var i: int = wid_index[w]
		if removed[i] == 0 and bool(nw.delta_of(w).get("felled", false)):
			removed[i] = 1
			data.entries[i]["felled"] = true
			_swap_occluder(i, true, false)
	return true


func _step_collision() -> bool:
	terrain_body = StaticBody3D.new()
	terrain_body.name = "Ground"
	terrain_body.collision_layer = 1
	terrain_body.collision_mask = 0
	terrain_body.add_to_group("terrain")
	var shape := HeightMapShape3D.new()
	shape.map_width = N
	shape.map_depth = N
	shape.map_data = data.heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	terrain_body.add_child(cs)
	var c := WorldConst.chunk_center(cx, cz)
	terrain_body.position = Vector3(c.x, 0.0, c.z)
	add_child(terrain_body)
	return true


## One terrain quadrant (33 × 33 vertices, arrays prepared by the worker) per step.
func _step_mesh() -> bool:
	var q := _mesh_cursor
	var mi := MeshInstance3D.new()
	mi.name = "Terrain_%d" % q
	mi.mesh = ArrayMesh.new()
	mi.material_override = Assets.get_terrain_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if Quality.allows("terrain_shadows") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	terrain_meshes.append(mi)
	if q == 0:
		terrain_mesh = mi
	_upload_quad(q)
	_mesh_cursor += 1
	return _mesh_cursor >= 4


static func shared_index() -> PackedInt32Array:
	if _index_cache.is_empty():
		var qn := ChunkJob.QN
		var cs := qn - 1
		_index_cache.resize(cs * cs * 6)
		var k := 0
		for iz in cs:
			for ix in cs:
				var a := iz * qn + ix
				var b := a + 1
				var c := a + qn
				var d := c + 1
				_index_cache[k] = a
				_index_cache[k + 1] = b
				_index_cache[k + 2] = c
				_index_cache[k + 3] = b
				_index_cache[k + 4] = d
				_index_cache[k + 5] = c
				k += 6
	return _index_cache


func _upload_quad(q: int) -> void:
	if q >= terrain_meshes.size():
		return
	if data.quad_colors[q].size() != ChunkJob.QN * ChunkJob.QN:
		data.quad_colors[q] = data.quad_colors_of(q)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.quad_verts[q]
	arrays[Mesh.ARRAY_NORMAL] = data.quad_normals[q]
	arrays[Mesh.ARRAY_COLOR] = data.quad_colors[q]
	arrays[Mesh.ARRAY_CUSTOM0] = data.quad_custom[q]
	arrays[Mesh.ARRAY_INDEX] = shared_index()
	var mesh := terrain_meshes[q].mesh as ArrayMesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)


## Re-uploads the quadrants touched by `rect` (world metres; all when empty) from the current AO.
func rebuild_mesh(rect: Rect2 = Rect2()) -> void:
	var o := WorldConst.chunk_origin(cx, cz)
	for q in terrain_meshes.size():
		var qr := Rect2(o + Vector2(float(q % 2), float(q / 2)) * 32.0, Vector2(32.0, 32.0)).grow(1.0)
		if rect.size != Vector2.ZERO and not qr.intersects(rect):
			continue
		data.quad_colors[q] = PackedColorArray()
		_upload_quad(q)


func apply_quality() -> void:
	for mi in terrain_meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if Quality.allows("terrain_shadows") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _shape_for(v: int) -> Shape3D:
	if _shapes.has(v):
		return _shapes[v]
	var col: Dictionary = ScatterCatalog.variant(v)["col"]
	var size: Array = col.get("s", [])
	var sh: Shape3D = null
	match str(col.get("t", "")):
		"cyl":
			var c := CylinderShape3D.new()
			c.radius = float(size[0])
			c.height = float(size[1])
			sh = c
		"sphere":
			var s := SphereShape3D.new()
			s.radius = float(size[0])
			sh = s
		"box":
			var b := BoxShape3D.new()
			b.size = Vector3(float(size[0]), float(size[1]), float(size[2]))
			sh = b
	_shapes[v] = sh
	return sh


static func _shape_offset(v: int) -> Vector3:
	return ScatterCatalog.variant(v)["col"].get("c", Vector3.ZERO)


func _new_body(bi: int) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = "%s_%d" % [["Scatter", "Blockers", "Stumps"][bi], _bodies.size()]
	b.collision_layer = [65, 64, 1][bi]
	b.collision_mask = 0
	b.set_meta("scatter_chunk", self)
	b.add_to_group("scatter_body")
	return b


func entry_transform(i: int) -> Transform3D:
	var e: Dictionary = data.entries[i]
	var s := float(e["s"])
	return Transform3D(Basis(Vector3.UP, float(e["yaw"])).scaled(Vector3(s, s, s)), Vector3(float(e["x"]), float(e["y"]), float(e["z"])))


## Scatter shapes, SHAPES_PER_STEP entries per step, each part on its own bodies built while they are not in the
## tree yet: Jolt then builds each compound once when the body enters the space (≈ 0.2 ms for 150 shapes)
## instead of once per added shape (≈ 7 ms).
func _step_shapes() -> bool:
	var n := data.entries.size()
	var end := mini(_shape_cursor + SHAPES_PER_STEP, n)
	var part: Array = [null, null, null]
	for i in range(_shape_cursor, end):
		var e: Dictionary = data.entries[i]
		var v := int(e["v"])
		var sh := _shape_for(v)
		if sh == null:
			continue
		var layer := int(ScatterCatalog.variant(v)["layer"])
		var bi := 0 if layer == 65 else (1 if layer == 64 else 2)
		if part[bi] == null:
			part[bi] = _new_body(bi)
		var body: StaticBody3D = part[bi]
		var xf := entry_transform(i)
		xf.origin += xf.basis * _shape_offset(v)
		var owner_id := body.create_shape_owner(body)
		body.shape_owner_add_shape(owner_id, sh)
		body.shape_owner_set_transform(owner_id, xf)
		if removed[i] == 1:
			body.shape_owner_set_disabled(owner_id, true)
		entry_owner[i] = owner_id
		entry_body[i] = -1
		_entry_body_ref[i] = body
		if not _owner_entry_by_body.has(body):
			_owner_entry_by_body[body] = {}
		(_owner_entry_by_body[body] as Dictionary)[owner_id] = i
	for b in part:
		if b != null:
			_bodies.append(b)
			add_child(b)
	_shape_cursor = end
	return _shape_cursor >= n


func _step_multimesh() -> bool:
	var keys := data.mm_keys
	var end := mini(_mm_cursor + MM_PER_STEP, keys.size())
	for q in range(_mm_cursor, end):
		var mk: int = keys[q]
		var d: Dictionary = data.mm[mk]
		var v := mk % 64
		var idx: PackedInt32Array = d["idx"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Assets.instancing_mesh(ScatterCatalog.name_of(v))
		mm.instance_count = idx.size()
		mm.buffer = d["buf"]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "mm_%d" % mk
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(ScatterCatalog.variant(v)["shadow"]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_mmis[mk] = mmi
		for n in idx.size():
			entry_mm[idx[n]] = mk
			entry_inst[idx[n]] = n
			if removed[idx[n]] == 1:
				_hide_instance(idx[n])
	_mm_cursor = end
	return _mm_cursor >= keys.size()


func _step_nodes() -> bool:
	var list := data.nodes
	var n_entries := data.entries.size()
	var total := list.size() + n_entries
	var made := 0
	var nw := NetWorld.instance
	while _node_cursor < total and made < NODES_PER_STEP:
		var q := _node_cursor
		_node_cursor += 1
		if q < list.size():
			var e: Dictionary = list[q]
			var wid := int(e["wid"])
			if nw != null and bool(nw.delta_of(wid).get("removed", false)):
				continue
			_make_node(e)
			made += 1
		else:
			var i := q - list.size()
			if removed[i] == 1 and bool(data.entries[i]["felled"]) and not materialized.has(i):
				_make_stump(i)
				made += 1
	return _node_cursor >= total


func _step_done() -> bool:
	state = State.LOADED
	return true


func _make_node(e: Dictionary) -> Node3D:
	var wid := int(e["wid"])
	var node: Node3D
	match int(e["node"]):
		ScatterCatalog.NodeKind.PICKUP:
			var p: Node3D = _scene(PICKUP_PATH).instantiate()
			p.set("item_id", e["item"])
			p.set("model", e["model"])
			p.set("amount", 1)
			p.name = "pk_%x" % wid
			node = p
		ScatterCatalog.NodeKind.BERRY_BUSH:
			node = _scene(BUSH_PATH).instantiate()
			node.name = "bb_%x" % wid
		_:
			node = Node3D.new()
			node.name = "poi_%s" % str(e.get("id", wid))
			var model := Assets.spawn_model(str(e["model"]))
			node.add_child(model)
			node.set_meta("poi_model", str(e["model"]))
			node.add_to_group("poi_prop")
			if visual and Net.has_client:
				PoiCutaway.attach(node, model)
			else:
				for c in model.get_children():
					if String(c.name).ends_with("_Stub"):
						(c as Node3D).visible = false
	node.set_meta("wid", wid)
	node.position = Vector3(float(e["x"]), float(e["y"]), float(e["z"]))
	node.rotation.y = float(e["yaw"])
	objects.add_child(node)
	return node


func _make_stump(i: int) -> void:
	var e: Dictionary = data.entries[i]
	if ScatterCatalog.variant(int(e["v"]))["kind"] == ScatterCatalog.Kind.LOG:
		return
	var st: Node3D = _scene(STUMP_PATH).instantiate()
	st.name = "stump_of_%x" % int(e["wid"])
	st.set_meta("of_wid", int(e["wid"]))
	objects.add_child(st)
	st.global_position = Vector3(float(e["x"]), float(e["y"]), float(e["z"]))
	st.rotation.y = float(e["yaw"])
	st.scale = Vector3.ONE * float(e["s"])


# ------------------------------------------------------------------ scatter state
func _hide_instance(i: int) -> void:
	var mk := entry_mm[i]
	if mk < 0 or not _mmis.has(mk):
		return
	var e: Dictionary = data.entries[i]
	(_mmis[mk] as MultiMeshInstance3D).multimesh.set_instance_transform(entry_inst[i], Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(float(e["x"]), float(e["y"]) - 50.0, float(e["z"]))))


func _show_instance(i: int) -> void:
	var mk := entry_mm[i]
	if mk < 0 or not _mmis.has(mk):
		return
	(_mmis[mk] as MultiMeshInstance3D).multimesh.set_instance_transform(entry_inst[i], entry_transform(i))


func _set_shape_disabled(i: int, disabled: bool) -> void:
	var o := entry_owner[i]
	var b: StaticBody3D = _entry_body_ref.get(i)
	if o >= 0 and b != null:
		b.shape_owner_set_disabled(o, disabled)


## Entry index of a raycast hit on one of this chunk's scatter bodies (-1 when unknown).
func entry_of_hit(body: Object, shape_index: int) -> int:
	if not _owner_entry_by_body.has(body):
		return -1
	var owner_id := (body as StaticBody3D).shape_find_owner(shape_index)
	return int((_owner_entry_by_body[body] as Dictionary).get(owner_id, -1))


func entry_position(i: int) -> Vector3:
	var e: Dictionary = data.entries[i]
	return Vector3(float(e["x"]), float(e["y"]), float(e["z"]))


func is_available(i: int) -> bool:
	return i >= 0 and i < removed.size() and removed[i] == 0


## Real ChoppableTree for a choppable entry (existing one if already materialized; null when felled).
func materialize(i: int) -> ChoppableTree:
	if materialized.has(i):
		if is_instance_valid(materialized[i]) and not (materialized[i] as ChoppableTree).is_queued_for_deletion():
			_touched[i] = Time.get_ticks_msec() / 1000.0
			return materialized[i]
		materialized.erase(i)
	if i < 0 or i >= data.entries.size() or removed[i] == 1 or not ScatterCatalog.is_choppable(int(data.entries[i]["v"])):
		return null
	var e: Dictionary = data.entries[i]
	var t: ChoppableTree = _scene(TREE_PATH).instantiate()
	t.variant = ScatterCatalog.name_of(int(e["v"]))
	t.name = "tree_%x" % int(e["wid"])
	t.set_meta("wid", int(e["wid"]))
	t.scatter_chunk = self
	t.scatter_entry = i
	removed[i] = 1
	_hide_instance(i)
	_set_shape_disabled(i, true)
	materialized[i] = t
	_touched[i] = Time.get_ticks_msec() / 1000.0
	t.transform = entry_transform(i)   # Objects sits at the origin: local = world
	objects.add_child(t)
	return t


## Back to the MultiMesh (an untouched hover / a chunk that no longer needs it).
func dematerialize(i: int) -> void:
	if not materialized.has(i) or not is_instance_valid(materialized[i]):
		return
	var t: ChoppableTree = materialized[i]
	if t.felled or t.hits > 0:
		return
	materialized.erase(i)
	_touched.erase(i)
	objects.remove_child(t)
	t.free()
	removed[i] = 0
	_show_instance(i)
	_set_shape_disabled(i, false)


## A materialized tree finished falling (tree.gd): the entry stays removed and the tree node is gone.
func on_tree_felled(i: int) -> void:
	data.entries[i]["felled"] = true
	materialized.erase(i)
	_touched.erase(i)


## Felled without a live tree (snapshot / delta for a chunk that is loaded): hide, stump, AO.
func fell_static(i: int) -> void:
	if i < 0 or i >= removed.size() or bool(data.entries[i]["felled"]):
		return
	if materialized.has(i):
		return
	removed[i] = 1
	data.entries[i]["felled"] = true
	_hide_instance(i)
	_set_shape_disabled(i, true)
	if state == State.LOADED or _node_cursor > data.nodes.size() + i:
		_make_stump(i)
	_swap_occluder(i, true, true)


## Replaces an entry's AO disc by its stump's (felled) — `rebuild` re-uploads the mesh(es).
func _swap_occluder(i: int, to_stump: bool, rebuild: bool) -> void:
	var e: Dictionary = data.entries[i]
	var v := int(e["v"])
	var so := ScatterCatalog.stump_occluder(v, float(e["s"]))
	var id := str(int(e["wid"]))
	if not to_stump:
		return
	var w := World.instance
	if w != null and w.terrain != null and rebuild:
		w.terrain.update_occluder(id, float(so[0]), float(so[1]))
	else:
		update_occluder(id, float(so[0]), float(so[1]), false)


## Local AO re-bake of one occluder (strength 0 = removed). Returns true when this chunk had it.
func update_occluder(id: String, r: float, strength: float, rebuild: bool = true) -> bool:
	var found := -1
	for k in data.occluders.size():
		if str((data.occluders[k] as Dictionary).get("id", "")) == id:
			found = k
			break
	if found < 0:
		return false
	var old: Dictionary = data.occluders[found]
	if data.ao.is_empty():
		var o0 := old.duplicate()
		o0["r"] = r
		o0["strength"] = strength
		o0.erase("size")
		data.occluders[found] = o0
		return true
	data.apply_occluder(old, false)
	var o := old.duplicate()
	o["r"] = r
	o["strength"] = strength
	o.erase("size")
	data.occluders[found] = o
	data.apply_occluder(o, true)
	if rebuild:
		var reach := maxf(r, ChunkJob.occluder_reach(old))
		var pos: Vector2 = o["pos"]
		rebuild_mesh(Rect2(pos - Vector2(reach, reach), Vector2(reach, reach) * 2.0))
	return true


## AO at a world position (nearest sample; 1 without a mesh).
func ao_at(x: float, z: float) -> float:
	if data.ao.is_empty():
		return 1.0
	var i := clampi(int(round(x)) - WorldConst.chunk_origin_i(cx), 0, N - 1)
	var j := clampi(int(round(z)) - WorldConst.chunk_origin_i(cz), 0, N - 1)
	return data.ao[j * N + i]


func height_at(x: float, z: float) -> float:
	return data.height_local(x, z)


## Choppable entries whose hover cylinder the ray (from, dir) crosses before `max_t`: nearest first.
func pick_choppable(from: Vector3, dir: Vector3, max_t: float) -> int:
	var best := -1
	var best_t := max_t
	for w in wid_index:
		var i: int = wid_index[w]
		if removed[i] == 1:
			continue
		var e: Dictionary = data.entries[i]
		var pick: Array = ScatterCatalog.variant(int(e["v"]))["pick"]
		var r := float(pick[0]) * float(e["s"])
		var h := float(pick[1]) * float(e["s"])
		var t := _ray_cylinder(from, dir, Vector3(float(e["x"]), float(e["y"]), float(e["z"])), r, h)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = i
	return best


## Ray vs vertical cylinder (base centre c, radius r, height h): entry distance or -1.
static func _ray_cylinder(o: Vector3, d: Vector3, c: Vector3, r: float, h: float) -> float:
	var ox := o.x - c.x
	var oz := o.z - c.z
	var a := d.x * d.x + d.z * d.z
	if a < 0.000001:
		return -1.0
	var b := 2.0 * (ox * d.x + oz * d.z)
	var cc := ox * ox + oz * oz - r * r
	var disc := b * b - 4.0 * a * cc
	if disc < 0.0:
		return -1.0
	var sq := sqrt(disc)
	for t in [(-b - sq) / (2.0 * a), (-b + sq) / (2.0 * a)]:
		if t < 0.0:
			continue
		var y: float = o.y + d.y * t
		if y >= c.y and y <= c.y + h:
			return t
	return -1.0


## Nearest available choppable entry to `pos` whose variant name starts with `prefix` (tests, tools).
func nearest_choppable(pos: Vector3, prefix: String = "") -> int:
	var best := -1
	var best_d := INF
	for w in wid_index:
		var i: int = wid_index[w]
		if removed[i] == 1:
			continue
		var e: Dictionary = data.entries[i]
		if prefix != "" and not ScatterCatalog.name_of(int(e["v"])).begins_with(prefix):
			continue
		var d := Vector2(float(e["x"]) - pos.x, float(e["z"]) - pos.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best


func _process(delta: float) -> void:
	if state != State.LOADED or materialized.is_empty():
		return
	_sweep_t += delta
	if _sweep_t < 1.0:
		return
	_sweep_t = 0.0
	var now := Time.get_ticks_msec() / 1000.0
	var keep: Node = null
	var lp := GameFlow.local_player() if Net.has_client else null
	if lp != null and lp.get("interactor") != null:
		var it: Interactor = lp.interactor
		keep = it.target.target_node() if it.target != null and is_instance_valid(it.target) else null
		if it.pending != null and is_instance_valid(it.pending) and it.pending.target_node() != null:
			_touched[_entry_of_node(it.pending.target_node())] = now
	for i in materialized.keys():
		if not is_instance_valid(materialized[i]):
			materialized.erase(i)
			continue
		var t: ChoppableTree = materialized[i]
		if t == keep:
			_touched[i] = now
			continue
		if now - float(_touched.get(i, now)) > DEMATERIALIZE_AFTER:
			dematerialize(i)


func _entry_of_node(n: Node) -> int:
	for i in materialized:
		if materialized[i] == n:
			return i
	return -1
