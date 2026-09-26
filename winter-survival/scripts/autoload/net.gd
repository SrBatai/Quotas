extends Node
## Autoload `Net` (ARQ v2 §2, §4): role detection, server.cfg, authentication (nonce + HMAC-SHA256 of the
## password, version/protocol check, identity token), hosting the dedicated server as a child process,
## joining, polling in _physics_process and ENet statistics. The same code runs in the dedicated server,
## the client and the offline (in-process local server) mode used by tests and as a fallback.

enum Role { NONE, OFFLINE, SERVER, CLIENT }

const GAME_VERSION := "0.5.0-m3"
## 2 (M3): the auth nonce carries the world seed (8 bytes after the 16 random ones).
const NET_PROTOCOL := 2
const GAME_SCENE := "res://scenes/main/game.tscn"
const DEFAULT_PORT := 7777
const DEFAULT_ADMIN_PORT := 7778
const DEFAULT_CFG := "user://server.cfg"
const AUTH_TIMEOUT := 5.0
const MAX_CHANNELS := 4
const HOST_WAIT_SECONDS := 25.0

signal role_changed(role: int)
signal connected()
signal disconnected(reason: String)
signal auth_failed(reason: String)
signal peer_joined(peer_id: int, display_name: String)
signal peer_left(peer_id: int)
signal server_ready()
## Client: the server's world seed arrived with the authentication nonce (before any spawn or RPC).
signal seed_received(world_seed: int)

var role: Role = Role.NONE
var cfg := ConfigFile.new()
var cfg_path: String = ""
var rules: Dictionary = {"pvp": false, "friendly_fire": "off"}
var enet: ENetMultiplayerPeer
var hosted_pid: int = -1
var hosted_admin_port: int = DEFAULT_ADMIN_PORT
var hosted_admin_token: String = ""
var last_error: String = ""
var world_is_ready: bool = false
## Client: world seed announced by the server during authentication (0 = not known yet).
var server_seed: int = 0
## peer_id -> {"name": String, "token_hash": String, "ip": String} (server)
var peers: Dictionary = {}
## Bandwidth / RTT (client and server), refreshed once per second.
var stats: Dictionary = {"rtt": 0.0, "loss": 0.0, "in_kbps": 0.0, "out_kbps": 0.0, "peers": 0}

var _nonces: Dictionary = {}
var _client_password: String = ""
var _client_name: String = ""
var _stats_timer: float = 0.0
var _signals_wired: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if OS.has_feature("dedicated_server") or args.has("--server"):
		var path := _arg(args, "--config", DEFAULT_CFG)
		var err := start_server(path)
		if err != OK:
			get_tree().quit(2)


func _arg(args: PackedStringArray, key: String, default: String) -> String:
	var i := args.find(key)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	for a in args:
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return default


# ------------------------------------------------------------------ role helpers
var is_server: bool:
	get: return role == Role.SERVER or role == Role.OFFLINE or role == Role.NONE
var has_client: bool:
	get: return role == Role.CLIENT or role == Role.OFFLINE or role == Role.NONE
var is_offline: bool:
	get: return role == Role.OFFLINE or role == Role.NONE
var is_dedicated: bool:
	get: return role == Role.SERVER
var is_client: bool:
	get: return role == Role.CLIENT


func local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()


## Sender of the RPC being handled (1 for direct calls in offline mode).
func sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return s if s != 0 else 1


## Server -> one peer. In offline mode (peer == self) the method is called directly.
func rpc_to(node: Node, method: StringName, peer: int, args: Array = []) -> void:
	if peer == local_peer_id() or multiplayer.multiplayer_peer == null:
		node.callv(method, args)
	elif multiplayer.get_peers().has(peer):
		node.callv("rpc_id", [peer, method] + args)


## Server -> every remote peer (the caller handles its own local copy).
func rpc_all(node: Node, method: StringName, args: Array = []) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.get_peers().is_empty():
		return
	node.callv("rpc", [method] + args)


## Client -> server. In offline mode the handler runs directly (sender() == 1).
func rpc_server(node: Node, method: StringName, args: Array = []) -> void:
	if is_server:
		node.callv(method, args)
	else:
		node.callv("rpc_id", [1, method] + args)


func cfg_get(section: String, key: String, default: Variant) -> Variant:
	return cfg.get_value(section, key, default)


# ------------------------------------------------------------------ offline (in-process local server)
func start_offline() -> void:
	if role == Role.OFFLINE:
		return
	_reset_peer()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	multiplayer.server_relay = false
	multiplayer.allow_object_decoding = false
	peers = {1: {"name": Identity.player_name, "token_hash": Identity.token_hash(), "ip": "local"}}
	rules = {"pvp": false, "friendly_fire": "off"}
	_set_role(Role.OFFLINE)


# ------------------------------------------------------------------ server
func load_config(path: String) -> void:
	cfg_path = path
	cfg = ConfigFile.new()
	if cfg.load(path) != OK:
		push_warning("Net: no %s; using defaults" % path)
		cfg = ConfigFile.new()
	rules = {
		"pvp": bool(cfg.get_value("rules", "pvp", false)),
		"friendly_fire": str(cfg.get_value("rules", "friendly_fire", "off")).to_lower(),
	}


func start_server(path: String) -> Error:
	load_config(path)
	_reset_peer()
	var port := int(cfg.get_value("server", "port", DEFAULT_PORT))
	var max_players := int(cfg.get_value("server", "max_players", 4))
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players, MAX_CHANNELS)
	if err != OK:
		last_error = "create_server: %s" % error_string(err)
		push_error("Net: " + last_error)
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	enet = peer
	multiplayer.multiplayer_peer = peer
	multiplayer.server_relay = false
	multiplayer.allow_object_decoding = false
	multiplayer.auth_timeout = AUTH_TIMEOUT
	multiplayer.auth_callback = _server_auth
	multiplayer.refuse_new_connections = true   # until the world is ready
	_wire_signals()
	Engine.max_fps = 60
	get_tree().multiplayer_poll = false
	_set_role(Role.SERVER)
	print("[NET] server '%s' listening UDP %d | max_players=%d | pvp=%s friendly_fire=%s | godot=%s | dedicated_server=%s" % [
		str(cfg.get_value("server", "name", "Ventisca")), port, max_players, rules["pvp"], rules["friendly_fire"],
		Engine.get_version_info()["string"], OS.has_feature("dedicated_server")])
	# The game scene is loaded by the boot scene (dedicated build) or by the test runner: an autoload's _ready
	# runs while the root is still adding children, where change_scene_to_file is refused.
	return OK


## Loads game.tscn on the next idle frame (safe from _ready / autoload setup).
func load_game_scene() -> void:
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)


## Called by game.gd once the world exists: accept connections.
func mark_world_ready() -> void:
	world_is_ready = true
	if role == Role.SERVER:
		multiplayer.refuse_new_connections = false
		print("[NET] READY")
	server_ready.emit()


func _wire_signals() -> void:
	if _signals_wired:
		return
	_signals_wired = true
	multiplayer.peer_authenticating.connect(_on_peer_authenticating)
	multiplayer.peer_authentication_failed.connect(_on_peer_auth_failed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_packet.connect(_on_peer_packet)


## Raw packets (SceneMultiplayer.send_bytes): first byte = type (Packets.PKT_*).
func _on_peer_packet(from: int, packet: PackedByteArray) -> void:
	if packet.is_empty() or from != 1 or role != Role.CLIENT:
		return
	if packet[0] == Packets.PKT_POSES:
		var d := Packets.unpack_poses(packet)
		if d.is_empty():
			return
		var world := get_tree().get_first_node_in_group("world")
		var players: Node = world.get_node_or_null("Players") if world != null else null
		if players == null:
			return
		for e in d["poses"]:
			var p: Node = players.get_node_or_null(str(int(e["peer"])))
			if p == null:
				continue
			if p.is_local:
				p.net.on_state(int(d["ack"]), e["pos"], d["vel"])
			else:
				p.net.on_remote_pose(e["pos"], float(e["yaw"]))


func _on_peer_authenticating(id: int) -> void:
	if role == Role.SERVER:
		# 16 random bytes + the world seed (s64): the client needs the seed to build its chunks (M3)
		var msg := Crypto.new().generate_random_bytes(16)
		var seed_bytes := PackedByteArray()
		seed_bytes.resize(8)
		seed_bytes.encode_s64(0, int(cfg.get_value("world", "seed", Balance.TERRAIN_SEED)))
		msg.append_array(seed_bytes)
		_nonces[id] = msg
		multiplayer.send_auth(id, msg)
	elif role == Role.CLIENT:
		pass  # the client answers the server's nonce in _client_auth


func _on_peer_auth_failed(id: int) -> void:
	_nonces.erase(id)
	if role == Role.SERVER:
		print("[NET] auth failed/timeout peer %d" % id)
	else:
		last_error = "auth"
		auth_failed.emit("auth_timeout")


func _server_auth(id: int, data: PackedByteArray) -> void:
	var d: Variant = JSON.parse_string(data.get_string_from_utf8())
	var reason := ""
	if typeof(d) != TYPE_DICTIONARY:
		reason = "handshake"
	elif int(d.get("proto", -1)) != NET_PROTOCOL or str(d.get("version", "")) != GAME_VERSION:
		reason = "version:%s" % GAME_VERSION
	elif not _password_ok(id, str(d.get("hmac", ""))):
		reason = "password"
	elif peers.size() >= int(cfg.get_value("server", "max_players", 4)):
		reason = "full"
	elif str(d.get("token", "")).length() != 64:
		reason = "identity"
	_nonces.erase(id)
	if reason != "":
		print("[NET] auth REJECT peer %d: %s" % [id, reason])
		multiplayer.send_auth(id, ("ERR:" + reason).to_utf8_buffer())
		multiplayer.disconnect_peer(id)
		return
	var pname := _sanitize_name(str(d.get("name", "")))
	var token_hash := Identity.sha256_hex(str(d["token"]).hex_decode())
	var ip := ""
	if enet != null and enet.get_peer(id) != null:
		ip = enet.get_peer(id).get_remote_address()
	peers[id] = {"name": pname, "token_hash": token_hash, "ip": ip}
	print("[NET] auth OK peer %d name=%s" % [id, pname])
	multiplayer.complete_auth(id)


func _sanitize_name(n: String) -> String:
	var out := ""
	for ch in n.strip_edges():
		var code := ch.unicode_at(0)
		if code >= 32 and code != 127:
			out += ch
	out = out.substr(0, 24)
	return out if out != "" else "Anónimo"


func _password_ok(id: int, hmac_hex: String) -> bool:
	var pw: String = str(cfg.get_value("server", "password", ""))
	if pw == "":
		return true
	return hmac_hex == hmac_hex_for(pw, _nonces.get(id, PackedByteArray()))


static func hmac_hex_for(password: String, nonce: PackedByteArray) -> String:
	if password == "" or nonce.is_empty():
		return ""   # open server: no proof needed (mbedTLS refuses an empty HMAC key)
	var h := HMACContext.new()
	h.start(HashingContext.HASH_SHA256, password.to_utf8_buffer())
	h.update(nonce)
	return h.finish().hex_encode()


func _on_peer_connected(id: int) -> void:
	if role != Role.SERVER:
		return
	if not peers.has(id):
		peers[id] = {"name": "peer%d" % id, "token_hash": "", "ip": ""}
	print("[NET] peer_connected %d (%s)" % [id, peers[id]["name"]])
	peer_joined.emit(id, peers[id]["name"])


func _on_peer_disconnected(id: int) -> void:
	if role != Role.SERVER:
		return
	print("[NET] peer_disconnected %d" % id)
	peer_left.emit(id)
	peers.erase(id)
	_nonces.erase(id)


func token_hash_of(peer_id: int) -> String:
	return str(peers.get(peer_id, {}).get("token_hash", ""))


func name_of(peer_id: int) -> String:
	return str(peers.get(peer_id, {}).get("name", "peer%d" % peer_id))


func kick(peer_id: int, reason: String = "kicked") -> void:
	if role == Role.SERVER and multiplayer.get_peers().has(peer_id):
		print("[NET] kick %d (%s)" % [peer_id, reason])
		multiplayer.disconnect_peer(peer_id)


# ------------------------------------------------------------------ client
func join(host: String, port: int, password: String, player_name: String) -> Error:
	_reset_peer()
	_client_password = password
	_client_name = player_name
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		last_error = "create_client: %s" % error_string(err)
		push_error("Net: " + last_error)
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	enet = peer
	multiplayer.multiplayer_peer = peer
	multiplayer.server_relay = false
	multiplayer.allow_object_decoding = false
	multiplayer.auth_callback = _client_auth
	_wire_signals()
	get_tree().multiplayer_poll = false
	_set_role(Role.CLIENT)
	print("[NET] connecting to %s:%d as %s" % [host, port, player_name])
	return OK


func _client_auth(_id: int, data: PackedByteArray) -> void:
	# the server sends either a 16-byte nonce or "ERR:<reason>" (only decode text in the latter case)
	if data.size() > 4 and data.slice(0, 4) == "ERR:".to_utf8_buffer():
		last_error = data.slice(4).get_string_from_utf8()
		print("[NET] auth rejected: %s" % last_error)
		auth_failed.emit(last_error)
		return
	if data.size() >= 24:
		server_seed = data.decode_s64(16)
		seed_received.emit(server_seed)
	var payload := {"version": GAME_VERSION, "proto": NET_PROTOCOL, "name": _client_name,
		"token": Identity.token_hex(), "hmac": hmac_hex_for(_client_password, data)}
	multiplayer.send_auth(1, JSON.stringify(payload).to_utf8_buffer())
	multiplayer.complete_auth(1)


func _on_connected_to_server() -> void:
	if role != Role.CLIENT:
		return
	print("[NET] connected_to_server, my id=%d" % multiplayer.get_unique_id())
	connected.emit()


func _on_connection_failed() -> void:
	if role != Role.CLIENT:
		return
	var reason := last_error if last_error != "" else "connection_failed"
	print("[NET] connection_failed (%s)" % reason)
	_reset_peer()
	_set_role(Role.NONE)
	disconnected.emit(reason)


func _on_server_disconnected() -> void:
	if role != Role.CLIENT:
		return
	print("[NET] server_disconnected")
	_reset_peer()
	_set_role(Role.NONE)
	disconnected.emit("server_disconnected")


func disconnect_from_server() -> void:
	if role == Role.CLIENT:
		print("[NET] disconnecting")
	_reset_peer()
	_set_role(Role.NONE)


func _reset_peer() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	enet = null
	peers.clear()
	_nonces.clear()
	world_is_ready = false
	server_seed = 0
	last_error = ""


func _set_role(r: Role) -> void:
	if role == r:
		return
	role = r
	role_changed.emit(role)


# ------------------------------------------------------------------ hosting from the game (child process)
## Writes user://server.cfg if missing and launches this executable as a headless dedicated server.
func host_from_game(server_name: String, password: String, port: int = DEFAULT_PORT) -> bool:
	var path := DEFAULT_CFG
	var c := ConfigFile.new()
	c.load(path)
	c.set_value("server", "name", server_name)
	c.set_value("server", "password", password)
	c.set_value("server", "port", port)
	c.set_value("server", "max_players", int(c.get_value("server", "max_players", 4)))
	c.set_value("server", "admin_port", int(c.get_value("server", "admin_port", DEFAULT_ADMIN_PORT)))
	if str(c.get_value("server", "admin_token", "")) == "":
		c.set_value("server", "admin_token", Crypto.new().generate_random_bytes(8).hex_encode())
	c.set_value("rules", "pvp", bool(c.get_value("rules", "pvp", false)))
	c.set_value("rules", "friendly_fire", str(c.get_value("rules", "friendly_fire", "off")))
	c.set_value("world", "seed", int(c.get_value("world", "seed", Balance.TERRAIN_SEED)))
	c.set_value("world", "day_length_sec", float(c.get_value("world", "day_length_sec", Balance.DAY_LENGTH_SEC)))
	c.save(path)
	hosted_admin_port = int(c.get_value("server", "admin_port", DEFAULT_ADMIN_PORT))
	hosted_admin_token = str(c.get_value("server", "admin_token", ""))
	var args: PackedStringArray = ["--headless"]
	if not OS.has_feature("template"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--", "--server", "--config", ProjectSettings.globalize_path(path)])
	hosted_pid = OS.create_process(OS.get_executable_path(), args)
	if hosted_pid <= 0:
		last_error = "cannot launch the server process"
		push_warning("Net: " + last_error)
		return false
	print("[NET] hosted server pid=%d" % hosted_pid)
	return true


## Waits until the hosted server's admin socket answers (world ready), up to HOST_WAIT_SECONDS.
func wait_for_hosted_server() -> bool:
	var t := 0.0
	while t < HOST_WAIT_SECONDS:
		if hosted_pid > 0 and not OS.is_process_running(hosted_pid):
			last_error = "the server process exited"
			return false
		var reply := admin_command("status", hosted_admin_port, hosted_admin_token, 0.3)
		if reply.begins_with("OK"):
			return true
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	last_error = "server did not answer"
	return false


## Asks the hosted server to save and quit; kills it if it does not exit in time.
func stop_hosted_server() -> void:
	if hosted_pid <= 0:
		return
	var pid := hosted_pid
	hosted_pid = -1
	if OS.is_process_running(pid):
		admin_command("save-and-quit", hosted_admin_port, hosted_admin_token, 2.0)
		var waited := 0
		while OS.is_process_running(pid) and waited < 3000:
			OS.delay_msec(100)
			waited += 100
		if OS.is_process_running(pid):
			OS.kill(pid)
	print("[NET] hosted server stopped")


## Blocking line-protocol admin call to 127.0.0.1:<port>: "<token>\n<command>\n" -> reply text ("" on failure).
static func admin_command(command: String, port: int, token: String, timeout: float = 2.0) -> String:
	var tcp := StreamPeerTCP.new()
	if tcp.connect_to_host("127.0.0.1", port) != OK:
		return ""
	var t0 := Time.get_ticks_msec()
	tcp.poll()
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() - t0 < timeout * 1000.0:
		OS.delay_msec(10)
		tcp.poll()
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return ""
	tcp.put_data((token + "\n" + command + "\n").to_utf8_buffer())
	var out := ""
	while Time.get_ticks_msec() - t0 < timeout * 1000.0:
		tcp.poll()
		var n := tcp.get_available_bytes()
		if n > 0:
			out += tcp.get_utf8_string(n)
			if out.ends_with("\n\n") or out.find("\nEND\n") >= 0:
				break
		elif tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		OS.delay_msec(10)
	tcp.disconnect_from_host()
	return out.strip_edges()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		stop_hosted_server()


# ------------------------------------------------------------------ loop
func _physics_process(delta: float) -> void:
	if role != Role.NONE and not get_tree().multiplayer_poll:
		multiplayer.poll()
	_stats_timer += delta
	if _stats_timer >= 1.0:
		_refresh_stats(_stats_timer)
		_stats_timer = 0.0


func _refresh_stats(span: float) -> void:
	stats["peers"] = multiplayer.get_peers().size() if multiplayer.multiplayer_peer != null else 0
	if enet == null:
		stats["in_kbps"] = 0.0
		stats["out_kbps"] = 0.0
		stats["rtt"] = 0.0
		stats["loss"] = 0.0
		return
	var sent := enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var recv := enet.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	stats["out_kbps"] = sent / span / 1000.0
	stats["in_kbps"] = recv / span / 1000.0
	if role == Role.CLIENT and enet.get_peer(1) != null:
		var p := enet.get_peer(1)
		stats["rtt"] = p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
		stats["loss"] = p.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / float(ENetPacketPeer.PACKET_LOSS_SCALE) * 100.0
