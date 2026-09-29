class_name AdminCommands
extends RefCounted
## Server administration (ARQ v2 §16.5, M5): one command set for the localhost admin socket (server/admin.sh,
## systemd ExecStop, Docker healthcheck) and for the chat (`/<command>` from a player whose identity hash is listed in
## server.cfg `[server] admin_tokens`, or anyone offline). Replies are text lines starting with OK / ERR.
##   status · players · stats · dbinfo · save · save-and-quit · quit · backup
##   say|broadcast <text> · kick <player> [reason] · ban <player|token_hash|ip> [reason] · unban <token_hash|ip> · bans
##   rule <key> <value> · rules · pvp on|off · ff off|reduced|full · time <hour> · day <n> · weather clear|blizzard [s]
##   give [player] <item> [n] · tp [player] <x> <z>
## <player> = display name (case-insensitive) or peer id. Every command is logged as `[ADMIN]` / an `admin` event.

## Rules an admin may change at runtime (type-checked; replicated through WorldState.rules).
const RULES := {"pvp": TYPE_BOOL, "friendly_fire": TYPE_STRING, "zombie_count_scale": TYPE_FLOAT, "noise_scale": TYPE_FLOAT,
	"cold_scale": TYPE_FLOAT, "loot_respawn": TYPE_FLOAT, "personal_loot_bags": TYPE_BOOL, "ammo_crafting": TYPE_BOOL,
	"permadeath": TYPE_BOOL, "fire_spread": TYPE_BOOL, "safety_system": TYPE_BOOL}
## Commands a chat admin may use (the socket accepts all of them).
const CHAT_COMMANDS := ["status", "players", "save", "backup", "say", "broadcast", "kick", "ban", "unban", "bans", "rule",
	"rules", "pvp", "ff", "time", "day", "weather", "give", "tp", "stats", "dbinfo"]

var tree: SceneTree
var manager: PlayerManager


func _init(p_tree: SceneTree, p_manager: PlayerManager) -> void:
	tree = p_tree
	manager = p_manager


## True when `peer` may run chat admin commands.
static func is_admin(peer: int) -> bool:
	if Net.is_offline:
		return true
	var th := Net.token_hash_of(peer)
	if th == "":
		return false
	var list: Variant = Net.cfg_get("server", "admin_tokens", [])
	if list is String:
		list = (list as String).split(",", false)
	for t in list:
		if str(t).strip_edges().to_lower() == th.to_lower():
			return true
	return false


## Runs one command line (no leading slash). `from_peer` = 0 for the socket, the peer id for a chat admin.
func run(line: String, from_peer: int = 0) -> String:
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return "ERR empty"
	var cmd := parts[0].to_lower()
	if from_peer != 0 and not CHAT_COMMANDS.has(cmd):
		return "ERR %s is only available on the admin socket" % cmd
	print("[ADMIN] %s%s" % [line, "" if from_peer == 0 else " (chat, peer %d)" % from_peer])
	if manager != null and manager.backend != null and cmd != "status" and cmd != "players" and cmd != "stats":
		manager.backend.log_event("admin", {"cmd": line.substr(0, 120), "peer": from_peer})
	var args := parts.slice(1)
	match cmd:
		"status":
			return "OK %s" % status_line()
		"players":
			var out := "OK %d" % manager.players().size()
			for p in manager.players():
				out += "\n%d %s %s hp=%.0f%s token=%s" % [p.peer_id, p.display_name, p.global_position.snapped(Vector3(0.1, 0.1, 0.1)),
					p.state.health, " (desconectado)" if p.disconnected else "", p.token_hash.substr(0, 12)]
			return out
		"stats":
			return "OK %s" % stats_line()
		"dbinfo":
			return "OK %s" % db_line()
		"save":
			manager.save_all()
			return "OK saved %s (%s)" % [manager.save_path, manager.backend.kind()]
		"save-and-quit":
			shutdown(true)
			return "OK saving and quitting"
		"quit":
			shutdown(false)
			return "OK quitting"
		"backup":
			var p := manager.autosave.daily_backup(true) if manager.autosave != null else ""
			return "OK backup %s" % p if p != "" else "ERR backup failed"
		"say", "broadcast":
			var text := line.substr(line.find(" ") + 1).strip_edges() if args.size() > 0 else ""
			if text == "":
				return "ERR usage: say <text>"
			Chat.instance.server_broadcast("SERVIDOR", text)
			return "OK"
		"kick":
			var p := find_player(args[0] if args.size() > 0 else "")
			if p == null:
				return "ERR no such player"
			var reason := " ".join(args.slice(1)) if args.size() > 1 else "expulsado por el administrador"
			kick(p, reason)
			return "OK kicked %s" % p.display_name
		"ban":
			if args.is_empty():
				return "ERR usage: ban <player|token_hash|ip> [reason]"
			var reason := " ".join(args.slice(1)) if args.size() > 1 else "baneado por el administrador"
			var p := find_player(args[0])
			if p != null:
				var ip := str(Net.peers.get(p.peer_id, {}).get("ip", ""))
				manager.ban(p.token_hash, ip, reason)
				kick(p, "baneado: " + reason)
				return "OK banned %s" % p.display_name
			if args[0].is_valid_ip_address():
				manager.ban("", args[0], reason)
			else:
				manager.ban(args[0].to_lower(), "", reason)
			return "OK banned %s" % args[0]
		"unban":
			if args.is_empty():
				return "ERR usage: unban <token_hash|ip>"
			var key := args[0] if not args[0].is_valid_ip_address() else "ip:" + args[0]
			return "OK unbanned %s" % args[0] if manager.unban(key.to_lower() if not key.begins_with("ip:") else key) else "ERR not banned"
		"bans":
			var out := "OK %d" % manager.bans.size()
			for k in manager.bans:
				var e: Dictionary = manager.bans[k]
				out += "\n%s %s %s" % [k, e.get("ip", ""), e.get("reason", "")]
			return out
		"rule":
			if args.size() < 2:
				return "ERR usage: rule <key> <value>"
			return set_rule(args[0].to_lower(), args[1].to_lower())
		"pvp":
			return set_rule("pvp", args[0].to_lower() if args.size() > 0 else "")
		"ff":
			return set_rule("friendly_fire", args[0].to_lower() if args.size() > 0 else "")
		"rules":
			return "OK %s" % JSON.stringify(WorldState.instance.rules)
		"time":
			if args.is_empty() or not args[0].is_valid_float():
				return "ERR usage: time <hour>"
			WorldState.instance.set_time(WorldState.instance.day, clampf(float(args[0]), 0.0, 23.99))
			return "OK hour=%.2f" % WorldState.instance.hour
		"day":
			if args.is_empty() or not args[0].is_valid_int():
				return "ERR usage: day <n>"
			WorldState.instance.set_time(maxi(int(args[0]), 1), WorldState.instance.hour)
			return "OK day=%d" % WorldState.instance.day
		"weather":
			var weather: Weather = _world().get_node_or_null("Weather") if _world() != null else null
			if weather == null or args.is_empty():
				return "ERR usage: weather clear|blizzard [seconds]"
			match args[0]:
				"clear", "thaw":
					weather.cancel()
				"blizzard", "great_blizzard":
					weather.force_blizzard(float(args[1]) if args.size() > 1 and args[1].is_valid_float() else 120.0)
				_:
					return "ERR usage: weather clear|blizzard [seconds]"
			return "OK weather=%s" % WorldState.instance.weather
		"give":
			return give(args, from_peer)
		"tp":
			return teleport(args, from_peer)
	return "ERR unknown command '%s'" % cmd


func _world() -> World:
	return tree.get_first_node_in_group("world") as World


func find_player(who: String) -> Player:
	if who == "" or manager == null:
		return null
	for p in manager.players():
		if p.disconnected:
			continue
		if (who.is_valid_int() and p.peer_id == int(who)) or p.display_name.to_lower() == who.to_lower():
			return p
	return null


func kick(p: Player, reason: String) -> void:
	p.state.notify("Desconectado: %s" % reason, 5.0)
	Chat.instance.server_broadcast("SERVIDOR", "%s ha sido expulsado (%s)" % [p.display_name, reason])
	var peer := p.peer_id
	tree.create_timer(0.3).timeout.connect(func() -> void: Net.kick(peer, reason))


func set_rule(key: String, value: String) -> String:
	if not RULES.has(key) or value == "":
		return "ERR unknown rule (%s)" % ", ".join(RULES.keys())
	var v: Variant
	match int(RULES[key]):
		TYPE_BOOL:
			if not value in ["true", "false", "on", "off", "1", "0"]:
				return "ERR %s expects on|off" % key
			v = value in ["true", "on", "1"]
		TYPE_FLOAT:
			if not value.is_valid_float():
				return "ERR %s expects a number" % key
			v = clampf(float(value), 0.0, 4.0)
		_:
			if key == "friendly_fire" and not value in ["off", "reduced", "full"]:
				return "ERR friendly_fire expects off|reduced|full"
			v = value
	var rules := WorldState.instance.rules.duplicate()
	rules[key] = v
	WorldState.instance.set_rules(rules)
	Net.rules = rules.duplicate()
	Chat.instance.server_broadcast("SERVIDOR", "regla %s = %s" % [key, str(v)])
	return "OK %s=%s" % [key, str(v)]


func give(args: PackedStringArray, from_peer: int) -> String:
	var target: Player = null
	var rest := args
	if args.size() >= 2 and find_player(args[0]) != null and not Items.exists(StringName(args[0])):
		target = find_player(args[0])
		rest = args.slice(1)
	elif from_peer != 0:
		target = manager.player_of(from_peer)
	if target == null or rest.is_empty():
		return "ERR usage: give <player> <item> [n]"
	var id := StringName(rest[0])
	if not Items.exists(id):
		return "ERR unknown item %s" % rest[0]
	var n := clampi(int(rest[1]) if rest.size() > 1 and rest[1].is_valid_int() else 1, 1, 200)
	var left := target.state.inventory.add(id, n, true)
	return "OK gave %d %s to %s" % [n - left, id, target.display_name]


func teleport(args: PackedStringArray, from_peer: int) -> String:
	var target: Player = null
	var rest := args
	if args.size() >= 3:
		target = find_player(args[0])
		rest = args.slice(1)
	elif from_peer != 0:
		target = manager.player_of(from_peer)
	if target == null or rest.size() < 2 or not rest[0].is_valid_float() or not rest[1].is_valid_float():
		return "ERR usage: tp <player> <x> <z>"
	var pos := teleport_player(target, float(rest[0]), float(rest[1]))
	return "OK %s at %s" % [target.display_name, pos.snapped(Vector3(0.1, 0.1, 0.1))]


## Server: moves a player (the chunks under the destination are built first). Returns the final position.
static func teleport_player(p: Player, x: float, z: float, y: float = NAN) -> Vector3:
	var world := p.get_tree().get_first_node_in_group("world") as World
	var c := WorldConst.clamp_playable(x, z, 2.0)   # W1: per-axis walls (−1450 … +4420 m)
	x = c.x
	z = c.y
	world.ensure_area(Vector3(x, 0.0, z), 1)
	var pos := Vector3(x, world.get_height(x, z) + 0.3, z)
	if not is_nan(y):
		pos.y = y + 0.3   # C1: onto a floor of a building (the chunk is built by ensure_area: its colliders exist)
	p.position = pos
	p.net_position = pos
	p.velocity = Vector3.ZERO
	return pos


## Stops the server: optional final save, clients told, the store closed (WAL checkpoint), exit code 0.
func shutdown(save: bool) -> void:
	print("[ADMIN] %s: shutting down" % ("save-and-quit" if save else "quit"))
	if save:
		if Chat.instance != null and not manager.players().is_empty():
			Chat.instance.server_broadcast("SERVIDOR", "El servidor se apaga: partida guardada")
		manager.save_all()
		if manager.backend != null:
			manager.backend.log_event("shutdown", {"players": manager.players().size()})
	manager.close_backend()
	tree.create_timer(0.2).timeout.connect(func() -> void: tree.quit(0))


func status_line() -> String:
	var ws := WorldState.instance
	return "players=%d/%d day=%d hour=%.2f weather=%s pvp=%s ff=%s tick=%d out=%.1fkB/s in=%.1fkB/s uptime=%.0fs backend=%s version=%s" % [
		manager.players().size(), int(Net.cfg_get("server", "max_players", 4)), ws.day, ws.hour, ws.weather,
		ws.rules.get("pvp", false), ws.rules.get("friendly_fire", "off"), Engine.get_physics_frames(),
		float(Net.stats["out_kbps"]), float(Net.stats["in_kbps"]), Time.get_ticks_msec() / 1000.0,
		manager.backend.kind() if manager.backend != null else "none", Net.GAME_VERSION]


func stats_line() -> String:
	var zs := ZombieSystem.instance
	var w := _world()
	return "physics_ms=%.2f process_ms=%.2f zombies=%d bodies=%d chunks=%d deltas=%d mem_mb=%.0f out=%.1fkB/s in=%.1fkB/s autosaves=%d last_save_ms=%.1f" % [
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		zs.count_alive() if zs != null else 0, zs.bodies_in_use() if zs != null else 0,
		w.streamer.loaded_keys().size() if w != null and w.streamer != null else 0,
		NetWorld.instance.chunk_keys().size() if NetWorld.instance != null else 0, OS.get_static_memory_usage() / 1048576.0,
		float(Net.stats["out_kbps"]), float(Net.stats["in_kbps"]),
		manager.autosave.saves if manager.autosave != null else 0, manager.autosave.last_save_ms if manager.autosave != null else 0.0]


func db_line() -> String:
	var b := manager.backend
	var m := b.load_world_meta()
	var sq := b as SqliteBackend
	return "backend=%s path=%s schema=%d world_version=%d city_version=%d players=%d chunks=%d%s" % [b.kind(), manager.save_path,
		b.schema_version(), int(m.get("world_version", -1)), int(m.get("city_version", -1)), b.player_count(), b.chunk_keys().size(),
		" journal=%s quick_check=%s" % [sq.journal_mode(), sq.integrity] if sq != null else ""]
