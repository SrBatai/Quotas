class_name CameraRig
extends Node3D
## Top-level follow rig: Pivot (yaw) → Pitch → Camera3D. Yaw in 45° steps, zoom 16–38 m, shake.
## W0: per-region camera profiles (CameraProfile / CameraZone, scripts/world/city/): the pitch and the far plane
## blend toward the active profile and the zoom is clamped to its range (city districts: −43°, up to 44 m; roofs:
## −40°, up to 50 m). Outside every zone the `default` profile is the G1 camera, unchanged.

signal profile_changed(id: StringName)

static var _active: CameraRig

@onready var pivot: Node3D = $Pivot
@onready var pitch: Node3D = $Pivot/Pitch
@onready var camera: Camera3D = $Pivot/Pitch/Camera3D

var player: Node3D
var yaw_index: int = 0
var dist: float = Balance.CAMERA_DIST
var _shake: float = 0.0
var _shake_time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _yaw_tween: Tween
var _zoom_tween: Tween
var _snapped: bool = false
## Active camera profile and the blended pitch (degrees).
var profile: CameraProfile = CameraProfile.preset(&"default")
var pitch_deg: float = Balance.CAMERA_PITCH_DEG
## Tests / bench / miradores: force a profile id (&"" = follow the CameraZones).
var profile_override: StringName = &""
var _zone_t: float = 0.0
## M5 (GDD §3.1): lean toward the cursor with a firearm in hand (FirearmClient sets it: ≤ 3 m, rifle 6 m), eased at 6/s.
var lean: Vector3 = Vector3.ZERO
var _lean_cur: Vector3 = Vector3.ZERO


static func active() -> CameraRig:
	if is_instance_valid(_active):
		return _active
	return null


func _ready() -> void:
	top_level = true
	player = get_parent() as Node3D
	# Only the local player's rig drives the viewport (remote players and the server strip this node anyway).
	if player != null and player.get("is_local") != null and not bool(player.get("is_local")):
		set_process(false)
		set_process_unhandled_input(false)
		return
	_active = self
	pivot.rotation_degrees.y = Balance.CAMERA_YAW_DEG
	pitch.rotation_degrees.x = Balance.CAMERA_PITCH_DEG
	camera.fov = Balance.CAMERA_FOV
	camera.position = Vector3(0, 0, dist)
	camera.near = 0.3
	camera.far = Balance.CAMERA_FAR
	camera.current = true
	Events.camera_shake.connect(shake)
	if player != null:
		global_position = player.global_position


func snap_to_player() -> void:
	if player != null:
		global_position = player.global_position
		_snapped = true


func _process(delta: float) -> void:
	if player == null:
		return
	var move_dir: Vector3 = player.get("move_dir") if player.get("move_dir") != null else Vector3.ZERO
	var forward := Vector3(0, 0, -1).rotated(Vector3.UP, pivot.rotation.y)
	var forward_offset := 0.0 if bool(player.get("in_house")) else Balance.CAMERA_FORWARD_OFFSET
	_lean_cur = _lean_cur.lerp(lean, 1.0 - exp(-Balance.CAMERA_FOLLOW * delta))
	var target := player.global_position + move_dir * Balance.CAMERA_LOOKAHEAD + forward * forward_offset + _lean_cur
	if not _snapped:
		global_position = target
		_snapped = true
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-Balance.CAMERA_FOLLOW * delta))
	_update_profile(delta)
	if _shake_time > 0.0:
		_shake_time -= delta
		var s := _shake * clampf(_shake_time / 0.3, 0.0, 1.0)
		camera.position = Vector3(_rng.randf_range(-s, s), _rng.randf_range(-s, s), dist)
	else:
		camera.position = Vector3(0, 0, dist)


func _unhandled_input(event: InputEvent) -> void:
	if player != null and bool(player.get("dead")):
		return
	if event.is_action_pressed("rotate_cam_left"):
		rotate_step(1)
	elif event.is_action_pressed("rotate_cam_right"):
		rotate_step(-1)
	elif event.is_action_pressed("zoom_in"):
		set_dist(dist - 2.0)
	elif event.is_action_pressed("zoom_out"):
		set_dist(dist + 2.0)


func rotate_step(direction: int) -> void:
	yaw_index += direction
	var target_yaw := Balance.CAMERA_YAW_DEG + float(yaw_index) * Balance.CAMERA_YAW_STEP
	if _yaw_tween != null and _yaw_tween.is_valid():
		_yaw_tween.kill()
	_yaw_tween = create_tween()
	_yaw_tween.tween_property(pivot, "rotation_degrees:y", target_yaw, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_yaw_tween.tween_callback(func() -> void: Events.camera_yaw_changed.emit(target_yaw))
	Events.camera_yaw_changed.emit(target_yaw)


func set_dist(value: float) -> void:
	dist = clampf(value, profile.dist_min, profile.dist_max)
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(camera, "position:z", dist, 0.2)


func get_yaw() -> float:
	return pivot.rotation.y


## Picks the profile (override, else the CameraZone under the player) every 0.25 s and blends toward it.
func _update_profile(delta: float) -> void:
	_zone_t -= delta
	if _zone_t <= 0.0:
		_zone_t = 0.25
		var want := profile_override
		if want == &"" and is_inside_tree():
			want = CameraZone.pick(get_tree(), player.global_position)
		if want != profile.id:
			set_profile(want)
	var k := 1.0 - exp(-delta / CameraProfile.BLEND_TAU)
	pitch_deg = lerpf(pitch_deg, profile.pitch_deg, k)
	pitch.rotation_degrees.x = pitch_deg
	camera.far = lerpf(camera.far, profile.far, k)


## Switches profile (blended). The zoom is clamped into the new range.
func set_profile(id: StringName) -> void:
	profile = CameraProfile.preset(id)
	if dist < profile.dist_min or dist > profile.dist_max:
		set_dist(dist)
	if CityCut.instance != null:
		CityCut.instance.props_capsule = profile.props_capsule
	profile_changed.emit(profile.id)


## Jumps to the active profile's pitch / far at once (teleports, screenshots).
func snap_profile() -> void:
	if profile_override != &"" and profile_override != profile.id:
		set_profile(profile_override)
	pitch_deg = profile.pitch_deg
	pitch.rotation_degrees.x = pitch_deg
	camera.far = profile.far


func shake(strength: float) -> void:
	_shake = maxf(_shake if _shake_time > 0.0 else 0.0, strength)
	_shake_time = 0.3
