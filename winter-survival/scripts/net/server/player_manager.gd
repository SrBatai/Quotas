class_name PlayerManager
extends Node
## Server-only: spawns / despawns player bodies (MultiplayerSpawner replicates them), keeps a body in the world
## for NET_GRACE_SECONDS after a disconnect and restores it to the same identity on reconnect (ARQ v2 §15.4),
## and saves profiles + world clock as JSON (M1 stand-in for the SQLite backend of M5).

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var save_path: String = "user://world_save.json"
var _profiles: Dictionary = {}       # token_hash -> profile Dictionary
var _grace: Dictionary = {}          # token_hash -> {"node": Player, "until": float}
var _autosave: float = 0.0
var _pending_peers: Array[int] = []
var _world: World
var _spawn_index: int = 0


func _ready() -> void:
	_world = get_tree().get_first_node_in_group("world")
	if Net.is_dedicated:
		save_path = str(Net.cfg_get("world", "save_path", "user://world_save.json"))
		_load()
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)


func players() -> Array[Player]:
	var out: Array[Player] = []
	for c in _world.get_node("Players").get_children():
		if c is Player:
			out.append(c)
	return out


func player_of(peer: int) -> Player:
	return _world.get_node("Players").get_node_or_null(str(peer)) as Player


## Called by game.gd when the world exists (offline: spawns the local player as peer 1).
func on_world_ready() -> void:
	if Net.is_offline:
		spawn_player(1, Identity.player_name, Identity.token_hash())
	for id in _pending_peers:
		spawn_player(id, Net.name_of(id), Net.token_hash_of(id))
	_pending_peers.clear()


func _on_peer_joined(id: int, pname: String) -> void:
	if not _world.is_ready:
		_pending_peers.append(id)
		return
	spawn_player(id, pname, Net.token_hash_of(id))


func spawn_player(peer_id: int, pname: String, token_hash: String) -> Player:
	var existing := player_of(peer_id)
	if existing != null:
		return existing
	var p: Player = PLAYER_SCENE.instantiate()
	p.name = str(peer_id)
	p.display_name = pname
	p.token_hash = token_hash
	var profile: Dictionary = {}
	# a body still in the world under the reconnect grace? take its live state
	if _grace.has(token_hash):
		var g: Dictionary = _grace[token_hash]
		var old: Player = g["node"]
		if is_instance_valid(old):
			profile = old.to_profile()
			old.queue_free()
		_grace.erase(token_hash)
	elif _profiles.has(token_hash):
		profile = _profiles[token_hash]
	if profile.is_empty():
		var spawn := _world.get_spawn_point() + Vector3(0, 0.15, 0)
		var ring := [Vector3.ZERO, Vector3(1.2, 0, 0.6), Vector3(-1.2, 0, 0.6), Vector3(0, 0, 1.4)]
		spawn += ring[_spawn_index % ring.size()]
		_spawn_index += 1
		p.net_position = spawn
		p.aim_yaw = _world.get_spawn_yaw()
	else:
		p.net_position = Vector3(float(profile.get("x", 0.0)), float(profile.get("y", 1.0)), float(profile.get("z", 0.0)))
		p.aim_yaw = float(profile.get("yaw", 0.0))
	p.pending_profile = profile
	_world.get_node("Players").add_child(p, true)
	print("[EVT] spawn player %d '%s' at %s%s" % [peer_id, pname, p.net_position.snapped(Vector3(0.1, 0.1, 0.1)),
		" (restored)" if not profile.is_empty() else ""])
	if Net.is_dedicated:
		Chat.instance.server_broadcast("SERVIDOR", "%s se ha unido" % pname)
	return p


func _on_peer_left(id: int) -> void:
	var p := player_of(id)
	if p == null:
		return
	p.disconnected = true
	_profiles[p.token_hash] = p.to_profile()
	_grace[p.token_hash] = {"node": p, "until": Time.get_ticks_msec() / 1000.0 + Balance.NET_GRACE_SECONDS}
	print("[EVT] player %d '%s' left; body kept %.0f s" % [id, p.display_name, Balance.NET_GRACE_SECONDS])
	if Net.is_dedicated:
		Chat.instance.server_broadcast("SERVIDOR", "%s se ha ido" % p.display_name)


## 30 Hz: every connected client gets ONE unreliable packet with every player's quantized pose plus its own
## ack/velocity (ARQ v2 §6.2, C10). Runs after the players' _physics_process (PlayerManager is a later sibling).
func _physics_process(_delta: float) -> void:
	if not Net.is_dedicated or Engine.get_physics_frames() % Balance.NET_STATE_EVERY != 0:
		return
	var all := players()
	if all.is_empty():
		return
	var entries := []
	for p in all:
		entries.append({"peer": p.peer_id, "pos": p.position, "yaw": p.aim_yaw})
	var peers := multiplayer.get_peers()
	for p in all:
		if p.disconnected or not peers.has(p.peer_id):
			continue
		multiplayer.send_bytes(Packets.pack_poses(p.net.last_applied_seq, p.velocity, entries), p.peer_id,
			MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 0)


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for th in _grace.keys():
		var g: Dictionary = _grace[th]
		var node: Player = g["node"]
		if not is_instance_valid(node):
			_grace.erase(th)
		elif now >= float(g["until"]):
			_profiles[th] = node.to_profile()
			node.queue_free()
			_grace.erase(th)
			print("[EVT] grace expired for %s" % th.substr(0, 8))
	if Net.is_dedicated:
		_autosave += delta
		if _autosave >= float(Net.cfg_get("world", "autosave_seconds", 60.0)):
			_autosave = 0.0
			save_all()


func save_all() -> void:
	for p in players():
		_profiles[p.token_hash] = p.to_profile()
	var ws := WorldState.instance
	var data := {"version": Net.GAME_VERSION, "world": {"day": ws.day, "hour": ws.hour, "weather": String(ws.weather)},
		"players": _profiles}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("PlayerManager: cannot write %s" % save_path)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("[EVT] saved %d profiles to %s" % [_profiles.size(), save_path])


func _load() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(data) != TYPE_DICTIONARY:
		return
	_profiles = data.get("players", {})
	var w: Dictionary = data.get("world", {})
	if not w.is_empty() and WorldState.instance != null:
		WorldState.instance.set_time(int(w.get("day", 1)), float(w.get("hour", 8.0)))
	print("[EVT] loaded %d profiles from %s" % [_profiles.size(), save_path])
