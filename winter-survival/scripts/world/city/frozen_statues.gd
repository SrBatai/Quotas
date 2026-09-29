class_name FrozenStatues
extends Node3D
## Client: the frozen of the city as statues (C1, doc 09 §4.4 «Estatuas congeladas», PLAN C32). A frozen zombie has
## no body on the server and costs only its 1 Hz keyframe (≈ 9 B/s); in the client it no longer needs one of the ZombieClient's
## 48 skeletal views: every frozen record WITHOUT a view within RANGE m of the camera focus is drawn as an instance
## of a MultiMesh of baked frozen poses (POSES variants of the `zombie_frozen_NN` bodies in Zom_Frozen_Idle, skinned
## once on the CPU with MeshInstance3D.bake_mesh_from_current_skeleton_pose, ice shards included): ≤ MAX statues in
## POSES × surfaces draw calls (≈ 8). When it wakes (state leaves FROZEN) it drops out of the MultiMesh and the pool
## gives it a skeletal view with Zom_Wake, as before. Rebuilt at REFRESH Hz (the statues do not move).
## Also the zombies trapped in the jam cars («atrapados en coches»): a seeded share of the jam cars of the loaded city
## chunks shows a frozen figure behind the windscreen (the same baked poses, seated lower), pure decoration by the
## seed (no record, 0 B/s; opening the door / breaking the glass to free one is V1).

const RANGE := 110.0
const MAX := 300
const REFRESH := 4.0
const POSES := 4
const TRAPPED_SHARE := 0.22
const GEN_TRAPPED := 0x54524150   # "TRAP"

static var _meshes: Array = []        # baked pose meshes (ArrayMesh), index = pose
static var _bake_tried: bool = false

var mmi: Array[MultiMeshInstance3D] = []
var trapped_mmi: Array[MultiMeshInstance3D] = []
var count: int = 0
var trapped: int = 0
var _t: float = 0.0
var _trap_key: int = -1


func _ready() -> void:
	name = "FrozenStatues"
	top_level = true
	for i in POSES:
		mmi.append(_mm("Statues_%d" % i, i))
		trapped_mmi.append(_mm("Trapped_%d" % i, i))
	await bake()
	for i in POSES:
		mmi[i].multimesh.mesh = _meshes[i]
		trapped_mmi[i].multimesh.mesh = _meshes[i]


func _mm(n: String, pose: int) -> MultiMeshInstance3D:
	var m := MultiMeshInstance3D.new()
	m.name = n
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _meshes[pose] if pose < _meshes.size() else null
	mm.instance_count = 0
	m.multimesh = mm
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	m.visibility_range_end = RANGE + 10.0
	add_child(m)
	return m


## Bakes the frozen poses once (a hidden ZombieView per pose, animated one step, then — a frame later, once the
## skins are registered with their skeletons — skinned on the CPU); without the art (Web placeholders) a simple
## ice-blue figure. Awaitable; later callers get the cached meshes at once.
func bake() -> void:
	if _bake_tried:
		while _meshes.size() < POSES:
			await get_tree().process_frame
		return
	_bake_tried = true
	var views: Array = []
	if not Assets.force_placeholders:
		for p in POSES:
			var zv := ZombieView.new()
			zv.visible = false
			add_child(zv)
			zv.setup(ZombieKinds.Kind.FROZEN, p)
			zv.set_motion(ZombieKinds.State.FROZEN, 0.0, false)
			views.append(zv)
		await get_tree().process_frame
		for p in views.size():
			var zv: ZombieView = views[p]
			zv.advance(0.2 + 0.37 * float(p))
			if zv.tree != null:
				zv.tree.advance(0.0)
		await get_tree().process_frame
	var out: Array = []
	for p in POSES:
		var mesh: ArrayMesh = null
		if p < views.size():
			mesh = _bake_model((views[p] as ZombieView).model)
			(views[p] as ZombieView).queue_free()
		if mesh == null:
			mesh = _placeholder()
		out.append(mesh)
	_meshes = out


## Every MeshInstance3D of the model, skinned ones baked to their current pose, merged per material into one mesh.
static func _bake_model(model: Node3D) -> ArrayMesh:
	if model == null:
		return null
	var by_mat := {}
	var order: Array = []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or (not m.visible and String(m.name) != "Ice"):
			continue
		var src: Mesh = m.mesh
		var xf := _rel(model, m)
		var skel := m.get_node_or_null(m.skeleton) as Skeleton3D
		if m.skin != null and skel != null:
			# CPU skinning of the current pose (bake_mesh_from_current_skeleton_pose refuses without a rendering
			# skin registration, e.g. headless): skinned vertices live in the skeleton's space
			src = _skin_cpu(m.mesh, m.skin, skel)
			xf = _rel(model, skel)
		for si in src.get_surface_count():
			var mat := m.get_active_material(si)
			var k := mat.get_instance_id() if mat != null else 0
			if not by_mat.has(k):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[k] = [st, mat]
				order.append(k)
			var arr := src.surface_get_arrays(si)
			# drop skin channels (bones / weights): the baked vertices are already posed
			arr[Mesh.ARRAY_BONES] = null
			arr[Mesh.ARRAY_WEIGHTS] = null
			var tmp := ArrayMesh.new()
			tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			(by_mat[k][0] as SurfaceTool).append_from(tmp, 0, xf)
	if order.is_empty():
		return null
	var out := ArrayMesh.new()
	for k in order:
		var st: SurfaceTool = by_mat[k][0]
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, by_mat[k][1])
	return out


## The mesh posed by the skeleton's current global bone poses (up to 8 weights per vertex), in skeleton space.
static func _skin_cpu(mesh: Mesh, skin: Skin, skel: Skeleton3D) -> ArrayMesh:
	var mats: Array[Transform3D] = []
	for bi in skin.get_bind_count():
		var bone := skin.get_bind_bone(bi)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(bi))
		mats.append(skel.get_bone_global_pose(bone) * skin.get_bind_pose(bi) if bone >= 0 else Transform3D.IDENTITY)
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var nv := verts.size()
		var per := bones.size() / maxi(nv, 1)
		if per > 0 and weights.size() == bones.size():
			for vi in nv:
				var p := Vector3.ZERO
				var n := Vector3.ZERO
				var wsum := 0.0
				for k in per:
					var w := weights[vi * per + k]
					if w <= 0.0:
						continue
					var b := bones[vi * per + k]
					if b < 0 or b >= mats.size():
						continue
					var t: Transform3D = mats[b]
					p += (t * verts[vi]) * w
					if not nrm.is_empty():
						n += (t.basis * nrm[vi]) * w
					wsum += w
				if wsum > 0.0:
					verts[vi] = p / wsum
					if not nrm.is_empty():
						nrm[vi] = n.normalized()
		arr[Mesh.ARRAY_VERTEX] = verts
		if not nrm.is_empty():
			arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_TANGENT] = null
		arr[Mesh.ARRAY_BONES] = null
		arr[Mesh.ARRAY_WEIGHTS] = null
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


static func _rel(root: Node, n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


static func _placeholder() -> ArrayMesh:
	var m := CityMesh.new()
	var ice := Color(0.72, 0.84, 0.95)
	m.box(Vector3(0, 0, 0), Vector3(0.45, 1.05, 0.3), ice, ice, 1.0)
	m.box(Vector3(0, 1.05, 0), Vector3(0.55, 0.55, 0.32), ice, ice, 1.0)
	m.box(Vector3(0, 1.6, 0), Vector3(0.26, 0.26, 0.26), ice, ice, 1.0)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.arrays())
	am.surface_set_material(0, Assets.get_shared_material())
	return am


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0 / REFRESH
	_refresh_statues()
	_refresh_trapped()


func _focus() -> Vector3:
	var lp := GameFlow.local_player() as Node3D
	if lp != null and lp.is_inside_tree():
		return lp.global_position
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	return cam.global_position if cam != null else Vector3.ZERO


func _refresh_statues() -> void:
	var zc := ZombieClient.instance
	var bufs: Array = []
	for i in POSES:
		bufs.append(PackedFloat32Array())
	count = 0
	if zc != null:
		var f := _focus()
		for id in zc.records:
			var r: ZombieClient.ZRec = zc.records[id]
			if r.state != ZombieKinds.State.FROZEN or r.view != null:
				continue
			if count >= MAX or f.distance_to(r.render_pos) > RANGE:
				continue
			var pose := posmod(r.variant, POSES)
			var b := Basis(Vector3.UP, r.render_yaw)
			var o := r.render_pos
			(bufs[pose] as PackedFloat32Array).append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z])
			count += 1
	for i in POSES:
		_upload(mmi[i], bufs[i])


func _upload(m: MultiMeshInstance3D, buf: PackedFloat32Array) -> void:
	var mm := m.multimesh
	var n := buf.size() / 12
	if mm.instance_count != n:
		mm.instance_count = n
	if n > 0:
		mm.buffer = buf
	m.visible = n > 0


## Trapped in the jam cars of the loaded chunks: rebuilt when the set of loaded city chunks changes.
func _refresh_trapped() -> void:
	var world := World.instance
	if world == null or world.streamer == null:
		return
	var keys := world.streamer.loaded_keys()
	var sig := keys.hash()
	if sig == _trap_key:
		return
	_trap_key = sig
	var bufs: Array = []
	for i in POSES:
		bufs.append(PackedFloat32Array())
	trapped = 0
	for k in keys:
		var ch: WorldChunk = world.streamer.chunks.get(k)
		if ch == null or ch.data == null:
			continue
		for e in ch.data.city:
			if not bool(e.get("jam", false)):
				continue
			var h := int(e["wid"])
			if WorldConst.unit(WorldConst.hash64(h, GEN_TRAPPED)) > TRAPPED_SHARE or str(e.get("variant", "")) == "burnt":
				continue
			var sz := CityLots.model_size(str(e["model"]))
			var yaw := deg_to_rad(float(e["yaw"]))
			var b := Basis(Vector3.UP, yaw + PI).scaled(Vector3(0.95, 0.72, 0.95))
			var p: Vector2 = e["pos"]
			# the driver's seat: a little forward of the centre, on the left, sunk into the seat
			var off := Basis(Vector3.UP, yaw) * Vector3(-sz.x * 0.2, 0.0, sz.z * 0.12)
			var o := Vector3(p.x, float(e["y"]) + sz.y * 0.28, p.y) + off
			var pose := posmod(h >> 7, POSES)
			(bufs[pose] as PackedFloat32Array).append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z])
			trapped += 1
	for i in POSES:
		_upload(trapped_mmi[i], bufs[i])
