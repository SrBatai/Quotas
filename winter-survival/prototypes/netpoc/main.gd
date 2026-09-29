extends Node
## Godot 4.7.2 networking PoC. Same script runs as dedicated server or client:
##   godot --headless --path . -- --server --port 7777 --duration 75
##   godot --headless --path . -- --client --port 7777 --name A --duration 10

const VERSION := "0.1.0"
const PASSWORD := "ventisca"
const DOOR_POS := Vector3(1.0, 0.0, 0.0)
const INTEREST_RADIUS := 15.0   # server-side interest management radius for the test
const PLAYER_SCENE := preload("res://player.tscn")

var is_server := false
var port := 7777
var client_name := "?"
var duration := 10.0
var friendly_fire := false   # server config (co-op PvE by default)
var tag := "[?]"

var _names: Dictionary = {}       # peer_id -> display name (server)
var _spawn_index := 0
var _t0_msec := 0
var _last_report := 0.0
var _phys_ticks := 0
var _frames := 0
var _connected := false
var _connect_time := 0.0
var _step := 0
var _rpc_ok_near := false
var _rpc_rejected_far := false
var _chat_ok := false
var _damage_blocked := false
var _spawned_remote := 0
var _despawned_remote := 0
var _remote_moved := false
var _remote_aims := false
var _reentry_synced := false
var _remote_seen: Dictionary = {}   # node name -> {"spawns": n, "last": Vector3, "aim": float}
var _bytes_sent := 0
var _bytes_recv := 0
var _enet: ENetMultiplayerPeer


func _log(msg: String) -> void:
	print("%s t=%6.2f %s" % [tag, (Time.get_ticks_msec() - _t0_msec) / 1000.0, msg])


func _ready() -> void:
	_t0_msec = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--server": is_server = true
			"--client": is_server = false
			"--port": i += 1; port = int(args[i])
			"--name": i += 1; client_name = args[i]
			"--duration": i += 1; duration = float(args[i])
			"--friendly-fire": friendly_fire = true
		i += 1
	Engine.max_fps = 60   # headless loops would otherwise spin at 100 % CPU
	if is_server:
		_start_server()
	else:
		_start_client()


# ------------------------------------------------------------------ server
func _start_server() -> void:
	tag = "[SERVER]"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 4)
	if err != OK:
		push_error("create_server failed: %s" % error_string(err))
		get_tree().quit(2)
		return
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	_enet = peer
	multiplayer.multiplayer_peer = peer
	multiplayer.auth_callback = _server_auth
	multiplayer.auth_timeout = 5.0
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.peer_authentication_failed.connect(func(id: int) -> void: _log("auth FAILED/timeout peer %d" % id))
	_log("listening UDP %d | display=%s | dedicated_server feature=%s | godot=%s | friendly_fire=%s" % [
		port, DisplayServer.get_name(), OS.has_feature("dedicated_server"),
		Engine.get_version_info().string, friendly_fire])


func _server_auth(id: int, data: PackedByteArray) -> void:
	var d: Variant = JSON.parse_string(data.get_string_from_utf8())
	if typeof(d) != TYPE_DICTIONARY or d.get("version", "") != VERSION or d.get("password", "") != PASSWORD:
		_log("auth REJECT peer %d payload=%s" % [id, str(d)])
		multiplayer.disconnect_peer(id)
		return
	_names[id] = str(d.get("name", "peer%d" % id)).substr(0, 24)
	_log("auth OK peer %d name=%s" % [id, _names[id]])
	multiplayer.complete_auth(id)


func _on_peer_connected(id: int) -> void:
	_log("peer_connected %d -> spawning player" % id)
	var p := PLAYER_SCENE.instantiate()
	p.name = str(id)                       # node name == owner peer id
	p.display_name = _names.get(id, "peer%d" % id)
	# Spawn ring 1 m around DOOR_POS (so every client's first interact is in range).
	var ring := [Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(1, 0, 1), Vector3(1, 0, -1)]
	p.net_position = ring[_spawn_index % ring.size()]
	_spawn_index += 1
	# Interest management: a player's state is only streamed to its owner and to peers whose
	# own player is within INTEREST_RADIUS. Spawn/despawn on the clients follows this visibility.
	var sync: MultiplayerSynchronizer = p.get_node("ServerSync")
	sync.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_PHYSICS
	sync.add_visibility_filter(_make_interest_filter(p))
	# NOTE: visibility_changed fires every physics tick for peer 0 (public visibility) when
	# visibility_update_mode is PHYSICS; only log real per-peer transitions.
	var last_vis: Dictionary = {}
	sync.visibility_changed.connect(func(for_peer: int) -> void:
		if for_peer == 0:
			return
		var v := sync.get_visibility_for(for_peer)
		if last_vis.get(for_peer, null) != v:
			last_vis[for_peer] = v
			_log("visibility of %s for peer %d -> %s" % [p.name, for_peer, v]))
	$World/Players.add_child(p, true)      # MultiplayerSpawner replicates this to all peers


func _make_interest_filter(p: Node) -> Callable:
	return func(for_peer: int) -> bool:
		if for_peer == str(p.name).to_int():
			return true
		var other := $World/Players.get_node_or_null(str(for_peer))
		return other != null and other.net_position.distance_to(p.net_position) < INTEREST_RADIUS


func _on_peer_disconnected(id: int) -> void:
	_log("peer_disconnected %d" % id)
	var p := $World/Players.get_node_or_null(str(id))
	if p:
		p.queue_free()                     # replicated despawn


# ------------------------------------------------------------------ client
func _start_client() -> void:
	tag = "[CLIENT %s]" % client_name
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client("127.0.0.1", port)
	if err != OK:
		push_error("create_client failed: %s" % error_string(err))
		get_tree().quit(2)
		return
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	_enet = peer
	multiplayer.multiplayer_peer = peer
	multiplayer.auth_callback = func(_id: int, _data: PackedByteArray) -> void: pass
	multiplayer.peer_authenticating.connect(func(id: int) -> void:
		var payload := {"version": VERSION, "password": PASSWORD, "name": client_name}
		multiplayer.send_auth(id, JSON.stringify(payload).to_utf8_buffer())
		multiplayer.complete_auth(id))
	multiplayer.connected_to_server.connect(func() -> void:
		_connected = true
		_connect_time = (Time.get_ticks_msec() - _t0_msec) / 1000.0
		_log("connected_to_server, my id=%d" % multiplayer.get_unique_id()))
	multiplayer.connection_failed.connect(func() -> void:
		_log("connection_failed"); get_tree().quit(3))
	multiplayer.server_disconnected.connect(func() -> void:
		_log("server_disconnected"); get_tree().quit(3))
	$PlayerSpawner.spawned.connect(func(n: Node) -> void:
		_log("spawned node %s (local=%s) at %s" % [n.name, n.is_local, n.net_position])
		if not n.is_local:
			_spawned_remote += 1
			var rec: Dictionary = _remote_seen.get(n.name, {"spawns": 0})
			rec["spawns"] = rec["spawns"] + 1
			rec["last"] = n.net_position
			rec["aim"] = n.aim_yaw
			_remote_seen[n.name] = rec)
	$PlayerSpawner.despawned.connect(func(n: Node) -> void:
		_log("despawned node %s" % n.name)
		if not n.is_local:
			_despawned_remote += 1)
	_log("connecting to 127.0.0.1:%d" % port)


func _local_player() -> Node:
	return $World/Players.get_node_or_null(str(multiplayer.get_unique_id()))


# ------------------------------------------------------------------ RPCs (identical on both sides)
@rpc("any_peer", "call_remote", "reliable")
func request_interact(target_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var p := $World/Players.get_node_or_null(str(sender))
	if p == null:
		return
	var dist: float = p.net_position.distance_to(DOOR_POS)
	var ok := target_id == "door_1" and dist <= 2.5
	_log("request_interact from %d target=%s dist=%.2f -> %s" % [sender, target_id, dist, "OK" if ok else "REJECT"])
	interact_result.rpc_id(sender, target_id, ok, dist)


@rpc("authority", "call_remote", "reliable")
func interact_result(target_id: String, ok: bool, dist: float) -> void:
	_log("interact_result target=%s ok=%s dist=%.2f" % [target_id, ok, dist])
	if ok:
		_rpc_ok_near = true
	else:
		_rpc_rejected_far = true


@rpc("any_peer", "call_remote", "reliable", 1)      # channel 1: chat never blocks gameplay traffic
func say(text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	broadcast_say.rpc(_names.get(sender, str(sender)), text.substr(0, 200))


@rpc("authority", "call_local", "reliable", 1)
func broadcast_say(who: String, text: String) -> void:
	_log("chat <%s> %s" % [who, text])
	if not multiplayer.is_server() and who != client_name:
		_chat_ok = true


@rpc("any_peer", "call_remote", "reliable")
func request_hit_player(victim_peer: int, dmg: int) -> void:
	# Server-validated player-vs-player damage, gated by the server config (friendly_fire/PvP).
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var blocked := not friendly_fire
	var v := $World/Players.get_node_or_null(str(victim_peer))
	if v != null and not blocked:
		v.hp = maxi(0, v.hp - clampi(dmg, 0, 50))
	_log("request_hit_player from %d on %d dmg=%d -> %s" % [sender, victim_peer, dmg, "BLOCKED (friendly_fire off)" if blocked else "applied"])
	hit_result.rpc_id(sender, victim_peer, blocked)


@rpc("authority", "call_remote", "reliable")
func hit_result(victim_peer: int, blocked: bool) -> void:
	_log("hit_result victim=%d blocked=%s" % [victim_peer, blocked])
	if blocked:
		_damage_blocked = true


# ------------------------------------------------------------------ loop
func _physics_process(_delta: float) -> void:
	_phys_ticks += 1


func _notification(what: int) -> void:
	# Used to check what a headless server receives on SIGTERM/SIGINT (systemd stop).
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST: _log("notification: WM_CLOSE_REQUEST")
		NOTIFICATION_CRASH: _log("notification: CRASH")
		NOTIFICATION_EXIT_TREE: _log("notification: EXIT_TREE (normal quit path)")


func _process(_delta: float) -> void:
	_frames += 1
	var t := (Time.get_ticks_msec() - _t0_msec) / 1000.0
	if is_server:
		if t - _last_report >= 5.0:
			var span := t - _last_report
			_last_report = t
			var sent := _enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
			var recv := _enet.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
			var pos := []
			for p in $World/Players.get_children():
				pos.append("%s@%s" % [p.name, p.net_position.snapped(Vector3(0.1, 0.1, 0.1))])
			_log("alive wall=%.1fs frames=%d physics_ticks=%d (expected~%d) peers=%d net: out=%.1f kB/s in=%.1f kB/s (all peers, ENet payload+headers) players=%s" % [
				t, _frames, _phys_ticks, int(t * 60), multiplayer.get_peers().size(),
				sent / span / 1000.0, recv / span / 1000.0, pos])
		if t >= duration:
			_log("server done, quitting")
			get_tree().quit(0)
		return

	# ---- client scripted timeline ----
	if not _connected:
		if t > 8.0:
			_log("FAIL: never connected"); get_tree().quit(3)
		return
	var lp := _local_player()
	var ct := t - _connect_time
	if lp:
		# Simulated input (headless). A: walks +X for 5 s (20 m) then back; B: walks +Z 2 s (8 m) then stops.
		# Aim yaw sweeps and the cursor world point orbits (isometric mouse-aim replication).
		var dir := Vector2.ZERO
		if client_name == "A":
			if ct > 2.0 and ct <= 7.0: dir = Vector2(1, 0)
			elif ct > 7.0 and ct <= 12.0: dir = Vector2(-1, 0)
		else:
			if ct > 2.0 and ct <= 4.0: dir = Vector2(0, 1)
		lp.input_dir = dir
		lp.input_aim_yaw = sin(ct)
		lp.input_aim_point = lp.position + Vector3(cos(ct), 0, sin(ct)) * 5.0
	# Accumulate observations about remote players every frame (they may despawn later).
	for p in $World/Players.get_children():
		if p == lp:
			continue
		var rec: Dictionary = _remote_seen.get(p.name, {"spawns": 1, "last": p.net_position, "aim": p.aim_yaw})
		var moved: bool = p.net_position.distance_to(rec["last"]) > 0.01
		var aimed: bool = absf(p.aim_yaw - rec["aim"]) > 0.001
		_remote_moved = _remote_moved or p.net_position.length() > 1.0
		_remote_aims = _remote_aims or absf(p.aim_yaw) > 0.05
		if rec["spawns"] >= 2 and (moved or aimed):
			_reentry_synced = true       # state keeps flowing after a visibility re-entry re-spawn
		rec["last"] = p.net_position
		rec["aim"] = p.aim_yaw
		_remote_seen[p.name] = rec
	if _step == 0 and lp and ct > 1.0:
		_step = 1
		request_interact.rpc_id(1, "door_1")          # near the door -> expect OK
		say.rpc_id(1, "hola desde %s" % client_name)
	elif _step == 1 and lp and ct > 1.5:
		_step = 2
		var others := $World/Players.get_children().filter(func(p: Node) -> bool: return p != lp)
		if others.is_empty():
			_step = 1   # wait until a remote player is visible (late joiner)
		else:
			for p in others:
				request_hit_player.rpc_id(1, str(p.name).to_int(), 10)   # expect BLOCKED (PvE)
	elif _step == 2 and lp and ct > 5.0:
		_step = 3
		request_interact.rpc_id(1, "door_1")          # walked away -> expect REJECT
		say.rpc_id(1, "segundo mensaje de %s" % client_name)
	if t >= duration:
		var rtt := _enet.get_peer(1).get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
		for p in $World/Players.get_children():
			if p != lp:
				_log("remote %s (%s) net_pos=%s aim_yaw=%.2f hp=%d" % [p.name, p.display_name, p.net_position.snapped(Vector3(0.01, 0.01, 0.01)), p.aim_yaw, p.hp])
		var ok := _spawned_remote >= 2 and _despawned_remote >= 1 and _reentry_synced and _remote_moved and _remote_aims \
			and _rpc_ok_near and _rpc_rejected_far and _chat_ok and _damage_blocked
		_log("POC RESULT %s: remote_spawns=%d remote_despawns=%d interest_reentry_synced=%s remote_moved=%s remote_aim_synced=%s rpc_near_ok=%s rpc_far_rejected=%s chat_relayed=%s pvp_blocked=%s local_reconcile_max_err=%.3fm snaps=%d rtt=%.0fms" % [
			"OK" if ok else "FAIL", _spawned_remote, _despawned_remote, _reentry_synced, _remote_moved, _remote_aims,
			_rpc_ok_near, _rpc_rejected_far, _chat_ok, _damage_blocked,
			lp.max_reconcile_err if lp else -1.0, lp.snaps if lp else -1, rtt])
		get_tree().quit(0 if ok else 1)
