class_name Chat
extends Node
## /root/Game/Chat: text chat on channel 1 (PLAN §3.2 "Chat"): `say` any_peer → sanitized, rate-limited →
## `broadcast_say` to everyone. Also carries server notices ("X se ha unido").

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
	server_broadcast(Net.name_of(peer), clean)


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
