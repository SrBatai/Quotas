class_name Chat
extends Node
## /root/Game/Chat: text chat on channel 1 (PLAN §3.2 "Chat"): `say` any_peer → sanitized, rate-limited →
## `broadcast_say` to everyone. Also carries server notices ("X se ha unido") and, when `server.debug_commands`
## is enabled in server.cfg (test servers) or offline, the `/kit`, `/give <item> <n>` and `/tp <x> <z>` commands.

const MAX_HISTORY := 100

static var instance: Chat

var history: Array[Dictionary] = []
var _rate: Dictionary = {}   # peer -> Array[float]


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Client entry point (also used offline).
func send(text: String) -> void:
	var clean := sanitize(text)
	if clean == "":
		return
	Net.rpc_server(self, &"say", [clean])


static func sanitize(text: String) -> String:
	var out := ""
	for ch in text:
		var code := ch.unicode_at(0)
		if code >= 32 and code != 127:
			out += ch
	return out.strip_edges().substr(0, Balance.NET_CHAT_MAX_CHARS)


@rpc("any_peer", "call_remote", "reliable", 1)
func say(text: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := Net.sender()
	var now := Time.get_ticks_msec() / 1000.0
	var arr: Array = _rate.get(peer, [])
	while not arr.is_empty() and now - float(arr[0]) > 1.0:
		arr.pop_front()
	if arr.size() >= int(Balance.NET_CHAT_PER_SECOND):
		_rate[peer] = arr
		return
	arr.append(now)
	_rate[peer] = arr
	var clean := sanitize(text)
	if clean == "":
		return
	if clean.begins_with("/"):
		_debug_command(peer, clean)
		return
	server_broadcast(Net.name_of(peer), clean)


func debug_commands_enabled() -> bool:
	return Net.is_offline or bool(Net.cfg_get("server", "debug_commands", false))


## Server: test/debug commands; silently ignored when disabled.
func _debug_command(peer: int, line: String) -> void:
	var nw := NetWorld.instance
	var p: Player = nw._player_of(peer) if nw != null else null
	if p == null or not debug_commands_enabled():
		return
	var parts := line.split(" ", false)
	print("[CHAT] debug command from %d: %s" % [peer, line])
	match parts[0].to_lower():
		"/kit":
			p.state.inventory.add(&"hacha", 1, true)
			p.state.inventory.add(&"piedra", 6, true)
			p.state.inventory.add(&"madera", 2, true)
			p.state.notify("Kit de pruebas recibido", 2.0)
		"/give":
			if parts.size() >= 2:
				var n := int(parts[2]) if parts.size() >= 3 else 1
				p.state.inventory.add(StringName(parts[1]), clampi(n, 1, 20), true)
		"/tp":
			if parts.size() >= 3 and parts[1].is_valid_float() and parts[2].is_valid_float():
				var world := get_tree().get_first_node_in_group("world") as World
				var x := clampf(float(parts[1]), -WorldConst.WALL + 2.0, WorldConst.WALL - 2.0)
				var z := clampf(float(parts[2]), -WorldConst.WALL + 2.0, WorldConst.WALL - 2.0)
				world.ensure_area(Vector3(x, 0.0, z), 1)   # M3: the collider must exist before the body lands
				var pos := Vector3(x, world.get_height(x, z) + 0.3, z)
				p.position = pos
				p.net_position = pos
				p.velocity = Vector3.ZERO


## Server: relays a line to everybody (including the local client when offline).
func server_broadcast(who: String, text: String) -> void:
	print("[CHAT] <%s> %s" % [who, text])
	if Net.has_client:
		broadcast_say(who, text)
	Net.rpc_all(self, &"broadcast_say", [who, text])


@rpc("authority", "call_remote", "reliable", 1)
func broadcast_say(who: String, text: String) -> void:
	history.append({"who": who, "text": text, "t": Time.get_ticks_msec()})
	while history.size() > MAX_HISTORY:
		history.pop_front()
	Events.chat_message.emit(who, text)
