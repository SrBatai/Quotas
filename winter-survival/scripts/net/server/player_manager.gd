class_name PlayerManager
extends Node
## Server-only: spawns / despawns player bodies (MultiplayerSpawner replicates them), assigns each a jacket
## variant, keeps a body in the world for NET_GRACE_SECONDS after a disconnect and restores it to the same
## identity on reconnect (ARQ v2 §15.4), and drives the persistence backend (ARQ v2 §15): profiles + world
## clock + chunk deltas. M5: BackendFactory picks SqliteBackend (godot-sqlite, WAL, schema migrations) or the
## JSON FileBackend from server.cfg `[world] backend` / `save_path` (offline = MemoryBackend); Autosave writes one
## batch every `autosave_seconds` + a daily backup; bans are checked at authentication (Net.ban_check).

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const OUTFITS := 4
## M2 default store, imported once into a new SQLite store when no save_path is configured (single-player hosts).
const LEGACY_SAVE := "user://world_save.json"

static var instance: PlayerManager

var save_path: String = "user://world_save.json"
var backend: PersistenceBackend
## Backend requested in server.cfg ("sqlite" / "file" / "memory"; "" = derived from save_path).
var backend_requested: String = ""
var autosave: Autosave
var bans: Dictionary = {}
var _grace: Dictionary = {}          # token_hash -> {"node": Player, "until": float}
var _pending_peers: Array[int] = []
var _world: World
var _spawn_index: int = 0
var _restored_chunks: int = 0
var _closed: bool = false


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null
	if Net.ban_check.is_valid() and Net.ban_check.get_object() == self:
		Net.ban_check = Callable()
	close_backend()


func _ready() -> void:
	_world = get_tree().get_first_node_in_group("world")
	if Net.is_dedicated:
		_open_backend()
		autosave = Autosave.new()
		autosave.name = "Autosave"
		add_child(autosave)
		autosave.setup(self)
		bans = backend.load_bans()
		Net.ban_check = is_banned
	else:
		backend = MemoryBackend.new()
	Loot.reset()
	Loot.nominal = backend.load_nominal()
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)


func _open_backend() -> void:
	backend_requested = str(Net.cfg_get("world", "backend", ""))
	var cfg_path := str(Net.cfg_get("world", "save_path", ""))
	var r := BackendFactory.create(backend_requested, cfg_path)
	backend = r[0]
	save_path = str(r[2])
	# single-player / old hosts: the M2 JSON store moves into a brand-new SQLite store once
	if backend is SqliteBackend and (backend as SqliteBackend).loaded_schema == 0:
		var legacy := cfg_path.get_basename() + ".json" if cfg_path != "" else LEGACY_SAVE
		if FileAccess.file_exists(legacy):
			var n := BackendFactory.import_json(legacy, backend)
			print("[EVT] persistence: imported %s into %s (%d chunks)" % [legacy, save_path, n])
	var sq := backend as SqliteBackend
	print("[EVT] persistence: backend=%s (requested '%s') path=%s schema=%d%s players=%d chunks=%d" % [backend.kind(),
		backend_requested, save_path, backend.schema_version(), " journal=%s quick_check=%s" % [sq.journal_mode(), sq.integrity] if sq != null else "",
		backend.player_count(), backend.chunk_keys().size()])
	var w := backend.load_world_meta()
	if w.is_empty():
		return
	if WorldState.instance != null:
		# the clock resumes; the weather scheduler restarts clean (a saved blizzard would skip its warning). Deferred:
		# this runs inside Game._ready, before the world's DayNight (a time_changed listener) is inside the tree
		WorldState.instance.set_time.call_deferred(int(w.get("day", 1)), float(w.get("hour", 8.0)))
	var cfg_seed := int(Net.cfg_get("world", "seed", Balance.TERRAIN_SEED))
	if w.has("seed") and int(w["seed"]) != cfg_seed:
		push_warning("PlayerManager: %s was saved with seed %d but server.cfg says %d: the stored deltas belong to another world" % [save_path, int(w["seed"]), cfg_seed])
	print("[EVT] persistence: world day %d hour %.1f world_version=%d city_version=%d (saved by %s)" % [int(w.get("day", 1)),
		float(w.get("hour", 8.0)), int(w.get("world_version", -1)), int(w.get("city_version", -1)), str(w.get("version", "?"))])


## Closes the store (final checkpoint). Idempotent; the node's exit and save-and-quit call it.
func close_backend() -> void:
	if _closed or backend == null:
		return
	_closed = true
	backend.close()


## Server bans (token hash or "ip:<address>"): the reason, or "" when the peer may join.
func is_banned(token_hash: String, ip: String) -> String:
	if bans.has(token_hash):
		return str((bans[token_hash] as Dictionary).get("reason", "baneado"))
	if ip != "" and bans.has("ip:" + ip):
		return str((bans["ip:" + ip] as Dictionary).get("reason", "baneado"))
	return ""


func ban(token_hash: String, ip: String, reason: String) -> void:
	if token_hash != "":
		backend.save_ban(token_hash, ip, reason)
	if ip != "":
		backend.save_ban("ip:" + ip, ip, reason)
	bans = backend.load_bans()
	backend.log_event("ban", {"token": token_hash.substr(0, 12), "ip": ip, "reason": reason})


func unban(key: String) -> bool:
	var ok := backend.remove_ban(key)
	if not ok and not key.begins_with("ip:"):
		ok = backend.remove_ban("ip:" + key)
	bans = backend.load_bans()
	return ok


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
		if p.disconnected or not peers.has(p.peer_id) or not Net.peer_ready(p.peer_id):
			continue
		# M3 interest: only the players in the recipient's 3 × 3 chunks (+ itself for the ack)
		var entries := []
		for o in all:
			if o == p or nw == null or nw.sees(p.peer_id, o.position):
				entries.append({"peer": o.peer_id, "pos": o.position, "yaw": o.aim_yaw})
		multiplayer.send_bytes(Packets.pack_poses(p.net.last_applied_seq, p.velocity, entries, p.position), p.peer_id,
			MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 0)


func _process(_delta: float) -> void:
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


## Autosave / admin `save`: connected profiles + world clock + dirty chunk deltas + loot counters as ONE batch
## (a single SQLite transaction; one atomic file write for the JSON backend).
func save_all() -> void:
	if backend == null:
		return
	var t0 := Time.get_ticks_usec()
	backend.begin_batch()
	for p in players():
		backend.save_player(p.token_hash, p.to_profile())
	var ws := WorldState.instance
	backend.save_world_meta({"version": Net.GAME_VERSION, "seed": ws.world_seed, "day": ws.day, "hour": ws.hour,
		"weather": String(ws.weather), "rules": ws.rules, "saved_at": int(Time.get_unix_time_from_system())})
	var chunks_saved := 0
	if NetWorld.instance != null:
		chunks_saved = NetWorld.instance.save_to(backend)
	var nominal := Loot.take_dirty_nominal()
	if not nominal.is_empty():
		backend.save_nominal(nominal)
	var err := backend.flush()
	if err != OK:
		push_warning("PlayerManager: save failed (%s %s)" % [error_string(err), backend.last_error])
		return
	print("[EVT] saved %d profiles, %d chunk deltas to %s (%s, %.1f ms)" % [players().size(), chunks_saved,
		save_path if Net.is_dedicated else "memory", backend.kind(), (Time.get_ticks_usec() - t0) / 1000.0])


## Saves one chunk's delta now (container closed, chunk hibernating): its own small transaction.
func save_chunk_now(key: int) -> void:
	if backend == null or NetWorld.instance == null:
		return
	var d: ChunkDelta = NetWorld.instance.chunks.get(key)
	if d != null and d.is_dirty():
		backend.save_chunk_delta(d)
