class_name PlayerInput
extends Node
## Owner client only: reads the input map (or a scripted vector in tests), resolves the camera-relative move
## vector in world space, auto-walk toward a clicked interactable, the mouse aim (cursor world point and the
## yaw the survivor faces) and packs a command dictionary per physics tick (PlayerNet sends it).

var enabled: bool = true
## Tests / headless clients: world-space move override (Vector2.INF = read the input map).
var scripted_move: Vector2 = Vector2.INF
var scripted_run: bool = false
var scripted_aim: Vector3 = Vector3.INF
var auto_target: InteractableComponent
var _auto_timer: float = 0.0
var _face_target: Vector3 = Vector3.INF
var _face_timer: float = 0.0
var _yaw: float = 0.0
var _aim_point: Vector3 = Vector3.ZERO
var _seq: int = 0
@onready var player: Player = get_parent()


func _ready() -> void:
	_yaw = player.aim_yaw


func face_toward(pos: Vector3) -> void:
	_face_target = pos
	_face_timer = 0.6


func _can_move() -> bool:
	return enabled and GameFlow.in_game and not player.dead and not get_tree().paused and not _typing()


func _typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit


func make_cmd() -> Dictionary:
	var dt := 1.0 / float(Balance.NET_TICK)
	var input := Vector2.ZERO
	var can_move := _can_move()
	if can_move:
		if scripted_move != Vector2.INF:
			input = scripted_move
		else:
			input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input != Vector2.ZERO and auto_target != null:
		auto_target = null
		if player.interactor != null:
			player.interactor.pending = null
	var dir := Vector3.ZERO
	if input != Vector2.ZERO:
		if scripted_move != Vector2.INF:
			dir = Vector3(input.x, 0, input.y).limit_length(1.0)
		else:
			var yaw := player.camera_rig.get_yaw() if player.camera_rig != null else 0.0
			dir = Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw).normalized()
	elif auto_target != null:
		if not is_instance_valid(auto_target):
			auto_target = null
		else:
			_auto_timer += dt
			var tp := auto_target.global_position
			var flat := Vector3(tp.x - player.global_position.x, 0, tp.z - player.global_position.z)
			if flat.length() <= auto_target.interact_range * 0.9 or _auto_timer > Balance.AUTO_WALK_TIMEOUT:
				var reached := flat.length() <= auto_target.interact_range
				auto_target = null
				_auto_timer = 0.0
				if player.interactor != null:
					if reached:
						player.interactor.perform_pending()
					else:
						player.interactor.pending = null
			else:
				dir = flat.normalized()
	if auto_target == null:
		_auto_timer = 0.0
	var btn := 0
	var run := can_move and input != Vector2.ZERO and (scripted_run if scripted_move != Vector2.INF else Input.is_action_pressed("run"))
	if run:
		btn |= Packets.BTN_RUN
	if can_move and scripted_move == Vector2.INF and Input.is_action_pressed("crouch"):
		btn |= Packets.BTN_CROUCH
	# facing: movement direction, else the interaction target for a moment, else keep
	var face_dir := dir
	if _face_timer > 0.0:
		_face_timer -= dt
		if _face_target != Vector3.INF:
			var f := _face_target - player.global_position
			f.y = 0.0
			if f.length() > 0.05:
				face_dir = f.normalized()
	if face_dir.length() > 0.01:
		_yaw = atan2(face_dir.x, face_dir.z)   # model front = +Z (Vector3.MODEL_FRONT)
	_aim_point = _cursor_world_point()
	_seq += 1
	return {"seq": _seq, "move": Vector2(dir.x, dir.z), "aim_yaw": _yaw, "aim": _aim_point, "btn": btn, "slot": 0, "flags": 0}


## Cursor projected on the horizontal plane through the survivor's chest (isometric mouse aim).
func _cursor_world_point() -> Vector3:
	if scripted_aim != Vector3.INF:
		return scripted_aim
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or DisplayServer.get_name() == "headless":
		return player.global_position + player.facing() * 3.0
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dirn := cam.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP, player.global_position.y + 1.2)
	var hit: Variant = plane.intersects_ray(from, dirn)
	if hit == null:
		return _aim_point
	return player.global_position + ((hit as Vector3) - player.global_position).limit_length(Balance.NET_MAX_AIM_DIST)


func _unhandled_input(event: InputEvent) -> void:
	if not _can_move():
		return
	if event.is_action_pressed("toggle_torch"):
		Net.rpc_server(NetWorld.instance, &"request_toggle_torch", [])
	elif event.is_action_pressed("eat"):
		Net.rpc_server(NetWorld.instance, &"request_eat_best", [])
