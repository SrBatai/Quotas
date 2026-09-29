class_name ZoneDiscovery
extends Node
## Zone discovery (H2, PLAN C35; docs/research/10_hud_ux.md appendix §6.1 and §8.7): server-authoritative and, with
## the server rule `shared_discovery` (default on), shared by the group. One node with the same path in both flavours
## (game.gd adds it as /root/Game/ZoneDiscovery), so its RPCs work like NetWorld's:
##   client → server  request_sync()            the local player spawned: send me what my group discovered
##                    request_discover(zone_id)  my ZoneTracker confirmed an undiscovered zone (12 m / 1.5 s)
##   server → client  _sync(list)                [[zone_id, by_name], …] of the peer's scope
##                    _discovered(zone_id, by_name, by_peer)
## The server checks the zone exists and that the player really stands in it (its authoritative position, with a
## 40 m margin for latency), keeps the first discovery of each zone per scope ("group", or the player's token hash
## when the rule is off) and stores it through the persistence backend (schema 3 `discoveries`: SQLite / JSON).
## Every synced client of the scope hears about it; the others get the P3 feed line «Ana descubrió: Las Torres» and,
## when they get there, the compact title instead of the big one (ZoneTracker asks `is_known`). Offline (in-process
## server, MemoryBackend) the store is user://hud_discovered.cfg per world seed (the H1 file), so single-player
## discovery still survives a restart.

signal synced_changed()

const SCOPE_GROUP := "group"
const OFFLINE_PATH := "user://hud_discovered.cfg"
## Server check: the player must be at most this far outside the zone it claims (client inset 12 m + latency).
const VALIDATE_MARGIN := 40.0
## Rate limit per peer: requests in a 2 s window.
const RATE_MAX := 12

static var instance: ZoneDiscovery

# ------------------------------------------------------------------ server state
var store: Dictionary = {}      # scope -> {zone_id -> {by, token, day, ts}}
var _synced: Dictionary = {}    # peer -> scope
var _rate: Dictionary = {}      # peer -> [window start (ms), count]
var _offline_key: String = ""
var rejected: int = 0
# ------------------------------------------------------------------ client state
## Zones the local player's scope has discovered: zone_id -> by_name.
var known: Dictionary = {}
## Discoveries requested by the local player and not yet confirmed: zone_id -> true.
var pending: Dictionary = {}
var synced: bool = false


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	if Net.is_server:
		Net.peer_left.connect(func(id: int) -> void:
			_synced.erase(id)
			_rate.erase(id))
		_load_server()
	if Net.has_client:
		Events.local_player_ready.connect(func(_p: Node) -> void: request_sync_now())
		if GameFlow.local_player() != null:
			request_sync_now.call_deferred()


# ------------------------------------------------------------------ client API (ZoneTracker)
## True when the local player's scope already discovered the zone (or the player just asked for it).
func is_known(zone_id: String) -> bool:
	return known.has(zone_id) or pending.has(zone_id)


## The local player confirmed an undiscovered zone: ask the server to record it.
func discover(zone_id: String) -> void:
	if is_known(zone_id):
		return
	pending[zone_id] = true
	Net.rpc_server(self, &"request_discover", [zone_id])


func request_sync_now() -> void:
	synced = false
	Net.rpc_server(self, &"request_sync", [])


## Tests / screenshots: forget every discovery of the local scope (offline store included).
func forget_all() -> void:
	known.clear()
	pending.clear()
	if Net.is_server:
		store.clear()
		if Net.is_offline:
			_save_offline()


# ------------------------------------------------------------------ server
func _backend() -> PersistenceBackend:
	var pm := PlayerManager.instance
	return pm.backend if pm != null else null


func _load_server() -> void:
	if Net.is_offline:
		_load_offline()
		return
	var b := _backend()
	if b == null:
		return
	store = b.load_discoveries()
	var n := 0
	for s in store:
		n += (store[s] as Dictionary).size()
	print("[EVT] discovery: %d zones restored in %d scopes (shared_discovery=%s, backend %s)" % [n, store.size(), _shared(), b.kind()])


func _shared() -> bool:
	return bool(WorldState.rules_now().get("shared_discovery", true))


func scope_of(peer: int) -> String:
	if _shared():
		return SCOPE_GROUP
	var th := Net.token_hash_of(peer) if not Net.is_offline else Identity.token_hash()
	return th if th != "" else "peer%d" % peer


func _scope_dict(scope: String) -> Dictionary:
	if Net.is_offline:
		_check_offline_seed()
	if not store.has(scope):
		store[scope] = {}
	return store[scope]


func _rate_ok(peer: int) -> bool:
	var now := Time.get_ticks_msec()
	var r: Array = _rate.get(peer, [now, 0])
	if now - int(r[0]) > 2000:
		r = [now, 0]
	r[1] = int(r[1]) + 1
	_rate[peer] = r
	return int(r[1]) <= RATE_MAX


@rpc("any_peer", "call_remote", "reliable", 1)
func request_sync() -> void:
	if not Net.is_server:
		return
	var peer := Net.sender()
	if not _rate_ok(peer):
		return
	var scope := scope_of(peer)
	_synced[peer] = scope
	var list: Array = []
	var d := _scope_dict(scope)
	for id: String in d:
		list.append([id, str((d[id] as Dictionary).get("by", ""))])
	Net.rpc_to(self, &"_sync", peer, [list])


@rpc("any_peer", "call_remote", "reliable", 1)
func request_discover(zone_id: String) -> void:
	if not Net.is_server:
		return
	var peer := Net.sender()
	if not _rate_ok(peer):
		return
	var e := Locations.by_id(zone_id)
	var pm := PlayerManager.instance
	var p: Player = pm.player_of(peer) if pm != null else null
	if e.is_empty() or p == null or p.dead:
		rejected += 1
		return
	var id := str(e["id"])
	var dep := Locations.depth(e, p.global_position.x, p.global_position.z)
	if dep < -VALIDATE_MARGIN:
		rejected += 1
		print("[EVT] discovery rejected: peer %d claims %s from %.0f m outside" % [peer, id, -dep])
		return
	var scope := scope_of(peer)
	var d := _scope_dict(scope)
	if d.has(id):
		# already known in this scope (a race between two players): the caller learns it
		Net.rpc_to(self, &"_discovered", peer, [id, str((d[id] as Dictionary).get("by", "")), 0])
		return
	var rec := {"by": p.display_name, "token": p.token_hash, "day": WorldState.day_now(), "ts": int(Time.get_unix_time_from_system())}
	d[id] = rec
	if Net.is_offline:
		_save_offline()
	else:
		var b := _backend()
		if b != null:
			b.save_discovery(scope, id, rec)
			b.log_event("discover", {"zone": id, "by": p.display_name, "scope": scope.substr(0, 12)})
	print("[EVT] zone discovered: %s by %s (peer %d, scope %s, %d in scope)" % [id, p.display_name, peer, scope.substr(0, 12), d.size()])
	for q: int in _synced:
		if str(_synced[q]) == scope:
			Net.rpc_to(self, &"_discovered", q, [id, p.display_name, peer])
	if not _synced.has(peer):
		Net.rpc_to(self, &"_discovered", peer, [id, p.display_name, peer])


# ------------------------------------------------------------------ client handlers
@rpc("authority", "call_remote", "reliable", 1)
func _sync(list: Array) -> void:
	known.clear()
	for it in list:
		if it is Array and (it as Array).size() >= 2:
			known[str(it[0])] = str(it[1])
			pending.erase(str(it[0]))
	synced = true
	synced_changed.emit()


@rpc("authority", "call_remote", "reliable", 1)
func _discovered(zone_id: String, by_name: String, by_peer: int) -> void:
	var own := by_peer == Net.local_peer_id()
	var had := known.has(zone_id) or pending.has(zone_id)
	known[zone_id] = by_name
	pending.erase(zone_id)
	Events.zone_discovered.emit(StringName(zone_id), by_name, own)
	if own or had or by_peer == 0:
		return
	# a teammate discovered it: one P3 line in the feed (appendix §6.1 «Ana descubrió: Distrito Financiero»)
	var e := Locations.by_id(zone_id)
	if e.is_empty():
		return
	Events.notify_ex.emit({"priority": 3, "key": "disc:" + zone_id, "body": "%s descubrió: %s" % [by_name, str(e["name"])]})


# ------------------------------------------------------------------ offline store (single player)
func _check_offline_seed() -> void:
	var key := "seed_%d" % (WorldState.instance.world_seed if WorldState.instance != null else 0)
	if key != _offline_key:
		_offline_key = key
		_load_offline()


func _load_offline() -> void:
	store.clear()
	if _offline_key == "":
		_offline_key = "seed_%d" % (WorldState.instance.world_seed if WorldState.instance != null else 0)
	var cfg := ConfigFile.new()
	if cfg.load(OFFLINE_PATH) != OK:
		return
	var d := {}
	for id: String in cfg.get_value(_offline_key, "ids", PackedStringArray()):
		d[id] = {"by": str(cfg.get_value(_offline_key, "by_" + id, Identity.player_name)), "day": 0, "ts": 0}
	store[scope_of(1)] = d


func _save_offline() -> void:
	if _offline_key == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(OFFLINE_PATH)
	if cfg.has_section(_offline_key):
		cfg.erase_section(_offline_key)
	var d: Dictionary = store.get(scope_of(1), {})
	cfg.set_value(_offline_key, "ids", PackedStringArray(d.keys()))
	cfg.save(OFFLINE_PATH)
