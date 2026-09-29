class_name CityLights
extends Node
## City night lighting (G2a, doc 08 §3.4), client only. Owns:
##   * the `city_lights` global (x night 0..1, y grid power, z game time in hours) read by window_city and
##     light_pool — DayNight feeds the night factor and the clock through set_sky();
##   * the power map (`city_power_map` + `city_power_rect`): a small R8 image over the city, 1 texel per
##     `cell` metres, where the grid sectors and the generator-powered blocks are painted (1 = powered). Windows
##     and lamps outside the map use the grid power (city_lights.y);
##   * street lamps: one MultiMesh of fake light pools on the ground + one of bulb halos per lamp set (2 draw
##     calls however many lamps), and a small pool of real OmniLight3D (Quality "lamp_lights": alto 12, medio 6,
##     compat / Web 0) moved to the powered lamps nearest the camera focus.

const POOL_MAT := "res://assets/materials/light_pool.tres"
const HALO_MAT := "res://assets/materials/light_halo.tres"
const LAMP_COLOR := Color(1.0, 0.78, 0.52)
const REAL_RANGE := 11.0
const REAL_ENERGY := 1.3
const REAL_MAX_DIST := 40.0
const RELIGHT_PERIOD := 0.3
## Fake pool strength kept under a lamp that has a real light.
const REAL_POOL_SCALE := 0.3

## The world's CityLights (client), where streamed city chunks register their lamps (C0: add_lamps / remove_lamps).
static var instance: CityLights
static var _night: float = 0.0
static var _power: float = 1.0
static var _hours: float = 12.0
static var _map: Image
static var _tex: ImageTexture
static var _rect := Vector4.ZERO

## Lamps: {pos: Vector3 (bulb), ground: float, power: float (0..1, <0 flicker), color: Color}
var lamps: Array[Dictionary] = []
var pools: MultiMeshInstance3D
var halos: MultiMeshInstance3D
var focus_override: Node3D
var _lights: Array[OmniLight3D] = []
var _real_lit: Dictionary = {}          # lamp index -> true while a real light sits on it
var _t: float = 0.0
var _by_owner: Dictionary = {}          # owner key (chunk) -> Array[Dictionary] of its lamps (C0 streaming)
var _rows_by_owner: Dictionary = {}     # owner key -> [pool rows, halo rows, power rev] (C1: made once per owner)
static var _power_rev: int = 0          # bumped by every power change (the cached rows hold the lamps' power)


func _enter_tree() -> void:
	instance = self


## The pool / halo nodes and their materials exist from the start: the first streamed chunk with lamps must not pay
## the material load inside a streaming step (C0).
func _ready() -> void:
	if pools == null:
		pools = _mm_node("Pools", POOL_MAT)
		halos = _mm_node("Halos", HALO_MAT)


func _exit_tree() -> void:
	if instance == self:
		instance = null


## C0: a streamed chunk's lamps ([bulb, ground y, power] each) join the set; the pools / halos are rebuilt.
func add_lamps(owner: int, list: Array) -> void:
	var own: Array = []
	for l in list:
		own.append({"pos": l[0], "ground": float(l[1]), "power": float(l[2]), "color": LAMP_COLOR})
	_by_owner[owner] = own
	# C1: the owner's buffer rows are made once (and again only after a power change); the MultiMesh buffers are
	# the owners' rows concatenated (the street dressing puts hundreds of lamps in the loaded chunks: a per-lamp
	# rebuild on every chunk load / unload was milliseconds of streaming)
	_rows_by_owner[owner] = _rows_of(own)
	_rebuild_owned()


static func _rows_of(own: Array) -> Array:
	var pb := PackedFloat32Array()
	var hb := PackedFloat32Array()
	pb.resize(own.size() * 16)
	hb.resize(own.size() * 16)
	for i in own.size():
		var l: Dictionary = own[i]
		var pos: Vector3 = l["pos"]
		var c := _custom_of(l)
		_row(pb, i * 16, Vector3(pos.x, float(l["ground"]) + 0.04, pos.z), c)
		_row(hb, i * 16, pos, c)
	return [pb, hb, _power_rev]


## C0: the chunk unloaded: its lamps leave the set.
func remove_lamps(owner: int) -> void:
	_rows_by_owner.erase(owner)
	if _by_owner.erase(owner):
		_rebuild_owned()


func _rebuild_owned() -> void:
	lamps.clear()
	var keys := _by_owner.keys()
	keys.sort()
	var pb := PackedFloat32Array()
	var hb := PackedFloat32Array()
	for k in keys:
		lamps.append_array(_by_owner[k])
		var rows: Array = _rows_by_owner.get(k, [])
		if rows.size() == 3 and int(rows[2]) != _power_rev:
			rows = _rows_of(_by_owner[k])
			_rows_by_owner[k] = rows
		if rows.size() == 3:
			pb.append_array(rows[0])
			hb.append_array(rows[1])
	if pb.size() != lamps.size() * 16:
		build()   # (lamps added through add_lamp as well: the per-lamp path)
	else:
		_build_from(pb, hb)
	_t = 0.0


## The MultiMeshes from ready buffers (the owners' rows): what build() makes, without the per-lamp loop.
func _build_from(pb: PackedFloat32Array, hb: PackedFloat32Array, pool_radius: float = 6.5, halo_size: float = 1.1) -> void:
	if pools == null:
		pools = _mm_node("Pools", POOL_MAT)
		halos = _mm_node("Halos", HALO_MAT)
	_real_lit = {}
	pools.multimesh = _multimesh(pool_radius * 2.0, true)
	halos.multimesh = _multimesh(halo_size, false)
	if lamps.is_empty():
		return
	pools.multimesh.buffer = pb
	halos.multimesh.buffer = hb


# ------------------------------------------------------------------ globals

## DayNight: night factor (0 day … 1 night) and the game clock (hours, for the slow re-roll of windows).
static func set_sky(night: float, hours: float) -> void:
	if absf(night - _night) < 0.002 and absf(hours - _hours) < 0.02:
		return
	_night = night
	_hours = hours
	_push()


## Grid power where the power map does not reach (0 = blackout, 1 = powered).
static func set_grid_power(p: float) -> void:
	_power = clampf(p, 0.0, 1.0)
	_power_rev += 1
	_push()


static func night() -> float:
	return _night


static func grid_power() -> float:
	return _power


static func _push() -> void:
	RenderingServer.global_shader_parameter_set("city_lights", Vector4(_night, _power, _hours, 0.0))


## Creates the power map over [x0, x0 + w] × [z0, z0 + d] at `cell` m per texel, filled with `fill`.
static func create_power_map(x0: float, z0: float, w: float, d: float, cell: float = 8.0, fill: float = 1.0) -> void:
	_power_rev += 1
	var sx := clampi(int(ceil(w / cell)), 1, 1024)
	var sz := clampi(int(ceil(d / cell)), 1, 1024)
	_map = Image.create(sx, sz, false, Image.FORMAT_R8)
	_map.fill(Color(fill, 0, 0))
	_rect = Vector4(x0, z0, w, d)
	_upload()


## Paints a world-space rectangle of the power map (a grid sector, or a generator-powered block = 1).
static func paint_power(x0: float, z0: float, x1: float, z1: float, value: float) -> void:
	_power_rev += 1
	if _map == null:
		return
	var sx := _map.get_width()
	var sz := _map.get_height()
	var ax := clampi(int(floor((minf(x0, x1) - _rect.x) / _rect.z * sx)), 0, sx - 1)
	var bx := clampi(int(ceil((maxf(x0, x1) - _rect.x) / _rect.z * sx)) - 1, 0, sx - 1)
	var az := clampi(int(floor((minf(z0, z1) - _rect.y) / _rect.w * sz)), 0, sz - 1)
	var bz := clampi(int(ceil((maxf(z0, z1) - _rect.y) / _rect.w * sz)) - 1, 0, sz - 1)
	for z in range(az, bz + 1):
		for x in range(ax, bx + 1):
			_map.set_pixel(x, z, Color(value, 0, 0))
	_upload()


## Power at a world point (map or grid), as the shaders see it.
static func power_at(p: Vector3) -> float:
	if _map == null or _rect.z <= 0.0:
		return _power
	var u := (p.x - _rect.x) / _rect.z
	var v := (p.z - _rect.y) / _rect.w
	if u < 0.0 or v < 0.0 or u >= 1.0 or v >= 1.0:
		return _power
	return _map.get_pixel(int(u * _map.get_width()), int(v * _map.get_height())).r


static func clear_power_map() -> void:
	_power_rev += 1
	_map = null
	_tex = null
	_rect = Vector4.ZERO
	RenderingServer.global_shader_parameter_set("city_power_rect", _rect)


static func _upload() -> void:
	if _tex == null or _tex.get_width() != _map.get_width() or _tex.get_height() != _map.get_height():
		_tex = ImageTexture.create_from_image(_map)
	else:
		_tex.update(_map)
	RenderingServer.global_shader_parameter_set("city_power_map", _tex)
	RenderingServer.global_shader_parameter_set("city_power_rect", _rect)


# ------------------------------------------------------------------ street lamps

## Adds a lamp (bulb position, ground height under it). power: 1 on, 0 off, negative = flickering.
func add_lamp(bulb: Vector3, ground_y: float, power: float = 1.0, color: Color = LAMP_COLOR) -> void:
	lamps.append({"pos": bulb, "ground": ground_y, "power": power, "color": color})


## Builds the pool and halo MultiMeshes for the lamps added so far (call again after adding / repowering).
func build(pool_radius: float = 6.5, halo_size: float = 1.1) -> void:
	if pools == null:
		pools = _mm_node("Pools", POOL_MAT)
		halos = _mm_node("Halos", HALO_MAT)
	_real_lit = {}
	pools.multimesh = _multimesh(pool_radius * 2.0, true)
	halos.multimesh = _multimesh(halo_size, false)
	if lamps.is_empty():
		return
	# one buffer upload per MultiMesh (C0: chunks add / remove lamps while streaming): 12 transform + 4 custom floats
	var pb := PackedFloat32Array()
	var hb := PackedFloat32Array()
	pb.resize(lamps.size() * 16)
	hb.resize(lamps.size() * 16)
	for i in lamps.size():
		var l: Dictionary = lamps[i]
		var pos: Vector3 = l["pos"]
		var c := lamp_custom(i)
		var o := i * 16
		_row(pb, o, Vector3(pos.x, float(l["ground"]) + 0.04, pos.z), c)
		_row(hb, o, pos, c)
	pools.multimesh.buffer = pb
	halos.multimesh.buffer = hb


static func _row(b: PackedFloat32Array, o: int, p: Vector3, c: Color) -> void:
	b[o] = 1.0
	b[o + 1] = 0.0
	b[o + 2] = 0.0
	b[o + 3] = p.x
	b[o + 4] = 0.0
	b[o + 5] = 1.0
	b[o + 6] = 0.0
	b[o + 7] = p.y
	b[o + 8] = 0.0
	b[o + 9] = 0.0
	b[o + 10] = 1.0
	b[o + 11] = p.z
	b[o + 12] = c.r
	b[o + 13] = c.g
	b[o + 14] = c.b
	b[o + 15] = c.a


## INSTANCE_CUSTOM of lamp i for light_pool.gdshader: rgb tint, a = intensity × power at the lamp (negative = flicker).
func lamp_custom(i: int) -> Color:
	return _custom_of(lamps[i])


static func _custom_of(l: Dictionary) -> Color:
	var p := float(l["power"])
	var pw := power_at(l["pos"])
	var col: Color = l["color"]
	return Color(col.r, col.g, col.b, p * pw if p >= 0.0 else -absf(p) * pw)


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


## Moves the real-light pool to the powered lamps nearest the camera focus (only at night).
func _update_real_lights() -> void:
	var budget := Quality.lamp_light_budget() if _night > 0.2 else 0
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
		if float(l["power"]) == 0.0 or power_at(l["pos"]) < 0.5:
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
			var l: Dictionary = lamps[li]
			o.visible = true
			o.global_position = (l["pos"] as Vector3) + Vector3(0, -0.3, 0)
			o.light_energy = REAL_ENERGY * _night
			lit[li] = true
		else:
			o.visible = false
	# a lamp with a real light keeps only a faint fake pool (the light does the job; no double brightness)
	if pools != null and pools.multimesh != null and lit != _real_lit:
		for i in lamps.size():
			if lit.has(i) != _real_lit.has(i):
				var cst := lamp_custom(i)
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
