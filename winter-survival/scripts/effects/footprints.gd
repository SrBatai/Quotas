class_name Footprints
extends Node3D
## Snow trail map (G1, doc 06 §3.9 option A; ARQ v2 §14). Every visible character (FootprintEmitter: players,
## wolves, deer) calls `stamp()`; each print is written into a world-space RGBA8 texture (R = depression,
## G = raised rim) that the terrain shader reads as displacement + normal + darkening, so any number of prints
## costs no draw calls, repeated steps dig a trench and the rim catches the real sun. The map covers MAP_SIZE m
## around the local camera target and is shifted (re-projected) in whole texels when the player walks
## RECENTER_DIST m from its centre. Back-ends (same API): "drawable" = DrawableTexture2D.blit_rect on the GPU
## (4.7, Forward+ and Compatibility), "cpu" = Image + ImageTexture.update (any renderer; also the headless
## smoke test, where the dummy renderer ignores the upload). Prints fade (decay) slowly and a blizzard buries them.

const MAP_SIZE := 56.0
const RESOLUTION := 1024
const RECENTER_DIST := 8.0
const STAMP_ANGLES := 16
const FOOT_LENGTH := 0.42
const FOOT_WIDTH := 0.26
## Decay per second (multiplicative, "drawable" back-end): calm ≈ 70 s half-life, blizzard buries in seconds.
const DECAY_KEEP := 0.99
const DECAY_KEEP_BLIZZARD := 0.80
const DECAY_INTERVAL := 1.0
const RECENT_MAX := 64

var backend: String = "cpu"
var texture: Texture2D
var rect := Rect2(-MAP_SIZE * 0.5, -MAP_SIZE * 0.5, MAP_SIZE, MAP_SIZE)
## Recent stamp positions (world), newest last: tests / audio use it.
var recent: Array[Vector3] = []

var _image: Image
var _dirty: bool = false
var _stamps: Array[Texture2D] = []
var _stamp_add: Material
var _stamp_mul: Material
var _white: ImageTexture
var _back: Texture2D
var _decay_t: float = 0.0
var _material: ShaderMaterial


func _ready() -> void:
	_material = Assets.get_terrain_material()
	var preferred := Quality.trail_backend() if DisplayServer.get_name() != "headless" else "cpu"
	_setup(preferred)
	_publish()


func _setup(preferred: String) -> void:
	backend = preferred
	if backend == "drawable" and ClassDB.class_exists("DrawableTexture2D") and ClassDB.class_exists("BlitMaterial"):
		texture = _make_drawable()
		_back = _make_drawable()
		for i in STAMP_ANGLES:
			_stamps.append(_make_stamp(64, float(i) * TAU / float(STAMP_ANGLES)))
		_stamp_add = ClassDB.instantiate("BlitMaterial")
		_stamp_add.set("blend_mode", ClassDB.class_get_integer_constant("BlitMaterial", "BLEND_MODE_ADD"))
		_stamp_mul = ClassDB.instantiate("BlitMaterial")
		_stamp_mul.set("blend_mode", ClassDB.class_get_integer_constant("BlitMaterial", "BLEND_MODE_MUL"))
		var w := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		w.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(w)
	else:
		backend = "cpu"
		_image = Image.create(RESOLUTION, RESOLUTION, false, Image.FORMAT_RGBA8)
		_image.fill(Color(0, 0, 0, 1))
		texture = ImageTexture.create_from_image(_image)


func _make_drawable() -> Texture2D:
	var dt: Texture2D = ClassDB.instantiate("DrawableTexture2D")
	dt.call("setup", RESOLUTION, RESOLUTION, 0, Color(0, 0, 0, 1), false)  # DRAWABLE_FORMAT_RGBA8
	return dt


func _publish() -> void:
	_material.set_shader_parameter("trail_map", texture)
	_material.set_shader_parameter("trail_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	_material.set_shader_parameter("trail_enabled", true)


func _exit_tree() -> void:
	if _material != null:
		_material.set_shader_parameter("trail_enabled", false)


## Foot profile in foot space (metres, +y = forward): R = depression (1 inside), G = raised rim ring.
static func _foot(fx: float, fy: float, length: float, width: float) -> Vector2:
	var w := width * 0.5 * (1.0 + 0.10 * fy / (length * 0.5))
	var rr := Vector2(fx / w, fy / (length * 0.5)).length()
	var inner := 1.0 - smoothstep(0.62, 0.92, rr)
	var ring := smoothstep(0.70, 0.95, rr) * (1.0 - smoothstep(0.98, 1.22, rr))
	return Vector2(inner, ring)


## Pre-rotated stamp (the blit has no rotation): a unit foot 1 m long inside a 2.6 m cell.
static func _make_stamp(size: int, yaw: float) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var cs := cos(yaw)
	var sn := sin(yaw)
	for py in size:
		for px in size:
			var d := (Vector2(px, py) + Vector2(0.5, 0.5)) / float(size) * 2.6 - Vector2(1.3, 1.3)
			var fx := d.x * cs - d.y * sn
			var fy := d.x * sn + d.y * cs
			var f := _foot(fx, fy, 1.0, 0.62)
			img.set_pixel(px, py, Color(f.x, f.y * (1.0 - f.x), 0.0, 1.0))
	return ImageTexture.create_from_image(img)


func _to_px(p: Vector2) -> Vector2:
	return (p - rect.position) / rect.size * float(RESOLUTION)


## One footprint. `pos` = ground point under the character, `yaw` = facing (radians, +Z forward = 0), `left`
## picks the foot side, `size` scales the print (1.0 = human boot; wolves / deer use ~0.5).
func stamp(pos: Vector3, yaw: float, left: bool, size: float = 1.0) -> void:
	# character right = -X of a +Z-facing model, yawed
	var side := Vector3(-cos(yaw), 0, sin(yaw)) * (-0.15 if left else 0.15) * size
	var p := pos + side
	recent.append(p)
	if recent.size() > RECENT_MAX:
		recent.pop_front()
	var c2 := Vector2(p.x, p.z)
	if not rect.has_point(c2):
		return
	var length := FOOT_LENGTH * size
	var width := FOOT_WIDTH * size
	var strength := clampf(0.5 + 0.5 * size, 0.6, 1.0)
	# the emitter's yaw is the model facing (+Z); the foot points along it
	var foot_yaw := yaw
	if backend == "drawable":
		var c := _to_px(c2)
		var half := Vector2(length, length) / rect.size * float(RESOLUTION) * 0.5 * 1.3
		var idx := int(round(fposmod(foot_yaw, TAU) / TAU * float(STAMP_ANGLES))) % STAMP_ANGLES
		texture.call("blit_rect", Rect2i(Vector2i(c - half), Vector2i(maxi(int(half.x * 2.0), 2), maxi(int(half.y * 2.0), 2))), _stamps[idx], Color(strength, strength, 1.0, 1.0), 0, _stamp_add)
		return
	var px_per_m := float(RESOLUTION) / rect.size.x
	var c := _to_px(c2)
	var r := length * 0.5 * px_per_m + 2.0
	var x0 := maxi(int(c.x - r), 0)
	var x1 := mini(int(c.x + r) + 1, RESOLUTION - 1)
	var y0 := maxi(int(c.y - r), 0)
	var y1 := mini(int(c.y + r) + 1, RESOLUTION - 1)
	var cs := cos(foot_yaw)
	var sn := sin(foot_yaw)
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var d := (Vector2(px, py) + Vector2(0.5, 0.5) - c) / px_per_m
			var fx := d.x * cs - d.y * sn
			var fy := d.x * sn + d.y * cs
			var f := _foot(fx, fy, length, width)
			if f.x <= 0.0 and f.y <= 0.0:
				continue
			var old := _image.get_pixel(px, py)
			var nr := minf(old.r + f.x * strength, 1.0)
			var ng := minf(maxf(old.g, f.y * strength * (1.0 - nr)), 1.0)
			_image.set_pixel(px, py, Color(nr, ng, 0.0, 1.0))
	_dirty = true


## Number of recent prints within `radius` of `pos` (tests).
func count_near(pos: Vector3, radius: float) -> int:
	var n := 0
	for p in recent:
		if p.distance_to(pos) < radius:
			n += 1
	return n


## Fresh snow: wipes the map.
func clear() -> void:
	recent.clear()
	if backend == "drawable":
		texture.call("blit_rect", Rect2i(0, 0, RESOLUTION, RESOLUTION), _white, Color(0, 0, 0, 1), 0, _stamp_mul)
	else:
		_image.fill(Color(0, 0, 0, 1))
		_dirty = true


## Shifts the map so `center` becomes its centre (whole texels; the content moves with the world).
func recenter(center: Vector2) -> void:
	var texel := rect.size.x / float(RESOLUTION)
	var new_pos := (center - rect.size * 0.5).snapped(Vector2(texel, texel))
	var delta_px := Vector2i(((rect.position - new_pos) / texel).round())
	if delta_px == Vector2i.ZERO:
		return
	if backend == "drawable":
		# double buffer: clear the back texture, copy the old content shifted, swap
		_back.call("blit_rect", Rect2i(0, 0, RESOLUTION, RESOLUTION), _white, Color(0, 0, 0, 1), 0, _stamp_mul)
		_back.call("blit_rect", Rect2i(delta_px, Vector2i(RESOLUTION, RESOLUTION)), texture, Color.WHITE, 0, null)
		var t := texture
		texture = _back
		_back = t
	else:
		var moved := Image.create(RESOLUTION, RESOLUTION, false, Image.FORMAT_RGBA8)
		moved.fill(Color(0, 0, 0, 1))
		moved.blit_rect(_image, Rect2i(0, 0, RESOLUTION, RESOLUTION), delta_px)
		_image = moved
		_dirty = true
	rect.position = new_pos
	_publish()


func _decay(keep: float) -> void:
	if backend == "drawable":
		texture.call("blit_rect", Rect2i(0, 0, RESOLUTION, RESOLUTION), _white, Color(keep, keep, keep, 1.0), 0, _stamp_mul)


func _process(delta: float) -> void:
	# follow the local camera target (rig) or the first player
	var target := Vector2.INF
	var rig := CameraRig.active()
	if rig != null:
		target = Vector2(rig.global_position.x, rig.global_position.z)
	elif get_viewport() != null and get_viewport().get_camera_3d() != null:
		var cam := get_viewport().get_camera_3d()
		var t := cam.global_position + (-cam.global_basis.z) * 12.0
		target = Vector2(t.x, t.z)
	if target != Vector2.INF:
		var center := rect.get_center()
		if absf(target.x - center.x) > RECENTER_DIST or absf(target.y - center.y) > RECENTER_DIST:
			recenter(target)
	_decay_t += delta
	if _decay_t >= DECAY_INTERVAL:
		_decay_t -= DECAY_INTERVAL
		var blizzard := WorldState.instance != null and WorldState.weather_now() == &"blizzard"
		_decay(DECAY_KEEP_BLIZZARD if blizzard else DECAY_KEEP)
		if blizzard and backend == "cpu":
			clear()
	if backend == "cpu" and _dirty:
		(texture as ImageTexture).update(_image)
		_dirty = false
