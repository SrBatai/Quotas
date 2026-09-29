class_name Mirador
extends Node3D
## Mirador (C0 provisional, C1 definitive; doc 09 §3.7 item 6, PLAN v3.4 «Miradores»): a marked point on a podium
## roof, a hero tower's roof, the Puente de Hierro, the valley's lookout tower and the Repetidor del Pico (C1). Holding V (the `shove` action: C1 gives miradores their own prompt) for HOLD seconds within `radius` of the
## mark, out of combat, hands the view to a mirador camera for DURATION seconds: pitch `pitch` (a low angle, the
## skyline above the frame's centre), FOV `fov`, far `far`, looking `look` degrees from north, the district
## silhouettes on, the «corte urbano» off (CityCut only writes its globals for the gameplay camera) and the fog
## thinned; the player has no control meanwhile. Q / E turn the view in 45° steps; any other key or click, or the
## time running out, gives the gameplay camera back. Client only; nothing is replicated (C1: the mirador reveals
## the map for the group).

const HOLD := 1.0
const DURATION := 6.0
const CANCEL_AFTER := 0.35
const EYE := 1.7
const FOG_SCALE := 0.14
const COMBAT_RANGE := 25.0

static var active_mirador: Mirador

## C1: the view was taken (CityWorld records the map reveal for H5).
signal used(m: Mirador)

var rec: Dictionary = {}
var look_deg: float = 90.0
var pitch_deg: float = -7.0
var fov: float = 46.0
var far: float = 1500.0
var dist: float = 9.0
var radius: float = 2.6
var active: bool = false
## Seconds the view lasts (screenshots / tests hold it longer).
var duration: float = DURATION
var hold: float = 0.0
var elapsed: float = 0.0
var camera: Camera3D
## Tests / screenshots: act as if this node were the local player.
var player_override: Node3D
var _player: Node3D
var _yaw_extra: float = 0.0
var _hinted: bool = false
var _saved: Dictionary = {}


func setup(p_rec: Dictionary) -> void:
	rec = p_rec
	name = "Mirador_%d" % int(rec.get("id", 0))
	look_deg = float(rec.get("look", 90.0))
	pitch_deg = float(rec.get("pitch", -7.0))
	fov = float(rec.get("fov", 46.0))
	far = float(rec.get("far", 1500.0))
	dist = float(rec.get("dist", 9.0))
	radius = CityLots.cm(rec.get("radius", 260))
	add_to_group("mirador")


func _ready() -> void:
	_marker()


## The mark on the roof: a low survey post with an orange band and a snowy base (procedural, 1 draw call).
func _marker() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	CityProcedural.block(st, Vector3(0, 0, 0), Vector3(0.9, 0.12, 0.9), CityProcedural.COL_STONE, CityProcedural.COL_SNOW)
	CityProcedural.block(st, Vector3(0, 0.12, 0), Vector3(0.12, 1.1, 0.12), Color(0.30, 0.31, 0.34), Color(0.30, 0.31, 0.34))
	CityProcedural.block(st, Vector3(0, 0.95, 0), Vector3(0.16, 0.18, 0.16), Color(0.95, 0.52, 0.18), Color(0.95, 0.52, 0.18))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Mark"
	mi.mesh = st.commit()
	mi.mesh.surface_set_material(0, Assets.get_shared_material())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _local_player() -> Node3D:
	if player_override != null:
		return player_override
	return GameFlow.local_player() as Node3D


func in_range(p: Vector3) -> bool:
	var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
	return d <= radius and absf(p.y - global_position.y) < 2.5


func _process(delta: float) -> void:
	if active:
		elapsed += delta
		_place_camera()
		if elapsed >= duration:
			deactivate()
		return
	var lp := _local_player()
	if lp == null or not lp.is_inside_tree():
		return
	var near := in_range(lp.global_position)
	if near and not _hinted:
		_hinted = true
		Events.notify.emit("Mirador: mantén V para otear", 3.0)
	elif not near:
		_hinted = false
	if near and Input.is_action_pressed("shove") and not _in_combat(lp):
		hold += delta
		if hold >= HOLD:
			activate(lp)
	else:
		hold = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not active or elapsed < CANCEL_AFTER:
		return
	if event.is_action_pressed("rotate_cam_left"):
		_yaw_extra += 45.0
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("rotate_cam_right"):
		_yaw_extra -= 45.0
		get_viewport().set_input_as_handled()
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		deactivate()
		get_viewport().set_input_as_handled()


static func _in_combat(p: Node3D) -> bool:
	if ZombieClient.instance == null:
		return false
	for id in ZombieClient.instance.records:
		var z: ZombieClient.ZRec = ZombieClient.instance.records[id]
		if (z.state == ZombieKinds.State.CHASE or z.state == ZombieKinds.State.ATTACK) \
				and Vector2(z.render_pos.x - p.global_position.x, z.render_pos.z - p.global_position.z).length() < COMBAT_RANGE:
			return true
	return false


## Hands the view to the mirador camera (tests call it directly).
func activate(p: Node3D = null) -> void:
	if active:
		return
	_player = p if p != null else _local_player()
	active = true
	active_mirador = self
	elapsed = 0.0
	hold = 0.0
	_yaw_extra = 0.0
	camera = Camera3D.new()
	camera.name = "MiradorCamera"
	camera.top_level = true
	camera.fov = fov
	camera.near = 0.5
	camera.far = far
	add_child(camera)
	_place_camera()
	camera.current = true
	if _player != null and _player.get("input_enabled") != null:
		_saved["input"] = bool(_player.get("input_enabled"))
		_player.set("input_enabled", false)
	var world := World.instance
	if world != null:
		_saved["env_override"] = world.env_override
		world.env_override = true
		var dn := world.get_node_or_null("DayNight") as DayNight
		if dn != null:
			_saved["fog"] = dn.fog_density_scale
			_saved["fog_color"] = dn.fog_color_override
			dn.fog_density_scale = FOG_SCALE
			if dn.city_night > 0.5:
				dn.fog_color_override = CityWorld.NIGHT_FOG
	if CityWorld.instance != null:
		CityWorld.instance.set_skyline(true)
	used.emit(self)


func deactivate() -> void:
	if not active:
		return
	active = false
	if active_mirador == self:
		active_mirador = null
	var rig := CameraRig.active()
	if rig != null and rig.camera != null:
		rig.camera.current = true
	if camera != null:
		camera.queue_free()
		camera = null
	if _player != null and is_instance_valid(_player) and _saved.has("input"):
		_player.set("input_enabled", bool(_saved["input"]))
	var world := World.instance
	if world != null:
		world.env_override = bool(_saved.get("env_override", false))
		var dn := world.get_node_or_null("DayNight") as DayNight
		if dn != null and _saved.has("fog"):
			dn.fog_density_scale = float(_saved["fog"])
			dn.fog_color_override = _saved.get("fog_color", Color(0, 0, 0, 0))
	_saved.clear()
	if CityWorld.instance != null:
		CityWorld.instance.set_skyline(false)


## Camera `dist` metres behind the player's eyes, looking `look` (+ the Q/E turns) degrees from north, `pitch` down.
func _place_camera() -> void:
	if camera == null:
		return
	var eye := (_player.global_position if _player != null and is_instance_valid(_player) else global_position) + Vector3(0, EYE, 0)
	var a := deg_to_rad(look_deg + _yaw_extra)
	var fwd := Vector3(sin(a), 0.0, -cos(a))
	camera.global_position = eye - fwd * dist + Vector3(0, dist * 0.35, 0)
	var dir := fwd.rotated(fwd.cross(Vector3.UP).normalized(), deg_to_rad(pitch_deg))
	camera.look_at(camera.global_position + dir, Vector3.UP)
