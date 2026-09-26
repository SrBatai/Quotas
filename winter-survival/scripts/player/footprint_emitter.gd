class_name FootprintEmitter
extends Node
## Stamps a footprint every `step` metres of ground travel for any character the client can see: players
## (local and remote), wolves and deer (PLAN M2 "huellas para todos los personajes"; M3 moves the stamps to
## SnowTrailMap). `visual` gives the yaw; `check_floor` only for locally simulated bodies.

var _body: Node3D
var _visual: Node3D
var _step: float = Balance.FOOTPRINT_STEP
var _size: float = 1.0
var _sound: bool = true
var _check_floor: bool = false
var _acc: float = 0.0
var _last_pos: Vector3 = Vector3.INF
var _left: bool = true


func setup(body: Node3D, visual: Node3D, step: float = Balance.FOOTPRINT_STEP, size: float = 1.0, sound: bool = true) -> void:
	_body = body
	_visual = visual
	_step = step
	_size = size
	_sound = sound
	_check_floor = body is Player and (body as Player).is_local


func _physics_process(_delta: float) -> void:
	if _body == null or not is_instance_valid(_body) or not _body.is_inside_tree():
		return
	if _check_floor and _body is CharacterBody3D and not (_body as CharacterBody3D).is_on_floor():
		_last_pos = _body.global_position
		return
	var p := _body.global_position
	if _last_pos == Vector3.INF:
		_last_pos = p
		return
	var d := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
	_last_pos = p
	if d > 2.0:
		return  # teleport
	_acc += d
	if _acc >= _step:
		_acc = 0.0
		var world := get_tree().get_first_node_in_group("world")
		if world != null and world.get("footprints") != null:
			var yaw: float = _visual.global_rotation.y if _visual != null else 0.0
			var ground := p
			ground.y = world.get_height(p.x, p.z)
			if absf(ground.y - p.y) > 1.0:
				ground.y = p.y - 0.05  # on a porch/floor
			world.footprints.stamp(ground, yaw, _left, _size)
			_left = not _left
		if _sound:
			AudioManager.play(&"footstep_snow", p)
