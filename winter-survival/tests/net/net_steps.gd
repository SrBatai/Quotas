extends RefCounted
## Net test body (loaded at runtime by tests/net/net_smoke.gd). Scenarios:
##   basic     4 clients walk patterns, see each other move, chat, request_hit_player (blocked with friendly_fire=off),
##             client A disconnects and reconnects inside the 60 s grace and gets its position back; downstream ≤ 5 kB/s.
##   idle      join and stand still (screenshot proof of remote players).
## Server: soak with the main scene; prints "alive" lines every 5 s; "SERVER RESULT" at quit (admin save-and-quit).

var tree: SceneTree
var opts: Dictionary = {}
var is_server: bool = false
var client_name: String = "?"
var scenario: String = "basic"
var duration: float = 60.0
var tag: String = "[?]"

var _t0: int = 0
var _last_report: float = 0.0
var _phys0: int = 0
var _frames: int = 0
var _server_ok: bool = true
# client observations
var _connect_time: float = -1.0
var _remote_first: Dictionary = {}     # name -> first seen position
var _remote_moved: Dictionary = {}     # name -> true once it moved > 1 m
var _remote_spawned: int = 0
var _remote_despawned: int = 0
var _chat_from_others: int = 0
var _hit_blocked: int = 0
var _hit_sent: int = 0
var _step: int = 0
var _pos_before_dc: Vector3 = Vector3.INF
var _reconnect_ok: bool = false
var _reconnect_tried: bool = false
var _bw_samples: Array[float] = []
var _bw_max: float = 0.0
var _rtt_max: float = 0.0
var _joins: int = 0
var _local_seen: bool = false


func _log(msg: String) -> void:
	print("%s t=%6.2f %s" % [tag, (Time.get_ticks_msec() - _t0) / 1000.0, msg])


func run(p_tree: SceneTree, p_opts: Dictionary) -> void:
	tree = p_tree
	opts = p_opts
	is_server = bool(opts["server"])
	client_name = str(opts["name"])
	scenario = str(opts["scenario"])
	duration = float(opts["duration"])
	_t0 = Time.get_ticks_msec()
	if is_server:
		tag = "[SERVER]"
		_run_server()
	else:
		tag = "[CLIENT %s]" % client_name
		_run_client()


# ------------------------------------------------------------------ server (Net autoload already listening)
func _run_server() -> void:
	if Net.role != Net.Role.SERVER:
		_log("FAIL: Net did not start the server (role=%d) %s" % [Net.role, Net.last_error])
		tree.quit(2)
		return
	tree.process_frame.connect(func() -> void: _frames += 1)
	Net.server_ready.connect(func() -> void: _log("world ready; accepting connections"))
	_phys0 = Engine.get_physics_frames()
	while true:
		await tree.create_timer(5.0).timeout
		var t := (Time.get_ticks_msec() - _t0) / 1000.0
		var ticks := Engine.get_physics_frames() - _phys0
		var pos := []
		var world := tree.get_first_node_in_group("world")
		if world != null:
			for p in world.get_node("Players").get_children():
				pos.append("%s@%s%s" % [p.name, p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), "(dc)" if p.disconnected else ""])
		_log("alive wall=%.1fs frames=%d physics_ticks=%d (expected~%d) peers=%d net: out=%.1f kB/s in=%.1f kB/s players=%s" % [
			t, _frames, ticks, int(t * 60), Net.stats["peers"], float(Net.stats["out_kbps"]), float(Net.stats["in_kbps"]), pos])
		if duration > 0.0 and t >= duration:
			_log("server duration reached, quitting")
			tree.quit(0)
			return


func on_finalize() -> void:
	if not is_server:
		return
	var t := (Time.get_ticks_msec() - _t0) / 1000.0
	var ticks := Engine.get_physics_frames() - _phys0
	var expected := t * 60.0
	var ok := t >= 5.0 and ticks >= expected * 0.9 and ticks <= expected * 1.1
	print("[SERVER] SERVER RESULT %s: wall=%.1fs physics_ticks=%d expected~%d frames=%d" % ["OK" if ok else "FAIL", t, ticks, int(expected), _frames])


# ------------------------------------------------------------------ client
func _run_client() -> void:
	Identity.player_name = client_name
	tree.process_frame.connect(_client_frame)
	Events.chat_message.connect(func(who: String, _text: String) -> void:
		if who != client_name and who != "SERVIDOR":
			_chat_from_others += 1)
	Events.hit_result.connect(func(_v: int, blocked: bool, reason: String) -> void:
		if blocked and reason == "friendly_fire":
			_hit_blocked += 1)
	Events.local_player_ready.connect(func(p: Node) -> void:
		_joins += 1
		_connect_time = (Time.get_ticks_msec() - _t0) / 1000.0
		_local_seen = true
		_log("local player ready: node=%s peer=%d role=%d pos=%s (join #%d)" % [p.name, Net.local_peer_id(), Net.role, p.global_position.snapped(Vector3(0.01, 0.01, 0.01)), _joins])
		if _joins == 2 and _pos_before_dc != Vector3.INF:
			var d: float = (p.global_position - _pos_before_dc).length()
			_reconnect_ok = d < 1.0
			_log("reconnect: position before dc %s, after %s, delta=%.2f m -> %s" % [_pos_before_dc.snapped(Vector3(0.01, 0.01, 0.01)), p.global_position.snapped(Vector3(0.01, 0.01, 0.01)), d, "OK" if _reconnect_ok else "FAIL"]))
	_join()


func _join() -> void:
	_log("joining %s:%d" % [opts["host"], int(opts["port"])])
	GameFlow.join(str(opts["host"]), int(opts["port"]), str(opts["password"]))


func _spawner() -> MultiplayerSpawner:
	var scene := tree.current_scene
	return scene.get_node_or_null("PlayerSpawner") if scene != null else null


var _spawner_wired: bool = false


func _client_frame() -> void:
	_frames += 1
	var t := (Time.get_ticks_msec() - _t0) / 1000.0
	var sp := _spawner()
	if sp != null and not _spawner_wired:
		_spawner_wired = true
		sp.spawned.connect(func(n: Node) -> void:
			_remote_spawned += 1
			_log("spawned %s at %s" % [n.name, n.net_position.snapped(Vector3(0.1, 0.1, 0.1))]))
		sp.despawned.connect(func(n: Node) -> void:
			_remote_despawned += 1
			_log("despawned %s" % n.name))
	if sp == null:
		_spawner_wired = false
	var lp: Player = GameFlow.local_player()
	if lp == null or not lp.is_inside_tree():
		if t > 40.0 and not _local_seen:
			_log("RESULT FAIL name=%s reason=never_connected last_error=%s" % [client_name, Net.last_error])
			tree.quit(3)
		if t >= duration and _local_seen:
			_finish(lp)
		return
	var ct := t - _connect_time
	# scripted movement (world-space) per client
	var mv := Vector2.ZERO
	var run := false
	if scenario == "basic":
		match client_name:
			"A":
				if ct > 1.0 and ct <= 5.0: mv = Vector2(1, 0)
				elif ct > 5.0 and ct <= 8.0: mv = Vector2(-1, 0); run = true
			"B":
				if ct > 1.0 and ct <= 4.0: mv = Vector2(0, 1)
				elif ct > 12.0 and ct <= 15.0: mv = Vector2(0, -1)
			"C":
				if ct > 2.0 and ct <= 6.0: mv = Vector2(-1, 0)
				elif ct > 14.0 and ct <= 17.0: mv = Vector2(1, 0)
			_:
				if ct > 1.5 and ct <= 4.5: mv = Vector2(0, -1)
				elif ct > 13.0 and ct <= 16.0: mv = Vector2(0, 1)
	lp.input.scripted_move = mv
	lp.input.scripted_run = run
	lp.input.scripted_aim = lp.global_position + Vector3(cos(ct), 1.2, sin(ct)) * 5.0
	# observe remote players
	var world := tree.get_first_node_in_group("world")
	if world != null:
		for p in world.get_node("Players").get_children():
			if p == lp or not (p is Player):
				continue
			var nm := String(p.name)
			if not _remote_first.has(nm):
				_remote_first[nm] = p.net_position
			elif (p.net_position - (_remote_first[nm] as Vector3)).length() > 1.0:
				_remote_moved[nm] = true
	# bandwidth / rtt samples once connected
	if ct > 2.0:
		var kb := float(Net.stats["in_kbps"])
		_bw_samples.append(kb)
		_bw_max = maxf(_bw_max, kb)
		_rtt_max = maxf(_rtt_max, float(Net.stats["rtt"]))
	# timeline
	if scenario == "basic":
		if _step == 0 and ct > 3.0:
			_step = 1
			Chat.instance.send("hola desde %s" % client_name)
		elif _step == 1 and ct > 6.0:
			var others := []
			if world != null:
				for p in world.get_node("Players").get_children():
					if p != lp:
						others.append(p)
			if not others.is_empty():
				_step = 2
				for p in others:
					_hit_sent += 1
					Net.rpc_server(NetWorld.instance, &"request_hit_player", [(p as Player).peer_id, 10.0])
		elif _step == 2 and ct > 9.0 and client_name == "A" and not _reconnect_tried:
			_reconnect_tried = true
			_step = 3
			_pos_before_dc = lp.global_position
			_log("disconnecting on purpose at %s (grace test)" % _pos_before_dc.snapped(Vector3(0.01, 0.01, 0.01)))
			GameFlow.to_main_menu("test disconnect")
			tree.create_timer(4.0).timeout.connect(_join)
		elif _step == 2 and ct > 9.0:
			_step = 3
	if t >= duration:
		_finish(lp)


func _finish(lp: Player) -> void:
	tree.process_frame.disconnect(_client_frame)
	var expected_remote := int(opts["clients"]) - 1
	var moved := _remote_moved.size()
	var bw_avg := 0.0
	for s in _bw_samples:
		bw_avg += s
	bw_avg = bw_avg / maxf(_bw_samples.size(), 1.0)
	var bw_ok := bw_avg <= 5.0
	var ok := _local_seen and _remote_spawned >= expected_remote and bw_ok
	if scenario == "basic":
		ok = ok and moved >= mini(expected_remote, 1) and _chat_from_others >= 1 and _hit_sent >= 1 and _hit_blocked >= 1
		if client_name == "A":
			ok = ok and _reconnect_ok
	var corr: int = lp.net.corrections if lp != null else -1
	var name_ok := lp != null and lp.name == str(Net.local_peer_id())
	ok = ok and name_ok
	_log("RESULT %s name=%s remote_spawns=%d remote_despawns=%d remote_moved=%d/%d chat_from_others=%d hit_sent=%d hit_blocked=%d reconnect=%s down_kbps_avg=%.2f down_kbps_max=%.2f rtt_max=%.0f corrections=%d node_name_is_peer=%s" % [
		"OK" if ok else "FAIL", client_name, _remote_spawned, _remote_despawned, moved, expected_remote, _chat_from_others,
		_hit_sent, _hit_blocked, str(_reconnect_ok) if client_name == "A" else "n/a", bw_avg, _bw_max, _rtt_max, corr, name_ok])
	tree.quit(0 if ok else 1)
