class_name PlayerManager
extends Node
## Server-only: spawns / despawns player bodies (MultiplayerSpawner replicates them), assigns each a jacket
## variant, keeps a body in the world for NET_GRACE_SECONDS after a disconnect and restores it to the same
## identity on reconnect (ARQ v2 §15.4), and drives the persistence backend (ARQ v2 §15): profiles + world
## clock + chunk deltas through FileBackend (JSON, dedicated) or MemoryBackend (offline); SQLite is M5.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const OUTFITS := 4

var save_path: String = "user://world_save.json"
var backend: PersistenceBackend
var _grace: Dictionary = {}          # token_hash -> {"node": Player, "until": float}
var _autosave: float = 0.0
var _pending_peers: Array[int] = []
var _world: World
var _spawn_index: int = 0
var _restored_chunks: int = 0


func _ready() -> void:
	_world = get_tree().get_first_node_in_group("world")
	if Net.is_dedicated:
		save_path = str(Net.cfg_get("world", "save_path", "user://world_save.json"))
		var fb := FileBackend.new()
		var err := fb.open(save_path)
		backend = fb
		if err == OK:
			print("[EVT] persistence: %s (%d profiles, %d chunks)" % [save_path, fb.player_count(), fb.chunk_keys().size()])
		var w := backend.load_world_meta()
		if not w.is_empty() and WorldState.instance != null:
			WorldState.instance.set_time(int(w.get("day", 1)), float(w.get("hour", 8.0)))
	else:
		backend = MemoryBackend.new()
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


## Called by game.gd when the world exists: restores the saved world, then spawns the local/pending players.
func on_world_ready() -> void:
	if NetWorld.instance != null:
		_restored_chunks = NetWorld.instance.load_from(backend)
		if _restored_chunks > 0:
			print("[EVT] restored %d chunk deltas" % _restored_chunks)
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


## Least used jacket among the players in the world (distinct colours per peer up to 4).
func _pick_outfit() -> int:
	var used := []
	used.resize(OUTFITS)
	used.fill(0)
	for p in players():
		used[p.outfit % OUTFITS] += 1
	var best := 0
	for i in OUTFITS:
		if used[i] < used[best]:
			best = i
	return best


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
	else:
		profile = backend.load_player(token_hash)
	if profile.is_empty():
		var spawn := _world.get_spawn_point() + Vector3(0, 0.15, 0)
		var ring := [Vector3.ZERO, Vector3(1.2, 0, 0.6), Vector3(-1.2, 0, 0.6), Vector3(0, 0, 1.4)]
		spawn += ring[_spawn_index % ring.size()]
		_spawn_index += 1
		p.net_position = spawn
		p.aim_yaw = _world.get_spawn_yaw()
		p.outfit = _pick_outfit()
	else:
		p.net_position = Vector3(float(profile.get("x", 0.0)), float(profile.get("y", 1.0)), float(profile.get("z", 0.0)))
		p.aim_yaw = float(profile.get("yaw", 0.0))
		p.outfit = int(profile.get("outfit", _pick_outfit())) % OUTFITS
	p.pending_profile = profile
	_world.ensure_area(p.net_position, 1)   # M3: the player's chunks exist before its body does
	_world.get_node("Players").add_child(p, true)
	print("[EVT] spawn player %d '%s' at %s outfit=%d%s" % [peer_id, pname, p.net_position.snapped(Vector3(0.1, 0.1, 0.1)),
		p.outfit, " (restored)" if not profile.is_empty() else ""])
	backend.log_event("join", {"peer": peer_id, "name": pname})
	if Net.is_dedicated:
		Chat.instance.server_broadcast("SERVIDOR", "%s se ha unido" % pname)
	return p


func _on_peer_left(id: int) -> void:
	var p := player_of(id)
	if p == null:
		return
	p.disconnected = true
	backend.save_player(p.token_hash, p.to_profile())
	_grace[p.token_hash] = {"node": p, "until": Time.get_ticks_msec() / 1000.0 + Balance.NET_GRACE_SECONDS}
	print("[EVT] player %d '%s' left; body kept %.0f s" % [id, p.display_name, Balance.NET_GRACE_SECONDS])
	backend.log_event("leave", {"peer": id, "name": p.display_name})
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
	var peers := multiplayer.get_peers()
	var nw := NetWorld.instance
	for p in all:
		if p.disconnected or not peers.has(p.peer_id):
			continue
		# M3 interest: only the players in the recipient's 3 × 3 chunks (+ itself for the ack)
		var entries := []
		for o in all:
			if o == p or nw == null or nw.sees(p.peer_id, o.position):
				entries.append({"peer": o.peer_id, "pos": o.position, "yaw": o.aim_yaw})
		multiplayer.send_bytes(Packets.pack_poses(p.net.last_applied_seq, p.velocity, entries, p.position), p.peer_id,
			MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 0)


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for th in _grace.keys():
		var g: Dictionary = _grace[th]
		var node: Player = g["node"]
		if not is_instance_valid(node):
			_grace.erase(th)
		elif now >= float(g["until"]):
			backend.save_player(th, node.to_profile())
			node.queue_free()
			_grace.erase(th)
			print("[EVT] grace expired for %s" % th.substr(0, 8))
	if Net.is_dedicated:
		_autosave += delta
		if _autosave >= float(Net.cfg_get("world", "autosave_seconds", 60.0)):
			_autosave = 0.0
			save_all()


## Autosave / admin `save`: connected profiles + world clock + dirty chunk deltas, then one atomic write.
func save_all() -> void:
	for p in players():
		backend.save_player(p.token_hash, p.to_profile())
	var ws := WorldState.instance
	backend.save_world_meta({"version": Net.GAME_VERSION, "seed": ws.world_seed, "day": ws.day, "hour": ws.hour,
		"weather": String(ws.weather), "rules": ws.rules})
	var chunks_saved := 0
	if NetWorld.instance != null:
		chunks_saved = NetWorld.instance.save_to(backend)
	var err := backend.flush()
	if err != OK:
		push_warning("PlayerManager: save failed (%s)" % error_string(err))
		return
	print("[EVT] saved %d profiles, %d chunk deltas to %s" % [backend.player_count(), chunks_saved, save_path if Net.is_dedicated else "memory"])
