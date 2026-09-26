extends Node
## Autoload `Identity`: 32-byte random token in user://identity.cfg (the server only ever stores its sha256),
## display name and recent servers (ARQ v2 §4). Client side only; harmless on the server.

const PATH := "user://identity.cfg"
const DEFAULT_NAME := "Superviviente"

var token: PackedByteArray = PackedByteArray()
var player_name: String = DEFAULT_NAME
var recent: Array = []


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		var hex := str(cfg.get_value("identity", "token", ""))
		if hex.length() == 64:
			token = hex.hex_decode()
		player_name = str(cfg.get_value("identity", "name", DEFAULT_NAME))
		recent = cfg.get_value("servers", "recent", [])
	if token.size() != 32:
		token = Crypto.new().generate_random_bytes(32)
		_save()
	# tests / headless clients can force a name from the command line; several test clients share this user://
	# directory, so such a client derives a distinct (deterministic) identity token from its name
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--name="):
			player_name = a.substr(7)
			var h := HashingContext.new()
			h.start(HashingContext.HASH_SHA256)
			h.update(("test-identity-" + player_name).to_utf8_buffer())
			token = h.finish()


func token_hex() -> String:
	return token.hex_encode()


## What the server stores and keys profiles by.
func token_hash() -> String:
	return sha256_hex(token)


static func sha256_hex(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()


func set_player_name(n: String) -> void:
	player_name = n.strip_edges().substr(0, 24)
	if player_name == "":
		player_name = DEFAULT_NAME
	_save()


func remember_server(address: String) -> void:
	recent.erase(address)
	recent.push_front(address)
	while recent.size() > 8:
		recent.pop_back()
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("identity", "token", token.hex_encode())
	cfg.set_value("identity", "name", player_name)
	cfg.set_value("servers", "recent", recent)
	cfg.save(PATH)
