class_name HudNet
extends Node
## H3 group / hazard / ping replication for the HUD (docs/research/10_hud_ux.md appendix §8.7: pings, hazards and
## the teammates' state are server-authoritative; routing and drawing stay on the client). One node with the same
## path in both flavours (game.gd adds it as /root/Game/HudNet next to ZoneDiscovery), reliable channel 1:
##   client → server  request_sync()                   the local player spawned: send me the team, hazards, pings
##                    request_ping(kind, pos)           «place» | «danger» at a world point (≤ 150 m, 3 per 2 s)
##                    request_test_warning(duration)    debug servers only: a blizzard with its 60 s warning
##   server → client  _mate(peer, downed, bleed, t_ms)  a player went down / got up — pushed the frame the server
##                                                      sees it (the synchronizer's delta interval is 0.2 s: this is
##                                                      what keeps «el derribo de B llega a A» under 0.2 s)
##                    _team(bytes)                      every 0.5 s: [peer:int32, health, warmth, bleed, flags]* —
##                                                      «herido (< 25 %)» with the real health (§8.7 `teammate_state`)
##                    _hazard(kind, state, seconds, detail)   the Weather's blizzard (warning 60 s → active → end)
##                                                      and any E1 / E2 hazard sent with broadcast_hazard()
##                    _ping(id, peer, kind, pos, seconds)
##                    _sync(team, hazards, pings)
## Only peers that asked for the sync get messages (never one still loading the scene: no «Node not found»).
## Offline the in-process server calls the handlers directly (Net.rpc_to), so single player takes the same path.

signal mate_changed(peer: int, downed: bool, t_ms: int)
signal team_changed()

const TEAM_PERIOD := 0.5
const HAZARD_PERIOD := 0.5
const PING_KINDS := ["place", "danger"]
const PING_RATE_MAX := 3
const SYNC_RATE_MAX := 6
## Flags of the team block.
const F_DOWNED := 1
const F_DEAD := 2
const F_HOUSE := 4
const F_COLD := 8

static var instance: HudNet

# ------------------------------------------------------------------ server state
var _synced: Dictionary = {}     # peer -> true
var _downed: Dictionary = {}     # peer -> bool (server view)
var _team_acc: float = 0.0
var _hz_acc: float = 0.0
var _hz_state: StringName = &""
var _api_hazards: Dictionary = {}   # kind -> [state, seconds, detail, t0 (s)]
var _ping_id: int = 0
var _pings: Dictionary = {}      # id -> [peer, kind, pos, until (s), seconds]
var _ping_rate: Dictionary = {}  # peer -> [window start ms, count]
var _sync_rate: Dictionary = {}
var pings_rejected: int = 0
# ------------------------------------------------------------------ client state
## peer -> {health, warmth, bleed, downed, dead, in_house, cold, t}
var team: Dictionary = {}
## peer -> {downed, bleed, t_ms (server), at (local ticks ms)} — the pushed downed state, ahead of the synchronizer.
var mate_hint: Dictionary = {}
var synced: bool = false
var pings_received: int = 0
## Tests: server → this client latency of the last _mate (same machine clock), ms.
var last_mate_latency_ms: int = -1


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	if Net.is_server:
		Net.peer_left.connect(func(id: int) -> void:
			_synced.erase(id)
			_ping_rate.erase(id)
			_sync_rate.erase(id)
			_downed.erase(id))
	if Net.has_client:
		Events.local_player_ready.connect(func(_p: Node) -> void: request_sync_now())
		if GameFlow.local_player() != null:
			request_sync_now.call_deferred()


static func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


# ------------------------------------------------------------------ client API
func request_sync_now() -> void:
	synced = false
	Net.rpc_server(self, &"request_sync", [])


## Places a ping (the HUD's Pings node and the tests call this).
func ping(kind: StringName, pos: Vector3) -> void:
	Net.rpc_server(self, &"request_ping", [String(kind), pos])


## The pushed downed state of a teammate while it is newer than `max_age` s (else {}).
func hint_of(peer: int, max_age: float = 1.0) -> Dictionary:
	var h: Dictionary = mate_hint.get(peer, {})
	if h.is_empty() or float(Time.get_ticks_msec() - int(h["at"])) / 1000.0 > max_age:
		return {}
	return h


# ------------------------------------------------------------------ server
func _rate_ok(table: Dictionary, peer: int, max_n: int) -> bool:
	var now := Time.get_ticks_msec()
	var r: Array = table.get(peer, [now, 0])
	if now - int(r[0]) > 2000:
		r = [now, 0]
	r[1] = int(r[1]) + 1
	table[peer] = r
	return int(r[1]) <= max_n


func _players() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("player"):
		if n is Player and (n as Player).is_inside_tree():
			out.append(n)
	return out


func _process(delta: float) -> void:
	if not Net.is_server or _synced.is_empty():
		return
	# downed flips: checked every frame, pushed at once
	for p: Player in _players():
		var d := p.downed and not p.dead
		if bool(_downed.get(p.peer_id, false)) != d:
			_downed[p.peer_id] = d
			var t := now_ms()
			if Net.is_dedicated:
				print("[EVT] hud mate %d downed=%s bleed=%d t_ms=%d" % [p.peer_id, d, p.bleed, t])
			for q: int in _synced:
				if q != p.peer_id:
					Net.rpc_to(self, &"_mate", q, [p.peer_id, d, p.bleed, t])
	_team_acc += delta
	if _team_acc >= TEAM_PERIOD:
		_team_acc = 0.0
		var ps := _players()
		if ps.size() >= 2:
			var b := _team_bytes(ps)
			for q: int in _synced:
				Net.rpc_to(self, &"_team", q, [b])
	_hz_acc += delta
	if _hz_acc >= HAZARD_PERIOD:
		_hz_acc = 0.0
		_poll_weather()
	# expired pings
	if not _pings.is_empty():
		var now := Time.get_ticks_msec() / 1000.0
		for id: int in _pings.keys():
			if now > float(_pings[id][3]):
				_pings.erase(id)


func _team_bytes(ps: Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(ps.size() * 8)
	var i := 0
	for p: Player in ps:
		var st := p.state
		b.encode_s32(i, p.peer_id)
		b[i + 4] = clampi(int(round(st.health if st != null else 0.0)), 0, 255)
		b[i + 5] = clampi(int(round(st.warmth if st != null else 0.0)), 0, 255)
		b[i + 6] = clampi(p.bleed, 0, 255)
		var f := 0
		if p.downed:
			f |= F_DOWNED
		if p.dead:
			f |= F_DEAD
		if p.in_house:
			f |= F_HOUSE
		if p.cold:
			f |= F_COLD
		b[i + 7] = f
		i += 8
	return b


func _weather() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("World/Weather") if scene != null else null


## The Weather's blizzard (warning → active → clear) as hazard states with the seconds left.
func _poll_weather() -> void:
	var w := _weather()
	if w == null:
		return
	var warn: Variant = w.get("_warning_left")
	var active: Variant = w.get("_active")
	var left: Variant = w.get("_time_left")
	var st := &""
	var secs := -1.0
	if active != null and bool(active):
		st = &"active"
		secs = float(left) if left != null else -1.0
	elif warn != null and float(warn) >= 0.0:
		st = &"soon"
		secs = float(warn)
	if st == _hz_state:
		return
	var was := _hz_state
	_hz_state = st
	if st == &"":
		if was != &"":
			_send_hazard(&"blizzard", &"end", -1.0, "")
	else:
		print("[EVT] hud hazard blizzard %s %.0f s" % [st, secs])
		_send_hazard(&"blizzard", st, secs, "")


func _send_hazard(kind: StringName, state: StringName, secs: float, detail: String) -> void:
	for q: int in _synced:
		Net.rpc_to(self, &"_hazard", q, [String(kind), String(state), secs, detail])


## Server API for E1 / E2 (ice storm, cold wave, avalanche, blackout, fire…): every synced client's HazardStack
## gets the state; late joiners get the last one with the sync.
func broadcast_hazard(kind: StringName, state: StringName, data: Dictionary = {}) -> void:
	if not Net.is_server:
		return
	var secs := float(data.get("seconds", -1.0))
	var detail := str(data.get("detail", ""))
	if HazardStack.norm_state(state) == &"end":
		_api_hazards.erase(kind)
	else:
		_api_hazards[kind] = [String(HazardStack.norm_state(state)), secs, detail, Time.get_ticks_msec() / 1000.0]
	_send_hazard(kind, HazardStack.norm_state(state), secs, detail)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_sync() -> void:
	if not Net.is_server:
		return
	var peer := Net.sender()
	if not _rate_ok(_sync_rate, peer, SYNC_RATE_MAX):
		return
	_synced[peer] = true
	var ps := _players()
	var hz: Array = []
	var w := _weather()
	if w != null:
		_hz_state = &""   # re-announce the blizzard to everybody on the next poll (cheap, idempotent)
	var now := Time.get_ticks_msec() / 1000.0
	for k: StringName in _api_hazards:
		var a: Array = _api_hazards[k]
		var s := float(a[1])
		hz.append([String(k), str(a[0]), s - (now - float(a[3])) if s > 0.0 else -1.0, str(a[2])])
	var pl: Array = []
	for id: int in _pings:
		var g: Array = _pings[id]
		pl.append([id, int(g[0]), str(g[1]), g[2], float(g[3]) - now])
	for p: Player in ps:
		_downed[p.peer_id] = p.downed and not p.dead
	Net.rpc_to(self, &"_sync", peer, [_team_bytes(ps), hz, pl])


@rpc("any_peer", "call_remote", "reliable", 1)
func request_ping(kind: String, pos: Vector3) -> void:
	if not Net.is_server:
		return
	var peer := Net.sender()
	var pm := PlayerManager.instance
	var p: Player = pm.player_of(peer) if pm != null else null
	if not PING_KINDS.has(kind) or p == null or p.dead or not pos.is_finite() or not _rate_ok(_ping_rate, peer, PING_RATE_MAX):
		pings_rejected += 1
		return
	var d := Vector2(pos.x - p.global_position.x, pos.z - p.global_position.z).length()
	if d > UiTokens.PING_RANGE + 10.0:
		pings_rejected += 1
		print("[EVT] ping rejected: peer %d at %.0f m" % [peer, d])
		return
	# at most 3 live per player: the oldest of that player goes
	var mine: Array = []
	for id: int in _pings:
		if int(_pings[id][0]) == peer:
			mine.append(id)
	mine.sort()
	while mine.size() >= UiTokens.PING_PER_PLAYER:
		_pings.erase(mine.pop_front())
	_ping_id += 1
	var secs := UiTokens.PING_DANGER_SECONDS if kind == "danger" else UiTokens.PING_PLACE_SECONDS
	_pings[_ping_id] = [peer, kind, pos, Time.get_ticks_msec() / 1000.0 + secs, secs]
	print("[EVT] ping %d by %d (%s) %s at %s" % [_ping_id, peer, p.display_name, kind, pos.snapped(Vector3(0.1, 0.1, 0.1))])
	for q: int in _synced:
		Net.rpc_to(self, &"_ping", q, [_ping_id, peer, kind, pos, secs])
	if not _synced.has(peer):
		Net.rpc_to(self, &"_ping", peer, [_ping_id, peer, kind, pos, secs])


## Debug servers (server.cfg debug_commands) and offline: a blizzard with its warning (Balance.BLIZZARD_WARNING).
@rpc("any_peer", "call_remote", "reliable", 1)
func request_test_warning(duration: float) -> void:
	if not Net.is_server:
		return
	if not (Net.is_offline or bool(Net.cfg_get("server", "debug_commands", false))):
		return
	var w := _weather()
	if w != null and w.has_method(&"_start_warning"):
		w.call(&"_start_warning", clampf(duration, 10.0, 600.0))
		print("[EVT] hud test: blizzard warning %.0f s, then %.0f s" % [Balance.BLIZZARD_WARNING, duration])


# ------------------------------------------------------------------ client handlers
@rpc("authority", "call_remote", "reliable", 1)
func _mate(peer: int, downed: bool, bleed: int, t_ms: int) -> void:
	mate_hint[peer] = {"downed": downed, "bleed": bleed, "t_ms": t_ms, "at": Time.get_ticks_msec()}
	last_mate_latency_ms = now_ms() - t_ms
	var e: Dictionary = team.get(peer, {})
	if not e.is_empty():
		e["downed"] = downed
		e["bleed"] = bleed
	mate_changed.emit(peer, downed, t_ms)


@rpc("authority", "call_remote", "reliable", 1)
func _team(b: PackedByteArray) -> void:
	_read_team(b)
	team_changed.emit()


func _read_team(b: PackedByteArray) -> void:
	var i := 0
	var t := Time.get_ticks_msec()
	while i + 8 <= b.size():
		var peer := b.decode_s32(i)
		var f := int(b[i + 7])
		var e := {"health": float(b[i + 4]), "warmth": float(b[i + 5]), "bleed": int(b[i + 6]), "downed": f & F_DOWNED != 0,
			"dead": f & F_DEAD != 0, "in_house": f & F_HOUSE != 0, "cold": f & F_COLD != 0, "t": t}
		team[peer] = e
		Events.teammate_state.emit(peer, e)
		i += 8


@rpc("authority", "call_remote", "reliable", 1)
func _hazard(kind: String, state: String, seconds: float, detail: String) -> void:
	var data := {"source": &"server"}
	if seconds > 0.0:
		data["seconds"] = seconds
	if detail != "":
		data["detail"] = detail
	Events.hazard_changed.emit(StringName(kind), StringName(state), data)


@rpc("authority", "call_remote", "reliable", 1)
func _ping(id: int, peer: int, kind: String, pos: Vector3, seconds: float) -> void:
	pings_received += 1
	Events.ping_placed.emit(id, peer, StringName(kind), pos, seconds)


@rpc("authority", "call_remote", "reliable", 1)
func _sync(team_bytes: PackedByteArray, hazards: Array, pings: Array) -> void:
	_read_team(team_bytes)
	for h in hazards:
		if h is Array and (h as Array).size() >= 4:
			_hazard(str(h[0]), str(h[1]), float(h[2]), str(h[3]))
	for g in pings:
		if g is Array and (g as Array).size() >= 5 and float(g[4]) > 0.0:
			_ping(int(g[0]), int(g[1]), str(g[2]), g[3], float(g[4]))
	synced = true
	team_changed.emit()
