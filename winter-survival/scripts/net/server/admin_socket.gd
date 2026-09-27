class_name AdminSocket
extends Node
## Localhost TCP admin socket (ARQ v2 §16.5). SIGTERM kills the headless server instantly, so the clean shutdown
## path is this socket (systemd ExecStop / Docker stop hook: server/admin.sh save-and-quit): "<token>\n<command>\n"
## → reply lines, "END", close. The command set lives in AdminCommands (also reachable from the chat by admins).

const IDLE_TIMEOUT := 5.0

var port: int = Net.DEFAULT_ADMIN_PORT
var token: String = ""
var _server := TCPServer.new()
var _conns: Array[Dictionary] = []   # {"peer": StreamPeerTCP, "buf": String, "t": float, "done": bool}
var _manager: PlayerManager
var _commands: AdminCommands


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
		print("[ADMIN] rejected connection (bad token)")
		return "ERR token"
	if _commands == null:
		_commands = AdminCommands.new(get_tree(), _manager)
	return _commands.run(line, 0)
