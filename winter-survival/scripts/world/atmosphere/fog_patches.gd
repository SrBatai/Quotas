class_name FogPatches
extends Node3D
## G2b local fog (doc 08 §3.5 «FogVolume locales»): a small pool of FogVolume nodes placed where fog belongs near
## the camera — haze and steam over lit fires, a street-level mist layer in the city at night, mist lying on the
## frozen lake and the río Albo at dawn and at night. FogVolumes only draw with volumetric fog, which Atmosphere
## turns on only on `alto` (Forward+) and only in a blizzard or at night: on `medio`, `compat` and the Web this node
## holds no volumes at all (their depth comes from the denser exponential / height fog). Client only. Densities are
## per metre like the global volumetric fog (0.0045 at night): a fire's haze 0.07 lets ~75 % through its 4 m.

const POOL := 6
const REFRESH := 1.0
const FIRE_RANGE := 40.0
const MIST_RANGE := 160.0
## Frozen water where mist gathers: [centre (x, z), half size (x, z), water level offset]. The valley lake comes
## from the Terrain at runtime; the río Albo under the Puente de Hierro (C0, x 2 262–2 612, z −384).
const WATER := [[Vector2(2437.0, -384.0), Vector2(90.0, 40.0)]]

var active: bool = false
var volumes: Array[FogVolume] = []
var _night: float = 0.0
var _blizzard: float = 0.0
var _city: float = 0.0
var _t: float = 0.0
var _noise: NoiseTexture3D
var _mats: Dictionary = {}


## Atmosphere.post_apply, every frame: whether volumetrics are on and the light of the moment.
func set_state(vol_on: bool, night_amount: float, blizzard: float, city: float) -> void:
	_night = night_amount
	_blizzard = blizzard
	_city = city
	if vol_on != active:
		active = vol_on
		_t = 0.0
		if not active:
			for v in volumes:
				v.visible = false


func _process(delta: float) -> void:
	if not active:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = REFRESH
	_place()


func _place() -> void:
	var focus := _focus()
	var wants: Array = []   # [priority distance, kind, position, size]
	# haze and steam over lit fires (their light scatters in it)
	for n in get_tree().get_nodes_in_group("heat_source") + get_tree().get_nodes_in_group("thaw_source"):
		var n3 := n as Node3D
		if n3 == null:
			continue
		var d := n3.global_position.distance_to(focus)
		if d < FIRE_RANGE:
			wants.append([d, "fire", n3.global_position + Vector3(0, 2.2, 0), Vector3(4.5, 5.0, 4.5)])
	# the city street mist at night (moves with the camera; no noise texture, so the move is invisible)
	if _city > 0.3 and _night > 0.5 and _blizzard < 0.5:
		var p := Vector3(snappedf(focus.x, 4.0), _ground(focus) + 1.0, snappedf(focus.z, 4.0))
		wants.append([0.0, "street", p, Vector3(90.0, 3.0, 90.0)])
	# mist over frozen water, dawn and night
	var mist := maxf(_night, smoothstep(5.0, 6.5, WorldState.hour_now()) * (1.0 - smoothstep(8.5, 10.5, WorldState.hour_now())))
	if mist > 0.3 and _blizzard < 0.5:
		for w in _water():
			var c: Vector2 = w[0]
			var half: Vector2 = w[1]
			var d := Vector2(focus.x, focus.z).distance_to(c) - half.length()
			if d < MIST_RANGE:
				wants.append([maxf(d, 1.0), "water", Vector3(c.x, float(w[2]) + 0.6, c.y), Vector3(half.x * 2.0, 2.4, half.y * 2.0)])
	wants.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	while volumes.size() < mini(POOL, wants.size()):
		var v := FogVolume.new()
		v.name = "Fog%d" % volumes.size()
		add_child(v)
		volumes.append(v)
	for i in volumes.size():
		var v := volumes[i]
		if i >= wants.size():
			v.visible = false
			continue
		var wnt: Array = wants[i]
		v.visible = true
		v.global_position = wnt[2]
		v.size = wnt[3]
		v.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX if str(wnt[1]) == "street" else RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		v.material = _material(str(wnt[1]))


func _material(kind: String) -> FogMaterial:
	if _mats.has(kind):
		return _mats[kind]
	var m := FogMaterial.new()
	match kind:
		"fire":
			m.density = 0.07
			m.albedo = Color("#B9B2AA")
			m.edge_fade = 0.6
			m.height_falloff = 0.25
			m.density_texture = _noise_tex()
		"street":
			m.density = 0.018
			m.albedo = Color("#8E9AB2")
			m.edge_fade = 0.25
			m.height_falloff = 0.8
		_:
			m.density = 0.05
			m.albedo = Color("#C7D2E2")
			m.edge_fade = 0.45
			m.height_falloff = 1.2
			m.density_texture = _noise_tex()
	_mats[kind] = m
	return m


func _noise_tex() -> NoiseTexture3D:
	if _noise != null:
		return _noise
	var fn := FastNoiseLite.new()
	fn.frequency = 0.08
	fn.fractal_octaves = 3
	_noise = NoiseTexture3D.new()
	_noise.width = 32
	_noise.height = 32
	_noise.depth = 32
	_noise.seamless = true
	_noise.noise = fn
	return _noise


func _water() -> Array:
	var out: Array = []
	for w in WATER:
		var c: Vector2 = w[0]
		out.append([c, w[1], _ground(Vector3(c.x, 0, c.y))])
	var world := World.instance
	if world != null and world.terrain != null:
		var lc: Vector2 = world.terrain.lake_center
		var r: float = world.terrain.lake_radius
		out.append([lc, Vector2(r, r) * 0.8, world.terrain.lake_level])
	return out


func _ground(p: Vector3) -> float:
	var world := World.instance
	if world != null and world.is_configured:
		return world.get_height(p.x, p.z)
	return p.y


func _focus() -> Vector3:
	var rig := CameraRig.active()
	if rig != null:
		return rig.global_position
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	return cam.global_position + (-cam.global_basis.z) * 20.0 if cam != null else Vector3.ZERO
