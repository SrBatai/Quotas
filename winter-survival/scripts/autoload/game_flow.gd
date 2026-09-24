extends Node
## Autoload `GameFlow` (client side, ARQ v2 §4): menus, hosting/joining/offline start, local pause, death /
## respawn screens, the "five days" achievement and the best score. Never holds gameplay state.

const GAME_SCENE := "res://scenes/main/game.tscn"
const MENU_SCENE := "res://scenes/main/main_menu.tscn"
const BEST_PATH := "user://best.cfg"

signal local_player_changed(player: Node)
signal flow_message(text: String)

var in_game: bool = false
var is_paused: bool = false
var best_days: int = 0
var last_message: String = ""
var pending_join: Dictionary = {}
var _local_player: Node
var _won_shown: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_best()
	Net.disconnected.connect(_on_disconnected)
	Net.auth_failed.connect(func(reason: String) -> void: last_message = _auth_text(reason))
	Events.local_player_ready.connect(_on_local_player_ready)
	Events.day_started.connect(_on_day_started)


func local_player() -> Node:
	if is_instance_valid(_local_player):
		return _local_player
	return null


func local_state() -> Node:
	var p := local_player()
	return p.get_node_or_null("State") if p != null else null


func _on_local_player_ready(player: Node) -> void:
	_local_player = player
	local_player_changed.emit(player)


# ------------------------------------------------------------------ starting a game
## Whether this platform can launch the dedicated server as a child process (never on the web build).
static func can_host_process() -> bool:
	if OS.has_feature("web"):
		return false
	return not OS.get_cmdline_user_args().has("--offline")


## Whether joining a remote server is possible (ENet/UDP does not exist on the web build).
static func can_join_network() -> bool:
	return not OS.has_feature("web")


## Single player without a child process: the authoritative server logic runs in this process
## (OfflineMultiplayerPeer, unique id 1, same server components). Used by tests, the web build and as fallback.
func play_offline() -> void:
	_won_shown = false
	Net.start_offline()
	_load_game()


## "Jugar": hosts a headless dedicated server as a child process and joins it (PLAN C14). Falls back to the
## in-process local server when the child cannot be launched.
func play_solo(password: String = "") -> void:
	_won_shown = false
	if not can_host_process():
		# Web export (no processes, no UDP) or an explicit request: the authoritative server runs in-process.
		play_offline()
		return
	if not Net.host_from_game("Partida de %s" % Identity.player_name, password):
		flow_message.emit("No se pudo lanzar el servidor local; modo sin red")
		play_offline()
		return
	flow_message.emit("Arrancando el servidor local…")
	var ok: bool = await Net.wait_for_hosted_server()
	if not ok:
		Net.stop_hosted_server()
		flow_message.emit("El servidor local no responde; modo sin red")
		play_offline()
		return
	join("127.0.0.1", Net.DEFAULT_PORT, password)


## "Unirse": loads the game scene first (the spawner must exist before the server spawns us) and connects.
func join(host: String, port: int, password: String) -> void:
	_won_shown = false
	pending_join = {"host": host, "port": port, "password": password}
	Net.role = Net.Role.CLIENT
	_load_game()


## Called by game.gd on world_ready when a join is pending.
func complete_pending_join() -> void:
	if pending_join.is_empty():
		return
	var j := pending_join
	pending_join = {}
	Identity.remember_server("%s:%d" % [j["host"], int(j["port"])])
	var err := Net.join(j["host"], int(j["port"]), j["password"], Identity.player_name)
	if err != OK:
		to_main_menu("No se pudo conectar")


func _load_game() -> void:
	in_game = true
	is_paused = false
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func to_main_menu(reason: String = "") -> void:
	in_game = false
	is_paused = false
	get_tree().paused = false
	last_message = reason
	_local_player = null
	if Net.is_client:
		Net.disconnect_from_server()
	elif Net.is_offline:
		Net.disconnect_from_server()
	Net.stop_hosted_server()
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_disconnected(reason: String) -> void:
	if in_game:
		to_main_menu(_auth_text(reason))


static func _auth_text(reason: String) -> String:
	if reason.begins_with("version:"):
		return "Versión incompatible (servidor %s)" % reason.substr(8)
	match reason:
		"password": return "Contraseña incorrecta"
		"full": return "Servidor lleno"
		"server_disconnected": return "Desconectado del servidor"
		"connection_failed": return "No se pudo conectar"
		"auth_timeout": return "El servidor no respondió"
	return reason


# ------------------------------------------------------------------ pause (local; the world only stops offline)
func set_paused(paused: bool) -> void:
	is_paused = paused
	if Net.is_offline:
		get_tree().paused = paused
	Events.game_paused.emit(paused)


# ------------------------------------------------------------------ death / win
func request_respawn() -> void:
	var nw := get_tree().current_scene.get_node_or_null("NetWorld") if get_tree().current_scene != null else null
	if nw != null:
		Net.rpc_server(nw, &"request_respawn", [])


func _on_day_started(day: int) -> void:
	if in_game and Net.has_client and day >= Balance.WIN_DAY and not _won_shown:
		_won_shown = true
		var days := day - 1
		_save_best(days)
		Events.game_won.emit(days)
		AudioManager.play(&"win")


## Called when the local player dies (PlayerState mirror): keeps the best score, shows the screen via Events.
func on_local_death(cause: StringName, days: int, hours: int) -> void:
	_save_best(days)
	Events.game_over.emit(days, hours, cause)
	AudioManager.play(&"player_die")


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(BEST_PATH) == OK:
		best_days = int(cfg.get_value("score", "best_days", 0))


func _save_best(days: int) -> void:
	if days <= best_days:
		return
	best_days = days
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best_days", best_days)
	cfg.save(BEST_PATH)
