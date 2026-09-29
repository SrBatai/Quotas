class_name BeaconLights
extends Node3D
## G2b beacons and rotating lights («balizas y rotativos», doc 08 §3.9), client only. Every beacon is two MultiMesh
## instances animated by assets/shaders/beacon.gdshader (a bulb halo + the light it throws on the snow), so any
## number of them costs 2 draw calls and no CPU per frame. At night the rotating ones nearest the camera also get a
## real SpotLight3D that sweeps the street (and the volumetric fog on `alto`): Quality lamp budget → alto 3,
## medio 2, compat / Web 0 (there the rotating ground wedge does the job). Owners (a city chunk, a scene) add and
## remove their beacons as a set, like CityLights' lamps.

enum Mode { BLINK = 0, ROTATE = 1, PULSE = 2, AMBER = 3 }

const MATERIAL_HALO := "res://assets/materials/beacon_halo.tres"
const MATERIAL_POOL := "res://assets/materials/beacon_pool.tres"
const HALO_SIZE := 0.9
const POOL_SIZE := 11.0
const REAL_MAX_DIST := 45.0
const RELIGHT := 0.4
const SPIN := 4.2          # rad/s, = beacon.gdshader rotate_speed

## {pos: Vector3 (bulb), ground: float, color: Color, mode: int, phase: float}
var beacons: Array[Dictionary] = []
var halos: MultiMeshInstance3D
var pools: MultiMeshInstance3D
var _by_owner: Dictionary = {}
var _spots: Array[SpotLight3D] = []
var _spot_of: Array[int] = []
var _t: float = 0.0
var _clock: float = 0.0


func _ready() -> void:
	halos = _mm_node("Halos", MATERIAL_HALO)
	pools = _mm_node("Pools", MATERIAL_POOL)


## A set of beacons under a key (a chunk, a scene; replaces that key's previous set). Each: [bulb pos, ground y, colour, mode, phase].
func put_set(key: int, list: Array) -> void:
	var own: Array = []
	for b in list:
		own.append({"pos": b[0], "ground": float(b[1]), "color": b[2], "mode": int(b[3]), "phase": fposmod(float(b[4]), 1.0)})
	if own.is_empty():
		_by_owner.erase(key)
	else:
		_by_owner[key] = own
	_rebuild()


func remove_set(key: int) -> void:
	if _by_owner.erase(key):
		_rebuild()


func count() -> int:
	return beacons.size()


func _rebuild() -> void:
	beacons.clear()
	var keys := _by_owner.keys()
	keys.sort()
	for k in keys:
		for b in _by_owner[k]:
			beacons.append(b)
	var n := beacons.size()
	halos.multimesh = _multimesh(HALO_SIZE, false, n)
	pools.multimesh = _multimesh(POOL_SIZE, true, n)
	if n == 0:
		return
	var hb := PackedFloat32Array()
	var pb := PackedFloat32Array()
	hb.resize(n * 16)
	pb.resize(n * 16)
	for i in n:
		var b: Dictionary = beacons[i]
		var p: Vector3 = b["pos"]
		var custom := custom_of(b["color"], int(b["mode"]), float(b["phase"]))
		_row(hb, i * 16, p, custom)
		_row(pb, i * 16, Vector3(p.x, float(b["ground"]) + 0.06, p.z), custom)
	halos.multimesh.buffer = hb
	pools.multimesh.buffer = pb
	_t = 0.0


## INSTANCE_CUSTOM of a beacon for beacon.gdshader: rgb = colour, a = mode + phase (fract).
static func custom_of(c: Color, mode: int, phase: float) -> Color:
	return Color(c.r, c.g, c.b, float(mode) + clampf(fposmod(phase, 1.0), 0.0, 0.999))


static func _row(buf: PackedFloat32Array, o: int, p: Vector3, c: Color) -> void:
	buf[o] = 1.0
	buf[o + 1] = 0.0
	buf[o + 2] = 0.0
	buf[o + 3] = p.x
	buf[o + 4] = 0.0
	buf[o + 5] = 1.0
	buf[o + 6] = 0.0
	buf[o + 7] = p.y
	buf[o + 8] = 0.0
	buf[o + 9] = 0.0
	buf[o + 10] = 1.0
	buf[o + 11] = p.z
	buf[o + 12] = c.r
	buf[o + 13] = c.g
	buf[o + 14] = c.b
	buf[o + 15] = c.a


func _mm_node(n: String, mat: String) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.material_override = load(mat)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _multimesh(size: float, ground: bool, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	if ground:
		q.orientation = PlaneMesh.FACE_Y
	mm.mesh = q
	mm.instance_count = n
	return mm


func _process(delta: float) -> void:
	# one clock for the shader lobes and the real spots (materials' `clock`; TIME would roll over and drift)
	_clock += delta
	var t := _clock
	for mmi in [halos, pools]:
		((mmi as MultiMeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("clock", t)
	for j in _spots.size():
		var s := _spots[j]
		if not s.visible or _spot_of[j] < 0 or _spot_of[j] >= beacons.size():
			continue
		var b: Dictionary = beacons[_spot_of[j]]
		var ang := t * SPIN + float(b["phase"]) * TAU
		var dir := Vector3(cos(ang), -0.28, sin(ang)).normalized()
		s.global_basis = Basis.looking_at(dir, Vector3.UP)
	_t -= delta
	if _t > 0.0:
		return
	_t = RELIGHT
	_assign_spots()


## Real SpotLight3D on the rotating beacons nearest the camera focus, at night only.
func _assign_spots() -> void:
	var budget := 0
	if CityLights.night() > 0.25:
		var lamps := Quality.lamp_light_budget()
		budget = 3 if lamps >= 12 else (2 if lamps > 0 else 0)
	while _spots.size() < budget:
		var s := SpotLight3D.new()
		s.name = "Spot%d" % _spots.size()
		s.spot_range = 16.0
		s.spot_angle = 24.0
		s.spot_attenuation = 1.2
		s.light_energy = 2.2
		s.shadow_enabled = false
		s.light_specular = 0.3
		s.light_volumetric_fog_energy = 2.5
		s.light_indirect_energy = 0.0
		add_child(s)
		_spots.append(s)
		_spot_of.append(-1)
	var focus := _focus()
	var order: Array = []
	for i in beacons.size():
		var b: Dictionary = beacons[i]
		if int(b["mode"]) != Mode.ROTATE:
			continue
		var d := focus.distance_to(b["pos"])
		if d < REAL_MAX_DIST:
			order.append([d, i])
	order.sort_custom(func(a: Array, c: Array) -> bool: return float(a[0]) < float(c[0]))
	for j in _spots.size():
		var s := _spots[j]
		if j < budget and j < order.size():
			var i := int(order[j][1])
			var b: Dictionary = beacons[i]
			s.visible = true
			s.global_position = (b["pos"] as Vector3) + Vector3(0, 0.15, 0)
			s.light_color = b["color"]
			_spot_of[j] = i
		else:
			s.visible = false
			_spot_of[j] = -1


func real_lights_on() -> int:
	var n := 0
	for s in _spots:
		if s.visible:
			n += 1
	return n


func _focus() -> Vector3:
	var rig := CameraRig.active()
	if rig != null:
		return rig.global_position
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	return cam.global_position if cam != null else Vector3.ZERO
