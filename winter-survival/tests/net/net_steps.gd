extends RefCounted
## Net test body (loaded at runtime by tests/net/net_smoke.gd). Scenarios:
##   basic         4 clients walk patterns, see each other move, chat, request_hit_player (blocked with friendly_fire=off),
##                 client A disconnects and reconnects inside the 60 s grace and gets its position back; downstream ≤ 5 kB/s.
##   shared_world  (PLAN M2 acceptance, 3 clients) A chops the pine nearest to the spawn → B sees the stump and only A
##                 gets the wood; A opens the cabinet, B is told "en uso"; A crafts a torch and places a campfire that
##                 B sees; C joins late (22 s) and receives the chunk deltas (felled tree, campfire, cabinet state).
##                 The test server enables the /kit and /tp chat commands (server.cfg `debug_commands=true`).
##   idle          join and stand still (screenshot proof of remote players).
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
# shared_world observations
var _sw: Dictionary = {}
var _notifies: Array[String] = []
var _storage_opened: int = 0
var _late: float = 0.0
var _target_tree_wid: int = 0
var _target_tree_pos: Vector3 = Vector3.ZERO
var _wood_before: int = -1
var _timeline: Array = []   # [[ct, Callable], ...] executed once when ct passes


func _log(msg: String) -> void:
	print("%s t=%6.2f %s" % [tag, (Time.get_ticks_msec() - _t0) / 1000.0, msg])


func run(p_tree: SceneTree, p_opts: Dictionary) -> void:
	tree = p_tree
	opts = p_opts
	is_server = bool(opts["server"])
	client_name = str(opts["name"])
	scenario = str(opts["scenario"])
	duration = float(opts["duration"])
	_late = float(opts.get("late", 0.0))
	# _initialize runs before the autoloads enter the tree: wait one frame so Net/GameFlow are ready
	await tree.process_frame
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
	await tree.process_frame
	if tree.current_scene == null:
		Net.load_game_scene()   # -s mode: no main scene; the boot scene does this in the real build
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
		var chunks := NetWorld.instance.chunk_keys().size() if NetWorld.instance != null else 0
		_log("alive wall=%.1fs frames=%d physics_ticks=%d (expected~%d) peers=%d net: out=%.1f kB/s in=%.1f kB/s chunks=%d players=%s" % [
			t, _frames, ticks, int(t * 60), Net.stats["peers"], float(Net.stats["out_kbps"]), float(Net.stats["in_kbps"]), chunks, pos])
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
	Events.notify.connect(func(text: String, _s: float) -> void:
		_notifies.append(text)
		if scenario == "shared_world":
			_log("toast: %s" % text))
	Events.storage_opened.connect(func(_st: Node) -> void: _storage_opened += 1)
	Events.local_player_ready.connect(func(p: Node) -> void:
		_joins += 1
		_connect_time = (Time.get_ticks_msec() - _t0) / 1000.0
		_local_seen = true
		_log("local player ready: node=%s peer=%d role=%d pos=%s outfit=%d (join #%d)" % [p.name, Net.local_peer_id(), Net.role, p.global_position.snapped(Vector3(0.01, 0.01, 0.01)), p.get("outfit"), _joins])
		if _joins == 2 and _pos_before_dc != Vector3.INF:
			var d: float = (p.global_position - _pos_before_dc).length()
			_reconnect_ok = d < 1.0
			_log("reconnect: position before dc %s, after %s, delta=%.2f m -> %s" % [_pos_before_dc.snapped(Vector3(0.01, 0.01, 0.01)), p.global_position.snapped(Vector3(0.01, 0.01, 0.01)), d, "OK" if _reconnect_ok else "FAIL"]))
	if scenario == "shared_world":
		_build_shared_world_timeline()
	if _late > 0.0:
		_log("late joiner: waiting %.0f s" % _late)
		tree.create_timer(_late).timeout.connect(_join)
	else:
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
			_log("spawned %s at %s outfit=%d" % [n.name, n.net_position.snapped(Vector3(0.1, 0.1, 0.1)), n.get("outfit")]))
		sp.despawned.connect(func(n: Node) -> void:
			_remote_despawned += 1
			_log("despawned %s" % n.name))
	if sp == null:
		_spawner_wired = false
	var lp: Player = GameFlow.local_player()
	if lp == null or not lp.is_inside_tree():
		if t > 40.0 + _late and not _local_seen:
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
	elif scenario == "shared_world" and client_name == "C" and ct > 2.0 and ct <= 4.0:
		mv = Vector2(0, 1)   # the late joiner walks a little too (remote_moved for the others)
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
	elif scenario == "shared_world":
		while not _timeline.is_empty() and ct >= float(_timeline[0][0]):
			var entry: Array = _timeline.pop_front()
			(entry[1] as Callable).call(lp, world)
	if t >= duration:
		_finish(lp)


# ------------------------------------------------------------------ shared_world helpers
func _cabinet(world: Node) -> Node:
	return world.get_node_or_null("Cabin/Cabinet") if world != null else null


## The pine closest to the porch spawn (deterministic scatter: the same node on every peer).
func _pick_target_tree(world: Node) -> void:
	if _target_tree_wid != 0:
		return
	var spawn: Vector3 = world.get_spawn_point()
	var best := INF
	for t in tree.get_nodes_in_group("tree"):
		if not String(t.variant).begins_with("pine"):
			continue
		var d: float = t.global_position.distance_to(spawn)
		if d < best:
			best = d
			_target_tree_wid = WorldRegistry.wid_of(t)
			_target_tree_pos = t.global_position
	_log("target tree wid=%d at %s (%.1f m from the spawn)" % [_target_tree_wid, _target_tree_pos.snapped(Vector3(0.1, 0.1, 0.1)), best])


func _tp(pos: Vector3) -> void:
	Chat.instance.send("/tp %.2f %.2f" % [pos.x, pos.z])


func _player_named(world: Node, pname: String) -> Player:
	for p in world.get_node("Players").get_children():
		if p is Player and (p as Player).display_name == pname:
			return p
	return null


func _stump_near(world: Node, pos: Vector3) -> bool:
	for c in world.get_node("Scatter").get_children():
		if String(c.name).begins_with("stump_of_") and c.global_position.distance_to(pos) < 0.5:
			return true
	return false


func _campfire_seen() -> bool:
	for c in tree.get_nodes_in_group("campfire"):
		if c.get_parent() != null and c.get_parent().name == "Placed" and bool(c.get("is_lit")):
			return true
	return false


func _build_shared_world_timeline() -> void:
	var tl := []
	match client_name:
		"A":
			tl = [
				[1.0, func(_lp: Player, world: Node) -> void:
					_pick_target_tree(world)
					Chat.instance.send("/kit")],
				[2.0, func(_lp: Player, _world: Node) -> void:
					var dir := (_target_tree_pos - _target_tree_pos.direction_to(Vector3.ZERO) * 0.0)
					var toward := (Vector3.ZERO - _target_tree_pos)
					toward.y = 0.0
					_tp(_target_tree_pos + toward.normalized() * 1.5)],
				[3.5, func(lp: Player, _world: Node) -> void:
					_wood_before = lp.state.count(&"madera")
					_sw["kit"] = lp.state.hand_tool() == &"hacha"
					_log("kit: hand=%s wood=%d stone=%d pos=%s" % [lp.state.hand_tool(), _wood_before, lp.state.count(&"piedra"), lp.global_position.snapped(Vector3(0.1, 0.1, 0.1))])],
				[4.0, func(_lp: Player, _world: Node) -> void: _chop()],
				[4.7, func(_lp: Player, _world: Node) -> void: _chop()],
				[5.4, func(_lp: Player, _world: Node) -> void: _chop()],
				[6.1, func(_lp: Player, _world: Node) -> void: _chop()],
				[7.5, func(lp: Player, world: Node) -> void:
					var d := NetWorld.instance.delta_of(_target_tree_wid)
					_sw["felled"] = bool(d.get("felled", false)) and _stump_near(world, _target_tree_pos)
					_sw["wood"] = lp.state.count(&"madera") == _wood_before + Balance.TREE_WOOD
					_log("after chop: delta=%s wood %d -> %d stump=%s" % [d, _wood_before, lp.state.count(&"madera"), _stump_near(world, _target_tree_pos)])],
				[9.0, func(_lp: Player, world: Node) -> void:
					var cab: Node3D = _cabinet(world)
					_tp(cab.global_position + cab.global_basis.z * 0.9)],
				[10.5, func(lp: Player, world: Node) -> void:
					lp.interactor.send_interact(InteractableComponent.find_from(_cabinet(world)), &"open")],
				[12.0, func(_lp: Player, world: Node) -> void:
					var st: Storage = _cabinet(world).get_node("Storage")
					_sw["cabinet"] = _storage_opened >= 1 and st.is_open and st.open_by == Net.local_peer_id()
					_log("cabinet open_by=%d is_open=%s opened_events=%d" % [st.open_by, st.is_open, _storage_opened])],
				[16.0, func(_lp: Player, world: Node) -> void:
					Net.rpc_server(NetWorld.instance, &"request_close_storage", [WorldRegistry.wid_of(_cabinet(world))])],
				[17.0, func(_lp: Player, _world: Node) -> void:
					Net.rpc_server(NetWorld.instance, &"request_craft", [&"antorcha"])],
				[18.0, func(lp: Player, world: Node) -> void:
					_sw["torch"] = lp.state.count(&"antorcha") >= 1
					_log("crafted torch: %d" % lp.state.count(&"antorcha"))
					var sp: Vector3 = world.get_spawn_point()
					_tp(sp + Vector3(2.5, 0, 2.0))],
				[19.5, func(lp: Player, world: Node) -> void:
					# same validation the server runs (rocks and bushes may sit anywhere beyond 9 m): pick a free spot
					var spot := Vector3.INF
					for cand in [Vector3(0, 0, 3.5), Vector3(2.5, 0, 2.5), Vector3(-2.5, 0, 2.5), Vector3(0, 0, -3.5), Vector3(3.5, 0, 0), Vector3(-3.5, 0, 0)]:
						var c: Vector3 = lp.global_position + cand
						c.y = world.get_height(c.x, c.z)
						if PlacementController.check_position(lp, c):
							spot = c
							break
					_log("placing campfire at %s (materials wood=%d stone=%d)" % [spot.snapped(Vector3(0.1, 0.1, 0.1)), lp.state.count(&"madera"), lp.state.count(&"piedra")])
					if spot != Vector3.INF:
						Net.rpc_server(NetWorld.instance, &"request_place", ["campfire", spot, 0.0])],
				[22.0, func(_lp: Player, _world: Node) -> void:
					_sw["campfire"] = _campfire_seen()
					_log("campfire seen: %s" % _campfire_seen())],
			]
		"B":
			tl = [
				[1.0, func(lp: Player, world: Node) -> void:
					_pick_target_tree(world)
					_wood_before = lp.state.count(&"madera")
					var toward := (Vector3.ZERO - _target_tree_pos)
					toward.y = 0.0
					_tp(_target_tree_pos + toward.normalized().rotated(Vector3.UP, 1.2) * 2.5)],
				[8.5, func(lp: Player, world: Node) -> void:
					var d := NetWorld.instance.delta_of(_target_tree_wid)
					_sw["stump"] = bool(d.get("felled", false)) and _stump_near(world, _target_tree_pos) and WorldRegistry.get_object(_target_tree_wid) == null
					_sw["no_wood"] = lp.state.count(&"madera") == _wood_before
					_log("saw felled: delta=%s stump=%s tree_gone=%s my wood=%d" % [d, _stump_near(world, _target_tree_pos), WorldRegistry.get_object(_target_tree_wid) == null, lp.state.count(&"madera")])],
				[11.5, func(_lp: Player, world: Node) -> void:
					var cab: Node3D = _cabinet(world)
					_tp(cab.global_position + cab.global_basis.z * 0.9 + cab.global_basis.x * 0.8)],
				[13.0, func(lp: Player, world: Node) -> void:
					_notifies.clear()
					var comp := InteractableComponent.find_from(_cabinet(world))
					_sw["label"] = comp.get_label(lp) == "Armario en uso" and not comp.can_interact(lp)
					_log("cabinet label for B: '%s' can=%s open_by=%d" % [comp.get_label(lp), comp.can_interact(lp), (_cabinet(world).get_node("Storage") as Storage).open_by])
					lp.interactor.send_interact(comp, &"open")],
				[14.5, func(_lp: Player, world: Node) -> void:
					var st: Storage = _cabinet(world).get_node("Storage")
					var a := _player_named(world, "A")
					_sw["en_uso"] = _notifies.has(NetWorld.REASONS["en_uso"]) and a != null and st.open_by == a.peer_id and _storage_opened == 0
					_log("en uso: notifies=%s open_by=%d A=%d opened_events=%d" % [_notifies, st.open_by, a.peer_id if a != null else -1, _storage_opened])],
				[23.0, func(_lp: Player, _world: Node) -> void:
					_sw["campfire"] = _campfire_seen()
					_log("campfire seen: %s" % _campfire_seen())],
			]
		"C":
			tl = [
				[1.0, func(_lp: Player, world: Node) -> void:
					_pick_target_tree(world)],
				[3.0, func(lp: Player, world: Node) -> void:
					# the felled pine is already gone here: find it through its stump (name = stump_of_<tree>) and
					# the deterministic wid (hash of the node path under World)
					var felled_wid := 0
					var stump_pos := Vector3.INF
					for c in world.get_node("Scatter").get_children():
						if String(c.name).begins_with("stump_of_tree_"):
							felled_wid = ("Scatter/" + String(c.name).trim_prefix("stump_of_")).hash()
							stump_pos = c.global_position
					var d := NetWorld.instance.delta_of(felled_wid)
					var keys := NetWorld.instance.chunk_keys()
					var in_clearing := not keys.is_empty()
					for k in keys:
						var cx := WorldConst.key_cx(k)
						var cz := WorldConst.key_cz(k)
						if cx < 23 or cx > 25 or cz < 23 or cz > 25:
							in_clearing = false
					_sw["deltas"] = NetWorld.instance.snapshots_received >= 1 and in_clearing
					_sw["felled"] = felled_wid != 0 and bool(d.get("felled", false)) and WorldRegistry.get_object(felled_wid) == null and stump_pos.distance_to(_target_tree_pos) < 0.5
					_sw["campfire"] = _campfire_seen()
					var st: Storage = _cabinet(world).get_node("Storage")
					_sw["cabinet_free"] = st.open_by == 0
					_log("late join: snapshots=%d chunks=%s felled wid=%d delta=%s stump at %s (target %s) campfire=%s cabinet open_by=%d wood=%d deltas=%d" % [
						NetWorld.instance.snapshots_received, keys, felled_wid, d, stump_pos, _target_tree_pos, _campfire_seen(), st.open_by, lp.state.count(&"madera"), NetWorld.instance.deltas.size()])],
			]
	tl.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	_timeline = tl


func _chop() -> void:
	Net.rpc_server(NetWorld.instance, &"request_interact", [_target_tree_wid, &"chop", 0])


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
	if scenario == "basic" and expected_remote > 0:
		ok = ok and moved >= 1 and _chat_from_others >= 1 and _hit_sent >= 1 and _hit_blocked >= 1
		if client_name == "A":
			ok = ok and _reconnect_ok
	var corr: int = lp.net.corrections if lp != null else -1
	var name_ok := lp != null and lp.name == str(Net.local_peer_id())
	ok = ok and name_ok
	if scenario == "shared_world":
		var expected_keys := {"A": ["kit", "felled", "wood", "cabinet", "torch", "campfire"],
			"B": ["stump", "no_wood", "label", "en_uso", "campfire"], "C": ["deltas", "felled", "campfire", "cabinet_free"]}
		var sw_ok := true
		for k in expected_keys.get(client_name, []):
			if not bool(_sw.get(k, false)):
				sw_ok = false
		ok = ok and sw_ok and not _timeline.is_empty() == false
		_log("RESULT %s name=%s shared_world=%s remote_spawns=%d remote_moved=%d/%d down_kbps_avg=%.2f down_kbps_max=%.2f rtt_max=%.0f corrections=%d snapshots=%d" % [
			"OK" if ok else "FAIL", client_name, _sw, _remote_spawned, moved, expected_remote, bw_avg, _bw_max, _rtt_max, corr,
			NetWorld.instance.snapshots_received if NetWorld.instance != null else -1])
	else:
		_log("RESULT %s name=%s remote_spawns=%d remote_despawns=%d remote_moved=%d/%d chat_from_others=%d hit_sent=%d hit_blocked=%d reconnect=%s down_kbps_avg=%.2f down_kbps_max=%.2f rtt_max=%.0f corrections=%d node_name_is_peer=%s" % [
			"OK" if ok else "FAIL", client_name, _remote_spawned, _remote_despawned, moved, expected_remote, _chat_from_others,
			_hit_sent, _hit_blocked, str(_reconnect_ok) if client_name == "A" else "n/a", bw_avg, _bw_max, _rtt_max, corr, name_ok])
	tree.quit(0 if ok else 1)
