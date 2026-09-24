class_name AdminSocket
extends Node
## Localhost TCP admin socket (ARQ v2 §16.5, M1 subset). SIGTERM kills the headless server instantly, so the
## clean shutdown path is this socket: "<token>\n<command>\n" → reply lines, "END", close. Commands:
## status | players | save | save-and-quit | say <text> | time <hour> | day <n> | rule <key> <value> | quit.

const IDLE_TIMEOUT := 5.0

var port: int = Net.DEFAULT_ADMIN_PORT
var token: String = ""
var _server := TCPServer.new()
var _conns: Array[Dictionary] = []   # {"peer": StreamPeerTCP, "buf": String, "t": float, "done": bool}
var _manager: PlayerManager


func setup(manager: PlayerManager) -> void:
	_manager = manager
	port = int(Net.cfg_get("server", "admin_port", Net.DEFAULT_ADMIN_PORT))
	token = str(Net.cfg_get("server", "admin_token", ""))
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		push_warning("AdminSocket: cannot listen on 127.0.0.1:%d (%s)" % [port, error_string(err)])
	else:
		print("[ADMIN] listening TCP 127.0.0.1:%d" % port)


func _process(delta: float) -> void:
	if not _server.is_listening():
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		_conns.append({"peer": peer, "buf": "", "t": 0.0, "done": false})
	for i in range(_conns.size() - 1, -1, -1):
		var c := _conns[i]
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		c["t"] = float(c["t"]) + delta
		if bool(c["done"]):
			# give the reply a frame to flush, then close
			peer.disconnect_from_host()
			_conns.remove_at(i)
			continue
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or float(c["t"]) > IDLE_TIMEOUT:
			peer.disconnect_from_host()
			_conns.remove_at(i)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			c["buf"] = str(c["buf"]) + peer.get_utf8_string(n)
		var buf: String = c["buf"]
		if buf.count("\n") >= 2:
			var lines := buf.split("\n")
			var reply := _handle(lines[0].strip_edges(), lines[1].strip_edges())
			peer.put_data((reply + "\nEND\n").to_utf8_buffer())
			c["done"] = true


func _handle(given_token: String, line: String) -> String:
	if token != "" and given_token != token:
		return "ERR token"
	var parts := line.split(" ", false)
	if parts.is_empty():
		return "ERR empty"
	var cmd := parts[0].to_lower()
	print("[ADMIN] %s" % line)
	match cmd:
		"status":
			return "OK %s" % _status_line()
		"players":
			var out := "OK"
			for p in _manager.players():
				out += "\n%d %s %s" % [p.peer_id, p.display_name, p.global_position.snapped(Vector3(0.1, 0.1, 0.1))]
			return out
		"save":
			_manager.save_all()
			return "OK saved %s" % _manager.save_path
		"save-and-quit":
			_manager.save_all()
			print("[ADMIN] save-and-quit: shutting down")
			get_tree().create_timer(0.2).timeout.connect(func() -> void: get_tree().quit(0))
			return "OK saving and quitting"
		"quit":
			get_tree().create_timer(0.2).timeout.connect(func() -> void: get_tree().quit(0))
			return "OK quitting"
		"say":
			Chat.instance.server_broadcast("SERVIDOR", line.substr(4))
			return "OK"
		"time":
			if parts.size() >= 2:
				WorldState.instance.set_time(WorldState.instance.day, float(parts[1]))
				return "OK hour=%.2f" % WorldState.instance.hour
			return "ERR usage: time <hour>"
		"day":
			if parts.size() >= 2:
				WorldState.instance.set_time(int(parts[1]), WorldState.instance.hour)
				return "OK day=%d" % WorldState.instance.day
			return "ERR usage: day <n>"
		"rule":
			if parts.size() >= 3:
				var rules := WorldState.instance.rules.duplicate()
				var key := parts[1]
				if key == "pvp":
					rules["pvp"] = parts[2].to_lower() in ["true", "1", "on"]
				elif key == "friendly_fire":
					rules["friendly_fire"] = parts[2].to_lower()
				else:
					return "ERR unknown rule"
				WorldState.instance.set_rules(rules)
				Net.rules = rules
				return "OK %s" % str(rules)
			return "ERR usage: rule <pvp|friendly_fire> <value>"
	return "ERR unknown command"


func _status_line() -> String:
	var ws := WorldState.instance
	return "players=%d/%d day=%d hour=%.2f weather=%s pvp=%s ff=%s tick=%d out=%.1fkB/s in=%.1fkB/s uptime=%.0fs" % [
		_manager.players().size(), int(Net.cfg_get("server", "max_players", 4)), ws.day, ws.hour, ws.weather,
		ws.rules.get("pvp", false), ws.rules.get("friendly_fire", "off"), Engine.get_physics_frames(),
		float(Net.stats["out_kbps"]), float(Net.stats["in_kbps"]), Time.get_ticks_msec() / 1000.0]
