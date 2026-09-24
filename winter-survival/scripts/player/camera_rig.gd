class_name CameraRig
extends Node3D
## Top-level follow rig: Pivot (yaw) → Pitch → Camera3D. Yaw in 45° steps, zoom 14–30 m, shake.

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


static func active() -> CameraRig:
	if is_instance_valid(_active):
		return _active
	return null


func _ready() -> void:
	top_level = true
	_active = self
	player = get_parent() as Node3D
	pivot.rotation_degrees.y = Balance.CAMERA_YAW_DEG
	pitch.rotation_degrees.x = Balance.CAMERA_PITCH_DEG
	camera.fov = Balance.CAMERA_FOV
	camera.position = Vector3(0, 0, dist)
	camera.near = 0.3
	camera.far = 260.0
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
	var target := player.global_position + move_dir * Balance.CAMERA_LOOKAHEAD + forward * Balance.CAMERA_FORWARD_OFFSET
	if not _snapped:
		global_position = target
		_snapped = true
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-Balance.CAMERA_FOLLOW * delta))
	if _shake_time > 0.0:
		_shake_time -= delta
		var s := _shake * clampf(_shake_time / 0.3, 0.0, 1.0)
		camera.position = Vector3(_rng.randf_range(-s, s), _rng.randf_range(-s, s), dist)
	else:
		camera.position = Vector3(0, 0, dist)


func _unhandled_input(event: InputEvent) -> void:
	if GameState.is_game_over:
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
	dist = clampf(value, Balance.CAMERA_DIST_MIN, Balance.CAMERA_DIST_MAX)
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(camera, "position:z", dist, 0.2)


func get_yaw() -> float:
	return pivot.rotation.y


func shake(strength: float) -> void:
	_shake = maxf(_shake if _shake_time > 0.0 else 0.0, strength)
	_shake_time = 0.3
