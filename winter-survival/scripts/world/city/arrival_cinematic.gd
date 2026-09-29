class_name ArrivalCinematic
extends Node3D
## Arrival cinematic of Altavega (C1; PLAN v3.4 item 5: «Cinemática de 6–8 s, saltable, la primera vez que se cruza el
## Puente de Hierro; nunca en combate»). Client with a display only; nothing is replicated. The first time the local
## player walks (or drives) east onto the Puente de Hierro, out of combat, a camera of its own takes the view for
## DURATION seconds: it starts low behind the player looking along the truss, rises over the river and turns to Las
## Torres, the district silhouettes on (the skyline beyond the streamed ring) and the fog thinned — then hands the
## view back. Any key or click after SKIP_AFTER skips it. «Seen» is remembered per install (user://c1_seen.cfg),
## so it plays once.

const DURATION := 7.0
const SKIP_AFTER := 0.5
const FOG_SCALE := 0.18
const SEEN_PATH := "user://c1_seen.cfg"
## Trigger: the west half of the bridge deck, moving east.
const TRIGGER := Rect2(2300.0, -400.0, 140.0, 32.0)
## Camera keys (world): [position, look-at] — from behind the player on the west ramp to high over the river facing
## Las Torres (Torre Albo, the Meridiano, LT-01) and the ensanche beyond.
const KEYS := [
	[Vector3(2372.0, 9.0, -380.0), Vector3(2640.0, 22.0, -404.0)],
	[Vector3(2412.0, 16.0, -366.0), Vector3(2660.0, 45.0, -410.0)],
	[Vector3(2458.0, 34.0, -350.0), Vector3(2690.0, 62.0, -400.0)],
	[Vector3(2500.0, 58.0, -330.0), Vector3(2720.0, 48.0, -420.0)],
]

var city: CityWorld
var active: bool = false
var elapsed: float = 0.0
var camera: Camera3D
## Tests: count of plays, and a way to force it regardless of the seen flag.
var plays: int = 0
var force: bool = false
var _seen: bool = false
var _player: Node3D
var _saved: Dictionary = {}


func setup(p_city: CityWorld) -> void:
	city = p_city
	var cfg := ConfigFile.new()
	if cfg.load(SEEN_PATH) == OK:
		_seen = bool(cfg.get_value("c1", "arrival", false))


func seen() -> bool:
	return _seen


func _process(delta: float) -> void:
	if active:
		elapsed += delta
		_place(clampf(elapsed / DURATION, 0.0, 1.0))
		if elapsed >= DURATION:
			finish()
		return
	if _seen and not force:
		return
	var lp := GameFlow.local_player() as Node3D
	if lp == null or not lp.is_inside_tree() or Mirador.active_mirador != null:
		return
	var p := lp.global_position
	if not TRIGGER.has_point(Vector2(p.x, p.z)):
		return
	var v: Variant = lp.get("velocity")
	var east := v is Vector3 and (v as Vector3).x > 0.5
	if not east and not force:
		return
	if Mirador._in_combat(lp):
		return
	play(lp)


## Starts the cinematic (tests call it directly).
func play(p: Node3D = null) -> void:
	if active:
		return
	_player = p if p != null else GameFlow.local_player() as Node3D
	active = true
	plays += 1
	elapsed = 0.0
	camera = Camera3D.new()
	camera.name = "ArrivalCamera"
	camera.top_level = true
	camera.fov = 52.0
	camera.near = 0.5
	camera.far = 1800.0
	add_child(camera)
	_place(0.0)
	camera.current = true
	if _player != null and _player.get("input_enabled") != null:
		_saved["input"] = bool(_player.get("input_enabled"))
		_player.set("input_enabled", false)
	var world := World.instance
	if world != null:
		_saved["env_override"] = world.env_override
		var dn := world.get_node_or_null("DayNight") as DayNight
		if dn != null:
			_saved["fog"] = dn.fog_density_scale
			dn.fog_density_scale = FOG_SCALE
	if city != null:
		city.set_skyline(true)
	_mark_seen()


func finish() -> void:
	if not active:
		return
	active = false
	var rig := CameraRig.active()
	if rig != null and rig.camera != null:
		rig.camera.current = true
		rig.snap_to_player()
	if camera != null:
		camera.queue_free()
		camera = null
	if _player != null and is_instance_valid(_player) and _saved.has("input"):
		_player.set("input_enabled", bool(_saved["input"]))
	var world := World.instance
	if world != null:
		var dn := world.get_node_or_null("DayNight") as DayNight
		if dn != null and _saved.has("fog"):
			dn.fog_density_scale = float(_saved["fog"])
	_saved.clear()
	if city != null and Mirador.active_mirador == null:
		city.set_skyline(false)


func _unhandled_input(event: InputEvent) -> void:
	if not active or elapsed < SKIP_AFTER:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		finish()
		get_viewport().set_input_as_handled()


## Camera at t ∈ [0, 1] along the keys (Catmull-Rom, eased at both ends).
func _place(t: float) -> void:
	if camera == null:
		return
	var e := t * t * (3.0 - 2.0 * t)
	var n := KEYS.size() - 1
	var f := e * float(n)
	var i := clampi(int(floor(f)), 0, n - 1)
	var u := f - float(i)
	var pos := _cr(i, u, 0)
	var look := _cr(i, u, 1)
	camera.global_position = pos
	camera.look_at(look, Vector3.UP)


func _cr(i: int, u: float, k: int) -> Vector3:
	var n := KEYS.size()
	var p0: Vector3 = KEYS[maxi(i - 1, 0)][k]
	var p1: Vector3 = KEYS[i][k]
	var p2: Vector3 = KEYS[mini(i + 1, n - 1)][k]
	var p3: Vector3 = KEYS[mini(i + 2, n - 1)][k]
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)


func _mark_seen() -> void:
	_seen = true
	var cfg := ConfigFile.new()
	cfg.load(SEEN_PATH)
	cfg.set_value("c1", "arrival", true)
	cfg.save(SEEN_PATH)
