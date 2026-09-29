class_name CombatFx
extends Node3D
## Client-only combat feedback (GDD v2 §7.5, §6.3): pooled blood decals on the snow (`gore/blood_splat_a/b/c`
## when Opus delivered them, else flat quads with a soft radial splat, #8B1E1E, darkening, BLOOD_DECAL_SECONDS),
## the white noise ring that expands to the real radius in 0.4 s, and the bloater's cloud. Fed by ZombieClient
## (FX records of ZombieNet) and by the local melee feedback. Never exists on the dedicated server.

const BLOOD_POOL := 48
const RING_POOL := 16
const RING_TIME := 0.4
const RING_FADE := 0.5
const SPLATS := ["gore/blood_splat_a", "gore/blood_splat_b", "gore/blood_splat_c"]
const HEAD_FRAGS := "gore/head_fragments"
const HEAD_FRAG_SECONDS := 12.0

static var instance: CombatFx

var world: World
var _blood: Array[Node3D] = []
var _blood_born := PackedFloat32Array()
var _blood_next: int = 0
var _rings: Array[MeshInstance3D] = []
var _ring_born := PackedFloat32Array()
var _ring_r := PackedFloat32Array()
var _ring_next: int = 0
var _clouds: Array = []          # [node, until]
var _blood_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _cloud_mat: StandardMaterial3D
## Test hooks.
var blood_spawned: int = 0
var heads_popped: int = 0
var _heads: Array = []            # [root, [[fragment, velocity, spin], …], until]
var rings_spawned: int = 0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	name = "CombatFx"
	top_level = true
	_blood_mat = StandardMaterial3D.new()
	_blood_mat.albedo_color = Color("#8B1E1E")
	_blood_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blood_mat.roughness = 0.6
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.55, Color(1, 1, 1, 0.95))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	_blood_mat.albedo_texture = tex
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(1, 1, 1, 0.8)
	_ring_mat.no_depth_test = false
	_cloud_mat = StandardMaterial3D.new()
	_cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cloud_mat.albedo_color = Color(0.66, 0.70, 0.42, 0.45)
	_cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blood_born.resize(BLOOD_POOL)
	_ring_born.resize(RING_POOL)
	_ring_r.resize(RING_POOL)


func _ground(p: Vector3) -> float:
	if world != null and world.terrain != null:
		return world.get_height(p.x, p.z)
	return p.y


## A blood splat of `size` m on the snow at `p` (the ground height under it). `yaw` (finite) = the blow's
## direction: blood_splat_c stretches along its +Z.
func blood(p: Vector3, size: float = 0.9, yaw: float = INF) -> void:
	var n: Node3D
	if _blood.size() < BLOOD_POOL:
		var pick: String = SPLATS[_blood.size() % SPLATS.size()]
		if Assets.has_model(pick) and not Assets.force_placeholders:
			n = Assets.spawn_model(pick)
		else:
			var mi := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(1.0, 1.0)
			mi.mesh = pm
			mi.material_override = _blood_mat.duplicate()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n = mi
		n.name = "blood_%d" % _blood.size()
		add_child(n)
		_blood.append(n)
	else:
		n = _blood[_blood_next]
	var idx := _blood.find(n)
	_blood_next = (idx + 1) % BLOOD_POOL
	n.visible = true
	n.global_position = Vector3(p.x, _ground(p) + 0.03, p.z)
	n.rotation = Vector3(0, yaw + randf_range(-0.3, 0.3) if is_finite(yaw) else randf() * TAU, 0)
	n.scale = Vector3.ONE * clampf(size, 0.4, 1.6) * randf_range(0.8, 1.2)
	_blood_born[idx] = Time.get_ticks_msec() / 1000.0
	blood_spawned += 1


## The noise ring (GDD §6.3): white, grows to `radius` in 0.4 s, then fades.
func ring(p: Vector3, radius: float) -> void:
	var mi: MeshInstance3D
	if _rings.size() < RING_POOL:
		mi = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.96
		tm.outer_radius = 1.0
		tm.rings = 48
		tm.ring_segments = 3
		mi.mesh = tm
		mi.material_override = _ring_mat.duplicate()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "ring_%d" % _rings.size()
		add_child(mi)
		_rings.append(mi)
	else:
		mi = _rings[_ring_next]
	var idx := _rings.find(mi)
	_ring_next = (idx + 1) % RING_POOL
	mi.visible = true
	mi.global_position = Vector3(p.x, _ground(p) + 0.12, p.z)
	mi.scale = Vector3(0.01, 1.0, 0.01)
	_ring_born[idx] = Time.get_ticks_msec() / 1000.0
	_ring_r[idx] = radius
	rings_spawned += 1


func cloud(p: Vector3, seconds: float, radius: float = 4.0) -> void:
	var root := Node3D.new()
	root.name = "cloud"
	add_child(root)
	root.global_position = Vector3(p.x, _ground(p) + 0.6, p.z)
	for k in 5:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = radius * randf_range(0.35, 0.55)
		sm.height = sm.radius * 1.4
		sm.radial_segments = 12
		sm.rings = 6
		mi.mesh = sm
		mi.material_override = _cloud_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(randf_range(-1.5, 1.5), randf_range(0.0, 1.0), randf_range(-1.5, 1.5))
		root.add_child(mi)
	_clouds.append([root, Time.get_ticks_msec() / 1000.0 + seconds])


## Gore-lite head burst (ASSET_SPEC v2 M4.5): gore/head_fragments at the HeadSocket transform `at`; each
## Frag_n (origin at its centroid) flies out from the head centre (+ the blow's `push`), tumbles and rests on the
## snow; the pieces go after HEAD_FRAG_SECONDS. A light ballistic step here (no physics bodies on the client).
func head_pop(at: Transform3D, push: Vector3) -> void:
	heads_popped += 1
	blood(at.origin, 1.0, atan2(push.x, push.z))
	if not Assets.has_model(HEAD_FRAGS) or Assets.force_placeholders:
		return
	var root := Assets.spawn_model(HEAD_FRAGS)
	root.name = "head_frags"
	add_child(root)
	root.global_transform = at
	var now := Time.get_ticks_msec() / 1000.0
	var pieces: Array = []
	for c in root.find_children("Frag_*", "", true, false):
		var n := c as Node3D
		if n == null:
			continue
		var out := n.global_position - at.origin
		out = out.normalized() if out.length() > 0.001 else Vector3.UP
		var v := out * randf_range(1.2, 2.6) + Vector3.UP * randf_range(1.4, 2.6) + push.normalized() * randf_range(0.8, 1.8)
		var spin := Vector3(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
		pieces.append([n, v, spin])
	_heads.append([root, pieces, now + HEAD_FRAG_SECONDS])


func _update_heads(delta: float, now: float) -> void:
	for h in _heads.duplicate():
		var root: Node3D = h[0]
		if now >= float(h[2]) or not is_instance_valid(root):
			if is_instance_valid(root):
				root.queue_free()
			_heads.erase(h)
			continue
		for pc in h[1]:
			var n: Node3D = pc[0]
			var v: Vector3 = pc[1]
			if v == Vector3.ZERO:
				continue
			v.y -= 9.8 * delta
			var p := n.global_position + v * delta
			var g := _ground(p) + 0.04
			if p.y <= g:
				p.y = g
				v = Vector3.ZERO if absf(v.y) < 1.5 else Vector3(v.x * 0.4, -v.y * 0.25, v.z * 0.4)
			n.global_position = p
			if v != Vector3.ZERO:
				n.rotate_x((pc[2] as Vector3).x * delta)
				n.rotate_y((pc[2] as Vector3).y * delta)
				n.rotate_z((pc[2] as Vector3).z * delta)
			pc[1] = v


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not _heads.is_empty():
		_update_heads(delta, now)
	for i in _rings.size():
		var mi := _rings[i]
		if not mi.visible:
			continue
		var age := now - _ring_born[i]
		var r := _ring_r[i] * clampf(age / RING_TIME, 0.0, 1.0)
		mi.scale = Vector3(maxf(r, 0.01), 1.0, maxf(r, 0.01))
		var a := 0.8 * clampf(1.0 - (age - RING_TIME) / RING_FADE, 0.0, 1.0)
		(mi.material_override as StandardMaterial3D).albedo_color.a = a
		if age > RING_TIME + RING_FADE:
			mi.visible = false
	if Engine.get_process_frames() % 30 == 0:
		for i in _blood.size():
			var n := _blood[i]
			if not n.visible:
				continue
			var age := now - _blood_born[i]
			if age > Balance.BLOOD_DECAL_SECONDS:
				n.visible = false
			elif n is MeshInstance3D and (n as MeshInstance3D).material_override is StandardMaterial3D:
				var k := clampf(age / Balance.BLOOD_DECAL_SECONDS, 0.0, 1.0)
				var m := (n as MeshInstance3D).material_override as StandardMaterial3D
				m.albedo_color = Color("#8B1E1E").darkened(0.5 * k)
				m.albedo_color.a = 1.0 - maxf(k - 0.8, 0.0) * 5.0
	for c in _clouds.duplicate():
		var until := float(c[1])
		var node: Node3D = c[0]
		if now >= until:
			node.queue_free()
			_clouds.erase(c)
		else:
			node.scale = Vector3.ONE * (1.0 + 0.05 * (8.0 - (until - now)))


func visible_blood() -> int:
	var n := 0
	for b in _blood:
		if b.visible:
			n += 1
	return n
