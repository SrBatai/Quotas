extends "res://tests/net/net_steps.gd"
## H3 net scenario `team` (2–4 clients; PLAN v3.8.1 H3 acceptance): notices and the group across the network, with
## a horde around (the `zombies` context: A fills the surroundings with walkers far enough not to bite).
##   ping     C (B with 2 clients) places a DANGER ping 6 m in front of itself: EVERY client receives it (same id),
##            draws it in the world (WorldLayer.pings_drawn) and hears ui_ping_danger at its point; the others also
##            get the P2 line «C: peligro · N m».
##   downed   B takes /hurt 200 → the server's HudNet pushes the downed state the frame it sees it; A must show the ONE
##            indicator (drawn in the world or on the edge) AND play ui_mate_down within 0.2 s of the server's
##            timestamp (same machine clock), with the P0 in the world (not on the line) and its caption; then A
##            revives B (hold) and the P0 ends.
##   hazard   A asks the debug server for a blizzard WITH its warning: every client's hazard line shows «ventisca ·
##            se acerca · 0:5x» (the countdown comes from the server, 60 s).
## Every client prints RESULT OK / FAIL with its checks; timings in the log.
## Run: NET_TEST_OUT=… tests/net/run_net_test.sh --clients 4 --duration 55 --soak 75 --scenario team --port 8107

const WAIT := 20.0
const DOWN_BUDGET_MS := 200

var _checks: Dictionary = {}
var _info: Dictionary = {}
var _started: bool = false
var _hud: Hud
var _pings_seen: Dictionary = {}     # id -> {peer, kind, pos, t}
var _cue_ms: Dictionary = {}         # event -> unix ms of the first event_played
var _cue_at: Dictionary = {}         # event -> position


func _run_client() -> void:
	super._run_client()
	_timeline = []
	tree.process_frame.connect(_team_frame)
	Events.ping_placed.connect(func(id: int, peer: int, kind: StringName, pos: Vector3, _s: float) -> void:
		if not _pings_seen.has(id):
			_pings_seen[id] = {"peer": peer, "kind": kind, "pos": pos, "t": HudNet.now_ms()}
			_log("ping %d from peer %d (%s) at %s" % [id, peer, kind, pos.snapped(Vector3(0.1, 0.1, 0.1))]))
	AudioManager.event_played.connect(func(e: StringName, _v: Node, at: Vector3) -> void:
		if (e == &"ui_mate_down" or e == &"ui_ping_danger") and not _cue_ms.has(e):
			_cue_ms[e] = HudNet.now_ms()
			_cue_at[e] = at)


func _sleep(s: float) -> void:
	await tree.create_timer(s).timeout


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if bool(cond.call()):
			return true
		await tree.process_frame
		t += tree.root.get_process_delta_time()
	return bool(cond.call())


func _others(world: Node) -> Array:
	var out: Array = []
	var lp := GameFlow.local_player()
	if world == null:
		return out
	for p in world.get_node("Players").get_children():
		if p is Player and p != lp:
			out.append(p)
	return out


func _team_frame() -> void:
	if _started or GameFlow.local_player() == null or _connect_time < 0.0:
		return
	var scene := tree.current_scene
	_hud = scene.get("hud") if scene != null else null
	if _hud == null or HudNet.instance == null:
		return
	_started = true
	_script()


func _script() -> void:
	var n := int(opts["clients"])
	var world := tree.get_first_node_in_group("world")
	# everybody in and synced (each client runs on its own clock: wait for the state, never a fixed time)
	_checks["synced"] = await _until(func() -> bool: return HudNet.instance.synced and _others(world).size() >= n - 1, WAIT + 20.0)
	_log("synced=%s players seen=%d" % [_checks["synced"], _others(world).size() + 1])
	if client_name == "A":
		Chat.instance.send("/director off")
		await _sleep(0.6)
		Chat.instance.send("/zombies 30 walker 70")   # the horde around, far enough not to bite
		await _sleep(0.6)
	var pinger := "C" if n >= 3 else "B"
	await _sleep(3.0)
	# ---------------------------------------------------------------- danger ping, seen by every client
	if client_name == pinger:
		var lp: Player = GameFlow.local_player()
		var cam := tree.root.get_camera_3d()
		var fwd := -cam.global_basis.z if cam != null else Vector3.FORWARD
		fwd.y = 0.0
		var at := lp.global_position + fwd.normalized() * 6.0
		_log("placing a danger ping at %s" % at.snapped(Vector3(0.1, 0.1, 0.1)))
		_hud.pings.place(&"danger", at)
	var got := await _until(func() -> bool: return _danger_id() != 0, WAIT)
	var id := _danger_id()
	# drawn in the world (the pinger stands 6 m from it; the others near the spawn: on screen for all)
	var drawn := await _until(func() -> bool: return _hud.world_layer.pings_drawn.has(id), 4.0)
	var heard: bool = _cue_ms.has(&"ui_ping_danger") and (_cue_at.get(&"ui_ping_danger", Vector3.INF) as Vector3).distance_to((_pings_seen.get(id, {}) as Dictionary).get("pos", Vector3.ZERO)) < 0.05
	_checks["ping_seen"] = got and drawn and heard
	if client_name != pinger:
		var key := "ping:%d" % id
		var lined := func() -> bool:
			var queued := not _hud.router.queue.filter(func(e: Dictionary) -> bool: return str(e["key"]) == key).is_empty()
			return _hud.router.shown_keys.has(key) or str(_hud.router.current.get("key", "")) == key or queued
		_checks["ping_line"] = await _until(lined, 4.0)
	_log("danger ping %d: received=%s drawn=%s heard=%s line=%s (%s)" % [id, got, drawn, heard, _checks.get("ping_line", "n/a"), _hud.banner.text_now()])
	# ---------------------------------------------------------------- hazard: the blizzard warning with its countdown
	if client_name == "A":
		Net.rpc_server(HudNet.instance, &"request_test_warning", [120.0])
	var hz := _hud.hazard
	var warned := await _until(func() -> bool: return hz.stack.state_of(&"blizzard") == &"soon" and hz.stack.left(&"blizzard") > 0.0, WAIT)
	var left := hz.stack.left(&"blizzard")
	var line := " · ".join(hz.line_parts())
	_checks["hazard_countdown"] = warned and left > 40.0 and left <= 60.5 and (line.begins_with("ventisca · se acerca · 0:5") or line == "ventisca · se acerca · 1:00")
	_log("blizzard warning: «%s» (%.1f s left)" % [line, left])
	await _sleep(2.0)
	# ---------------------------------------------------------------- downed: B → A in ≤ 0.2 s
	match client_name:
		"B":
			Chat.instance.send("/hurt 200")
			_checks["down"] = await _until(func() -> bool: return GameFlow.local_player() != null and (GameFlow.local_player() as Player).downed, WAIT)
			var up := func() -> bool:
				var p := GameFlow.local_player() as Player
				return p != null and not p.downed and not p.dead
			_checks["revived"] = await _until(up, WAIT + 10.0)
			_log("B: downed=%s then revived=%s" % [_checks["down"], _checks["revived"]])
		"A":
			await _watch_down(world)
		_:
			var b := _player_named(world, "B")
			var seen := await _until(func() -> bool: return b != null and _hud.team.downed_at.has(b.peer_id), WAIT)
			_log("%s: saw B down=%s" % [client_name, seen])
	await _sleep(1.0)


## A: waits for B's down, measures the indicator and the cue against the server's timestamp, checks the P0, revives.
func _watch_down(world: Node) -> void:
	var b := _player_named(world, "B")
	if b == null:
		_log("A: no B")
		return
	var bp := b.peer_id
	var down := await _until(func() -> bool: return _hud.team.downed_at.has(bp) and _hud.world_layer.downed_seen.has(bp) and _cue_ms.has(&"ui_mate_down"), WAIT)
	var hint: Dictionary = HudNet.instance.mate_hint.get(bp, {})
	var t_srv := int(hint.get("t_ms", 0))
	# downed_seen holds ticks: bring it to the unix clock of the server's timestamp
	var ind_unix := HudNet.now_ms() - (Time.get_ticks_msec() - int(_hud.world_layer.downed_seen.get(bp, Time.get_ticks_msec())))
	var ind_ms := ind_unix - t_srv
	var cue_ms := int(_cue_ms.get(&"ui_mate_down", 0)) - t_srv
	var p0: Dictionary = _hud.router.p0.get("mate_down:%d" % bp, {})
	var cap := _hud.captions.history.filter(func(h: String) -> bool: return h.begins_with("latido y estática de radio · B"))
	_info["down_indicator_ms"] = ind_ms
	_info["down_cue_ms"] = cue_ms
	_info["rpc_ms"] = HudNet.instance.last_mate_latency_ms
	_checks["down_seen"] = down and t_srv > 0
	_checks["down_fast"] = down and ind_ms >= 0 and ind_ms <= DOWN_BUDGET_MS and cue_ms >= 0 and cue_ms <= DOWN_BUDGET_MS
	_checks["down_p0_world"] = not p0.is_empty() and p0["target"] == &"world" and not _hud.banner.text_now().contains("suelo") and not cap.is_empty()
	_log("A: B down → indicator %d ms, ui_mate_down %d ms after the server (rpc %d ms); P0 %s; caption %s; accent %s" % [ind_ms, cue_ms,
		HudNet.instance.last_mate_latency_ms, p0.get("target", "-"), cap, _hud.accent.accent.get("kind", "-")])
	# revive B (hold, next to it)
	_tp(b.global_position + Vector3(1.0, 0, 0.3))
	await _sleep(1.2)
	Net.rpc_server(NetWorld.instance, &"request_revive", [bp, true])
	var up := await _until(func() -> bool: return not _hud.router.p0.has("mate_down:%d" % bp), WAIT)
	Net.rpc_server(NetWorld.instance, &"request_revive", [bp, false])
	_checks["down_p0_ends"] = up
	_log("A: B revived, P0 ended=%s heartbeat %.2f" % [up, AudioManager.heartbeat_intensity()])


func _danger_id() -> int:
	for id: int in _pings_seen:
		if (_pings_seen[id] as Dictionary)["kind"] == &"danger":
			return id
	return 0


func _finish(lp: Player) -> void:
	tree.process_frame.disconnect(_client_frame)
	if tree.process_frame.is_connected(_team_frame):
		tree.process_frame.disconnect(_team_frame)
	var n := int(opts["clients"])
	var pinger := "C" if n >= 3 else "B"
	var keys: Array = ["synced", "ping_seen", "hazard_countdown"]
	if client_name != pinger:
		keys.append("ping_line")
	if client_name == "A":
		keys.append_array(["down_seen", "down_fast", "down_p0_world", "down_p0_ends"])
	elif client_name == "B":
		keys.append_array(["down", "revived"])
	var ok := _local_seen and lp != null
	for k in keys:
		if not bool(_checks.get(k, false)):
			ok = false
	_log("RESULT %s name=%s scenario=%s checks=%s info=%s pings=%d rtt_max=%.0f" % ["OK" if ok else "FAIL", client_name, scenario, _checks,
		_info, HudNet.instance.pings_received if HudNet.instance != null else -1, _rtt_max])
	tree.quit(0 if ok else 1)
