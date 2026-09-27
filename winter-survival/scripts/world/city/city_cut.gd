class_name CityCut
extends Node
## «Corte urbano» manager (W0, doc 09 §3.4), client only, one per world. Every frame it writes the global shader
## parameters of assets/shaders/city_cut.gdshaderinc from the gameplay camera and the LOCAL player (never from
## animation state, remote players or the network):
##   ws_cut_player   feet + on flag           ws_cut_floor    player floor level, blended over 0.25 s + stub
##   ws_cut_view     dir to camera, W, R      ws_cut_capsule  chest + radius
##   ws_cut_aim      second zone (cursor)     ws_cut_own(_ext) footprint / stub / top of the player's own building
##   ws_cut_style    dither strength, props capsule, edge width
##   ws_cut_cam(_ext) footprint of the building that contains the camera (cut whole above the floor cut)
## W, R and Rc scale with the camera distance and pitch (camera profiles), so the player stays visible at every
## zoom. It also finds the building the local player stands in (registered CityBuilding components) and tells it
## the floor (roof and upper floor groups go shadow-only). is_cut() mirrors the shader in GDScript (threshold 0.5)
## for the cursor ray (ray_through_cut) and the tests. Cost: 8 global writes + an AABB test per building.

const STUB := 0.4
const OWN_STUB := 0.6
const CORRIDOR_W := 10.0
const EDGE := 4.0
const ZONE_MIN := 16.0
const ZONE_MAX := 26.0
const CAPSULE_R := 3.5
const CAPSULE_R_FAR := 4.5
const FLOOR_BLEND := 0.25
const RETARGET := 0.25
const CHEST := 1.2
const AIM_MIN := 3.0
const AIM_MAX := 30.0
const CEILING_GAP := 0.35
## A building whose footprint grown by this margin contains the camera is cut whole above the floor cut.
const CAMERA_MARGIN := 6.0
const GLOBALS := ["ws_cut_player", "ws_cut_floor", "ws_cut_view", "ws_cut_capsule", "ws_cut_aim", "ws_cut_own",
	"ws_cut_own_ext", "ws_cut_style", "ws_cut_cam", "ws_cut_cam_ext"]

enum Kind { STRUCT, CAPSULE }

## Registry grid cell (m): a building is listed in every cell its footprint circle (+ the camera margin) touches,
## so the per-frame queries look at one cell for the feet and one for the camera, however big the city.
const GRID_CELL := 32.0

static var instance: CityCut
static var _buildings: Array = []
static var _grid: Dictionary = {}          # Vector2i -> Array[CityBuilding]
static var _cells_of: Dictionary = {}      # CityBuilding -> Array[Vector2i]

## Master switch (Quality "city_cut"; miradores turn it off).
var enabled: bool = true
## Capsule on city props (world_vcol_capsule); follows the active camera profile unless forced.
var props_capsule: bool = false
var props_capsule_forced: int = -1        # -1 follow the profile, 0 off, 1 on
## 1 = the core of the cut is fully removed (accessibility option could lower it).
var dither_strength: float = 1.0
## Second zone at the aim point (Commandos lesson: plan what you point at). Off by default until aiming exists.
var aim_zone: bool = false
## Bench: evaluate every term of the cut in the shaders but remove nothing (measures the ALU cost of the cut
## with the same pixels on screen as with the cut off).
var eval_only: bool = false
## Bench / tests.
var player_override: Node3D
var camera_override: Camera3D
## Building the local player stands in (or null) and the floor; building that contains the camera (or null).
var own: CityBuilding
var own_floor: int = -1
var camera_building: CityBuilding
## Building whose roof the local player stands on (its camera-side parapet / roof plant is stubbed in the shader).
var roof_building: CityBuilding
## Last values written (readable headless, where the dummy renderer keeps no globals).
var state: Dictionary = {}

var _y_from: float = 0.0
var _y_to: float = 0.0
var _t: float = 1.0
var _floor_init: bool = false


static func register(b: CityBuilding) -> void:
	if _buildings.has(b):
		return
	_buildings.append(b)
	var o := b.root.global_position
	var r := b.reach() + CAMERA_MARGIN
	var cells: Array = []
	for cx in range(floori((o.x - r) / GRID_CELL), floori((o.x + r) / GRID_CELL) + 1):
		for cz in range(floori((o.z - r) / GRID_CELL), floori((o.z + r) / GRID_CELL) + 1):
			var key := Vector2i(cx, cz)
			if not _grid.has(key):
				_grid[key] = []
			(_grid[key] as Array).append(b)
			cells.append(key)
	_cells_of[b] = cells


static func unregister(b: CityBuilding) -> void:
	_buildings.erase(b)
	for key in _cells_of.get(b, []):
		var list: Array = _grid.get(key, [])
		list.erase(b)
		if list.is_empty():
			_grid.erase(key)
	_cells_of.erase(b)
	if instance != null and instance.own == b:
		instance.own = null
		instance.own_floor = -1


static func buildings() -> Array:
	return _buildings


## Buildings whose footprint (+ camera margin) may contain the world point.
static func candidates(p: Vector3) -> Array:
	return _grid.get(Vector2i(floori(p.x / GRID_CELL), floori(p.z / GRID_CELL)), [])


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null
		_write_off()


func _ready() -> void:
	enabled = Quality.city_cut_enabled()
	Quality.preset_changed.connect(func(_p: StringName) -> void: enabled = Quality.city_cut_enabled())


func _process(delta: float) -> void:
	update(delta)


func _player() -> Node3D:
	if player_override != null:
		return player_override if is_instance_valid(player_override) and player_override.is_inside_tree() else null
	var rig := CameraRig.active()
	if rig != null and rig.player != null and rig.player.is_inside_tree():
		return rig.player
	var lp := GameFlow.local_player() as Node3D
	return lp if lp != null and lp.is_inside_tree() else null


func _camera() -> Camera3D:
	if camera_override != null:
		return camera_override if is_instance_valid(camera_override) else null
	var rig := CameraRig.active()
	if rig != null and rig.camera != null and rig.camera.current:
		return rig.camera
	return null


## Writes the globals for this frame. Called by _process; tests call it directly.
func update(delta: float) -> void:
	var cam := _camera()
	var pl := _player()
	if not enabled or cam == null or pl == null or _buildings.is_empty():
		# no city loaded (the forest): the city materials are not drawn, nothing to write
		if bool(state.get("on", true)):
			_write_off()
		_set_own(null, -1)
		return
	var feet := pl.global_position
	var c := cam.global_position
	# own building (the first registered building whose footprint and height contain the feet)
	var ob: CityBuilding = null
	var cb: CityBuilding = null
	var rb: CityBuilding = null
	for b in candidates(feet):
		if not is_instance_valid(b):
			continue
		if ob == null and (b as CityBuilding).contains(feet):
			ob = b
		if rb == null and (b as CityBuilding).on_roof(feet):
			rb = b
	for b in candidates(c):
		if is_instance_valid(b) and (b as CityBuilding).hugs_camera(c, CAMERA_MARGIN):
			cb = b
			break
	roof_building = rb if ob == null else null
	var k := ob.floor_index(feet.y) if ob != null else -1
	_set_own(ob, k)
	# floor level the cut is referred to: follows the feet, retargeted in 0.25 m steps and blended over 0.25 s
	var level := ob.floor_level(k) if ob != null else feet.y
	if not _floor_init:
		_y_from = level
		_y_to = level
		_t = 1.0
		_floor_init = true
	elif absf(level - _y_to) > RETARGET:
		_y_from = lerpf(_y_from, _y_to, _t)
		_y_to = level
		_t = 0.0
	_t = minf(1.0, _t + delta / FLOOR_BLEND) if delta > 0.0 else 1.0
	var to_cam := Vector2(c.x - feet.x, c.z - feet.z)
	var hd := to_cam.length()
	var dir := to_cam / hd if hd > 0.01 else Vector2(0.7071, 0.7071)
	var zone := clampf(0.65 * hd + 6.0, ZONE_MIN, ZONE_MAX)
	var chest := feet + Vector3(0, CHEST, 0)
	var cd := c.distance_to(chest)
	var rc := lerpf(CAPSULE_R, CAPSULE_R_FAR, clampf((cd - 24.0) / 14.0, 0.0, 1.0))
	var aim := Vector4.ZERO
	if aim_zone and pl.get("aim_point") != null:
		var ap: Vector3 = pl.get("aim_point")
		var ad := Vector2(ap.x - feet.x, ap.z - feet.z).length()
		if ad > AIM_MIN and ad < AIM_MAX:
			aim = Vector4(ap.x, ap.y, ap.z, 1.0)
	var props := props_capsule
	var rig := CameraRig.active() if camera_override == null else null
	if rig != null:
		props = rig.profile.props_capsule   # the active camera profile decides (city / rooftop: on)
	if props_capsule_forced >= 0:
		props = props_capsule_forced == 1
	var own_v := Vector4.ZERO
	var own_ext := Vector4(1, 0, 0, 0)
	if ob != null:
		var box := ob.own_box()
		var cen: Vector2 = box["centre"]
		var half: Vector2 = box["half"]
		var yaw: float = box["yaw"]
		own_v = Vector4(cen.x, cen.y, half.x, half.y)
		own_ext = Vector4(cos(yaw), sin(yaw), ob.floor_level(k) + OWN_STUB, ob.floor_level(k + 1) - CEILING_GAP)
	elif roof_building != null:
		# on a roof: the camera-side parapet and roof plant drop to the 0.6 m stub; nothing is hidden on the CPU
		var rbox := roof_building.own_box()
		var rcen: Vector2 = rbox["centre"]
		var rh: Vector2 = rbox["half"]
		var ry: float = rbox["yaw"]
		var roof_y := roof_building.base_y() + roof_building.roof_level
		own_v = Vector4(rcen.x, rcen.y, rh.x, rh.y)
		own_ext = Vector4(cos(ry), sin(ry), roof_y + OWN_STUB, roof_y + 1.0e4)
	var cam_v := Vector4.ZERO
	var cam_ext := Vector4(1, 0, 0, 0)
	camera_building = cb
	if cb != null and cb != ob and cb != roof_building:
		var cbox := cb.own_box()
		var cc: Vector2 = cbox["centre"]
		var ch: Vector2 = cbox["half"]
		cam_v = Vector4(cc.x, cc.y, ch.x, ch.y)
		cam_ext = Vector4(cos(float(cbox["yaw"])), sin(float(cbox["yaw"])), 0.0, 0.0)
	state = {
		"on": true,
		"ws_cut_player": Vector4(feet.x, feet.y, feet.z, 1.0),
		"ws_cut_floor": Vector4(_y_from, _y_to, _t, STUB),
		"ws_cut_view": Vector4(dir.x, dir.y, CORRIDOR_W, zone),
		"ws_cut_capsule": Vector4(chest.x, chest.y, chest.z, rc),
		"ws_cut_aim": aim,
		"ws_cut_own": own_v,
		"ws_cut_own_ext": own_ext,
		"ws_cut_style": Vector4(dither_strength, 1.0 if props else 0.0, EDGE, 0.0),
		"ws_cut_cam": cam_v,
		"ws_cut_cam_ext": cam_ext,
		"camera": c,
	}
	if eval_only:
		state["ws_cut_floor"] = Vector4(_y_from, _y_to, _t, 1.0e5)
		state["ws_cut_view"] = Vector4(dir.x, dir.y, 0.0, 0.0)
		state["ws_cut_capsule"] = Vector4(chest.x, chest.y, chest.z, 0.02)
		state["ws_cut_own"] = Vector4.ZERO
		state["ws_cut_cam"] = Vector4.ZERO
	for g in GLOBALS:
		RenderingServer.global_shader_parameter_set(g, state[g])


func _write_off() -> void:
	state = {"on": false, "ws_cut_player": Vector4.ZERO}
	RenderingServer.global_shader_parameter_set("ws_cut_player", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("ws_cut_own", Vector4.ZERO)


func _set_own(b: CityBuilding, k: int) -> void:
	if b != own:
		if own != null and is_instance_valid(own):
			own.set_player_floor(-1)
		own = b
	own_floor = k
	if own != null:
		own.set_player_floor(k)


# ------------------------------------------------------------------ GDScript mirror of the shader

static func _smooth(e0: float, e1: float, x: float) -> float:
	if e1 <= e0:
		return 1.0 if x >= e1 else 0.0
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _slab_above(y_ref: float, base_y: float, ground_h: float, floor_h: float) -> float:
	var k := maxf(0.0, ceil((y_ref + 0.5 - base_y - ground_h) / floor_h))
	return base_y + ground_h + k * floor_h


static func _zone(p: Vector3, c: Vector3, centre: Vector3, r: float, s: Dictionary) -> float:
	var h := c.y - p.y
	if h <= 0.05:
		return 1.0
	var pl: Vector4 = s["ws_cut_player"]
	var g := c + (p - c) * ((c.y - pl.y) / h)
	var e := maxf((s["ws_cut_style"] as Vector4).z, 0.5)
	return 1.0 - _smooth(r - e, r, Vector2(g.x - centre.x, g.z - centre.z).length())


static func _capsule(p: Vector3, c: Vector3, s: Dictionary) -> float:
	var cap: Vector4 = s["ws_cut_capsule"]
	var r := cap.w
	if r <= 0.01:
		return 0.0
	var ba := Vector3(cap.x, cap.y, cap.z) - c
	var t := clampf((p - c).dot(ba) / maxf(ba.dot(ba), 1e-4), 0.0, 1.0)
	return (1.0 - _smooth(r * 0.55, r, p.distance_to(c + ba * t))) * (1.0 if t <= 0.96 else 0.0)


static func _in_box(p: Vector3, o: Vector4, e: Vector4) -> bool:
	if o.z <= 0.0:
		return false
	var d := Vector2(p.x - o.x, p.z - o.y)
	var l := Vector2(d.x * e.x - d.y * e.y, d.x * e.y + d.y * e.x)
	return absf(l.x) <= o.z and absf(l.y) <= o.w


static func _in_own(p: Vector3, s: Dictionary) -> bool:
	return _in_box(p, s["ws_cut_own"], s["ws_cut_own_ext"])


## Fade 0 (kept) … 1 (removed) of a fragment at p seen from c with the globals `s` (CityCut.state).
## Same maths as city_cut_struct_fade / city_cut_capsule_discard; the shader discards where fade × strength
## exceeds a 4×4 Bayer threshold, so fade ≥ 0.97 is "fully removed" and 0 "fully kept".
static func fade_at(p: Vector3, c: Vector3, s: Dictionary, kind: int = Kind.STRUCT, base_y: float = 0.0,
		ground_h: float = 3.3, floor_h: float = 3.0) -> float:
	if not bool(s.get("on", false)):
		return 0.0
	var style: Vector4 = s["ws_cut_style"]
	if kind == Kind.CAPSULE:
		return _capsule(p, c, s) * style.x if style.y > 0.5 else 0.0
	var plv: Vector4 = s["ws_cut_player"]
	var pl := Vector3(plv.x, plv.y, plv.z)
	var view: Vector4 = s["ws_cut_view"]
	var d_side := Vector2(p.x - pl.x, p.z - pl.z).dot(Vector2(view.x, view.y))
	var side := _smooth(-3.0, 1.0, d_side)
	var fade := 0.0
	if _in_own(p, s):
		var ext: Vector4 = s["ws_cut_own_ext"]
		if p.y > ext.w:
			fade = 1.0
		elif p.y > ext.z:
			fade = side if ext.w > 5000.0 else _smooth(-1.5, 0.5, d_side)
	elif side > 0.0:
		var fl: Vector4 = s["ws_cut_floor"]
		var y_cut := lerpf(_slab_above(fl.x, base_y, ground_h, floor_h), _slab_above(fl.y, base_y, ground_h, floor_h), fl.z) + fl.w
		if p.y > y_cut and _in_box(p, s.get("ws_cut_cam", Vector4.ZERO), s.get("ws_cut_cam_ext", Vector4(1, 0, 0, 0))):
			fade = side
		elif p.y > y_cut:
			var ab := Vector2(pl.x - c.x, pl.z - c.z)
			var u := clampf(Vector2(p.x - c.x, p.z - c.z).dot(ab) / maxf(ab.dot(ab), 1e-4), 0.0, 1.0)
			var e := maxf(style.z, 0.5)
			var q := Vector2(c.x, c.z) + ab * u
			var corridor := 1.0 - _smooth(view.z - e, view.z, Vector2(p.x, p.z).distance_to(q))
			var zone := _zone(p, c, pl, view.w, s)
			var aim: Vector4 = s["ws_cut_aim"]
			if aim.w > 0.5:
				zone = maxf(zone, _zone(p, c, Vector3(aim.x, aim.y, aim.z), view.w * 0.5, s))
			fade = side * maxf(corridor, zone)
	return maxf(fade, _capsule(p, c, s)) * style.x


## Is the world point cut away right now (fade > 0.5)? `base_y`, `ground_h`, `floor_h` describe the building.
func is_cut(p: Vector3, kind: int = Kind.STRUCT, base_y: float = 0.0, ground_h: float = 3.3, floor_h: float = 3.0) -> bool:
	if not bool(state.get("on", false)):
		return false
	return fade_at(p, state["camera"], state, kind, base_y, ground_h, floor_h) > 0.5


## Is this collider part of a cut city building at the hit point?
func is_hit_cut(collider: Object, p: Vector3) -> bool:
	if not bool(state.get("on", false)) or collider == null or not (collider is Node):
		return false
	var n := collider as Node
	while n != null:
		if n.is_in_group(CityBuilding.GROUP):
			var b := n.get_node_or_null("CityBuilding") as CityBuilding
			if b == null:
				return false
			return is_cut(p, Kind.STRUCT, b.base_y(), b.ground_h, b.floor_h)
		n = n.get_parent()
	return false


## Cursor ray that goes through cut buildings (doc 09 §3.1 layer F): repeats the query excluding a collider hit at
## a cut point, up to 4 times. Without a CityCut (or with the cut off) it is a plain intersect_ray.
static func ray_through_cut(space: PhysicsDirectSpaceState3D, q: PhysicsRayQueryParameters3D) -> Dictionary:
	var hit := space.intersect_ray(q)
	if instance == null or not bool(instance.state.get("on", false)):
		return hit
	var excl := q.exclude.duplicate()
	for i in 4:
		if hit.is_empty() or not instance.is_hit_cut(hit.collider, hit.position):
			return hit
		excl.append((hit.collider as CollisionObject3D).get_rid() if hit.collider is CollisionObject3D else hit.rid)
		q.exclude = excl
		hit = space.intersect_ray(q)
	return hit
