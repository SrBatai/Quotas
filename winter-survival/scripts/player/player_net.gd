class_name PlayerNet
extends Node
## Player networking (ARQ v2 §6.7). Owner client: generates a command every physics tick, predicts with
## PlayerSim, sends 2 commands per packet at 30 Hz with the 2 previous ones repeated (channel 0, unreliable
## ordered) and reconciles against the server's `_state` ack (replay of unacknowledged inputs, 5 cm
## threshold). Server: jitter buffer + authoritative PlayerSim; ack at 30 Hz; owner-only mirror on channel 1.

var owner_peer: int = 1
var corrections: int = 0
var last_error: float = 0.0
var last_ack: int = 0

var _pending: Array[Dictionary] = []   # owner: commands not yet acknowledged (with pos_after)
var _recent: Array[Dictionary] = []    # owner: last commands (redundancy window)
var _queue: Array[Dictionary] = []     # server: received commands (jitter buffer)
var _last_seq: int = 0                 # server: newest sequence accepted
var _last_cmd: Dictionary = {}
var _tick: int = 0
var _idle_cmd: Dictionary = {"seq": 0, "move": Vector2.ZERO, "aim_yaw": 0.0, "aim": Vector3.ZERO, "btn": 0, "slot": 0, "flags": 0}
@onready var body: Player = get_parent()


func _ready() -> void:
	owner_peer = body.peer_id


func pending_count() -> int:
	return _pending.size()


func _physics_process(dt: float) -> void:
	if Net.is_server:
		_server_step(dt)
	elif body.is_local:
		_client_step(dt)


# ------------------------------------------------------------------ server
func _server_step(dt: float) -> void:
	var cmd: Dictionary
	if body.is_local and body.input != null:
		cmd = body.input.make_cmd()           # offline: the owner is this process
	elif _queue.is_empty():
		cmd = _last_cmd if not _last_cmd.is_empty() else _idle_cmd
	else:
		cmd = _queue.pop_front()
		while _queue.size() > Balance.NET_MAX_INPUT_QUEUE:
			_queue.pop_front()
	if body.dead or body.disconnected:
		cmd = cmd.duplicate()
		cmd["move"] = Vector2.ZERO
		cmd["btn"] = int(cmd.get("btn", 0)) & ~(Packets.BTN_RUN)
	PlayerSim.step(body, cmd, dt, body.sim_params())
	body.net_position = body.position
	body.aim_yaw = wrapf(float(cmd.get("aim_yaw", body.aim_yaw)), -PI, PI)
	var aim: Vector3 = cmd.get("aim", body.position)
	body.aim_point = body.position + (aim - body.position).limit_length(Balance.NET_MAX_AIM_DIST)
	var btn := int(cmd.get("btn", 0))
	var move: Vector2 = cmd.get("move", Vector2.ZERO)
	body.running = (btn & Packets.BTN_RUN) != 0 and move != Vector2.ZERO and body.can_run
	body.crouching = (btn & Packets.BTN_CROUCH) != 0
	body.move_dir = Vector3(move.x, 0.0, move.y)
	_last_cmd = cmd
	_tick += 1
	if not body.is_local and _tick % Balance.NET_STATE_EVERY == 0 and multiplayer.get_peers().has(owner_peer):
		# raw packet (no Variant / RPC headers): 23 B at 30 Hz, unreliable ordered on channel 0
		multiplayer.send_bytes(Packets.pack_state(int(cmd.get("seq", 0)), body.position, body.velocity), owner_peer,
			MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 0)
	body.state.flush_mirror()


@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func _inputs(bytes: PackedByteArray) -> void:
	if not multiplayer.is_server() or Net.sender() != owner_peer:
		return
	for cmd in Packets.unpack_cmds(bytes, body.position):
		var seq := int(cmd["seq"])
		if seq <= _last_seq:
			continue   # duplicate (redundancy) or old
		_last_seq = seq
		_queue.append(cmd)
	while _queue.size() > Balance.NET_MAX_INPUT_QUEUE * 2:
		_queue.pop_front()


# ------------------------------------------------------------------ owner client
func _client_step(dt: float) -> void:
	var cmd := body.input.make_cmd()
	cmd["pos"] = body.position
	PlayerSim.step(body, cmd, dt, body.sim_params())
	cmd["pos_after"] = body.position
	cmd["vel_after"] = body.velocity
	_pending.append(cmd)
	while _pending.size() > 180:
		_pending.pop_front()
	_recent.append(cmd)
	while _recent.size() > Balance.NET_SEND_EVERY + Balance.NET_INPUT_REDUNDANCY:
		_recent.pop_front()
	var btn := int(cmd.get("btn", 0))
	var move: Vector2 = cmd["move"]
	body.move_dir = Vector3(move.x, 0.0, move.y)
	body.running = (btn & Packets.BTN_RUN) != 0 and move != Vector2.ZERO and body.can_run
	_tick += 1
	if _tick % Balance.NET_SEND_EVERY == 0:
		_inputs.rpc_id(1, Packets.pack_cmds(_recent))


## Owner: server ack + authoritative pos/vel (raw packet routed by Net.peer_packet).
func on_state_bytes(bytes: PackedByteArray) -> void:
	if Net.is_server or not body.is_local:
		return
	var s := Packets.unpack_state(bytes)
	if s.is_empty():
		return
	var ack := int(s["ack"])
	if ack <= last_ack:
		return
	last_ack = ack
	var predicted := Vector3.INF
	while not _pending.is_empty() and int(_pending[0]["seq"]) <= ack:
		var c: Dictionary = _pending.pop_front()
		if int(c["seq"]) == ack:
			predicted = c["pos_after"]
	if predicted == Vector3.INF:
		return   # ack for a command we no longer hold (e.g. before the first send)
	var err: float = (predicted - (s["pos"] as Vector3)).length()
	last_error = err
	if err > Balance.NET_RECONCILE_THRESHOLD:
		corrections += 1
		body.position = s["pos"]
		body.velocity = s["vel"]
		for c in _pending:
			PlayerSim.step(body, c, 1.0 / Balance.NET_TICK, body.sim_params())
			c["pos_after"] = body.position
			c["vel_after"] = body.velocity


# ------------------------------------------------------------------ owner-only mirror + effects (server → owner)
@rpc("authority", "call_remote", "reliable", 1)
func _mirror(d: Dictionary) -> void:
	if Net.is_server:
		return
	body.state.apply_mirror(d)


@rpc("authority", "call_remote", "reliable", 1)
func _notify(text: String, seconds: float) -> void:
	if Net.is_dedicated:
		return
	Events.notify.emit(text, seconds)


@rpc("authority", "call_remote", "reliable", 1)
func _fx(kind: StringName, value: float) -> void:
	if Net.is_dedicated or not body.is_local:
		return
	match kind:
		&"shake":
			Events.camera_shake.emit(value)
		&"hurt":
			Events.player_damaged.emit(value, &"")
			AudioManager.play(&"player_hurt")
