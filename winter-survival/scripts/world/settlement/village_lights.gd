class_name VillageLights
extends Node3D
## Night lighting of the M6b sites (PLAN §7 M6b «luces de pueblo»: Forward+ real lights; `compat`: emissive + halo,
## risk R7), client only. The lamps of the streamed chunks (SettlementChunk.add_lamps) share two MultiMeshes with the
## city's materials — a fake light pool on the ground and a bulb halo per lamp (res://assets/materials/light_pool /
## light_halo: they fade in with the night factor DayNight feeds through CityLights.set_sky) — so a whole village
## costs 2 draw calls at night and none by day, in every renderer. On top, Forward+ gets a small pool of real
## OmniLight3D (Quality.lamp_light_budget(): alto 12, medio 6, compat / Web 0) moved to the powered lamps nearest the
## camera focus. The village runs on the sawmill's generator: most lamps are on, some flicker (power < 0), some
## are dead (0) — decided per lamp by the site plan.

const POOL_MAT := "res://assets/materials/light_pool.tres"
const HALO_MAT := "res://assets/materials/light_halo.tres"
const LAMP_COLOR := Color(1.0, 0.8, 0.55)
const REAL_RANGE := 10.0
const REAL_ENERGY := 1.25
const REAL_MAX_DIST := 42.0
const RELIGHT_PERIOD := 0.3
const REAL_POOL_SCALE := 0.3
const POOL_RADIUS := 6.0
const HALO_SIZE := 1.0

var lamps: Array[Dictionary] = []       # {pos: bulb, ground: y, power}
var pools: MultiMeshInstance3D
var halos: MultiMeshInstance3D
var focus_override: Node3D
var _by_owner: Dictionary = {}
var _lights: Array[OmniLight3D] = []
var _real_lit: Dictionary = {}
var _t: float = 0.0


func _ready() -> void:
	pools = _mm_node("Pools", POOL_MAT)
	halos = _mm_node("Halos", HALO_MAT)


## A chunk's lamps ([bulb, ground y, power] each) join the set.
func add_lamps(owner_key: int, list: Array) -> void:
	var own: Array = []
	for l in list:
		own.append({"pos": l[0], "ground": float(l[1]), "power": float(l[2])})
	_by_owner[owner_key] = own
	_rebuild()


func remove_lamps(owner_key: int) -> void:
	if _by_owner.erase(owner_key):
		_rebuild()


func _rebuild() -> void:
	lamps.clear()
	var keys := _by_owner.keys()
	keys.sort()
	for k in keys:
		for l in _by_owner[k]:
			lamps.append(l)
	if pools == null:
		return
	_real_lit = {}
	pools.multimesh = _multimesh(POOL_RADIUS * 2.0, true)
	halos.multimesh = _multimesh(HALO_SIZE, false)
	if lamps.is_empty():
		return
	var pb := PackedFloat32Array()
	var hb := PackedFloat32Array()
	pb.resize(lamps.size() * 16)
	hb.resize(lamps.size() * 16)
	for i in lamps.size():
		var l: Dictionary = lamps[i]
		var pos: Vector3 = l["pos"]
		var c := _custom(i)
		_row(pb, i * 16, Vector3(pos.x, float(l["ground"]) + 0.05, pos.z), c)
		_row(hb, i * 16, pos, c)
	pools.multimesh.buffer = pb
	halos.multimesh.buffer = hb
	_t = 0.0


## INSTANCE_CUSTOM for light_pool.gdshader: rgb tint, a = intensity (negative = flicker, 0 = dead lamp).
func _custom(i: int) -> Color:
	var p := float(lamps[i]["power"])
	return Color(LAMP_COLOR.r, LAMP_COLOR.g, LAMP_COLOR.b, p)


static func _row(b: PackedFloat32Array, o: int, p: Vector3, c: Color) -> void:
	var v := [1.0, 0.0, 0.0, p.x, 0.0, 1.0, 0.0, p.y, 0.0, 0.0, 1.0, p.z, c.r, c.g, c.b, c.a]
	for k in 16:
		b[o + k] = float(v[k])


func _mm_node(n: String, mat_path: String) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.material_override = load(mat_path)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _multimesh(size: float, ground: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	if ground:
		q.orientation = PlaneMesh.FACE_Y
	mm.mesh = q
	mm.instance_count = lamps.size()
	return mm


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = RELIGHT_PERIOD
	_update_real_lights()


## Real lights (Forward+) on the powered lamps nearest the focus, at night only.
func _update_real_lights() -> void:
	var night := CityLights.night()
	var budget := Quality.lamp_light_budget() if night > 0.2 else 0
	while _lights.size() < budget:
		var o := OmniLight3D.new()
		o.name = "LampLight%d" % _lights.size()
		o.light_color = LAMP_COLOR
		o.omni_range = REAL_RANGE
		o.omni_attenuation = 1.2
		o.shadow_enabled = false
		o.light_specular = 0.2
		o.light_indirect_energy = 0.0
		add_child(o)
		_lights.append(o)
	var focus := _focus()
	var order: Array = []
	for i in lamps.size():
		var l: Dictionary = lamps[i]
		if float(l["power"]) <= 0.0:
			continue
		var d := focus.distance_to(l["pos"])
		if d < REAL_MAX_DIST:
			order.append([d, i])
	order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var lit := {}
	for j in _lights.size():
		var o := _lights[j]
		if j < budget and j < order.size():
			var li := int(order[j][1])
			o.visible = true
			o.global_position = (lamps[li]["pos"] as Vector3) + Vector3(0, -0.3, 0)
			o.light_energy = REAL_ENERGY * night
			lit[li] = true
		else:
			o.visible = false
	if pools != null and pools.multimesh != null and lit != _real_lit and pools.multimesh.instance_count == lamps.size():
		for i in lamps.size():
			if lit.has(i) != _real_lit.has(i):
				var cst := _custom(i)
				cst.a *= REAL_POOL_SCALE if lit.has(i) else 1.0
				pools.multimesh.set_instance_custom_data(i, cst)
		_real_lit = lit


func real_lights_on() -> int:
	var n := 0
	for o in _lights:
		if o.visible:
			n += 1
	return n


func _focus() -> Vector3:
	if focus_override != null and is_instance_valid(focus_override):
		return focus_override.global_position
	var rig := CameraRig.active()
	if rig != null:
		return rig.global_position
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	return cam.global_position if cam != null else Vector3.ZERO
