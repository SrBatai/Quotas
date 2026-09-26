class_name WorldState
extends Node
## Replicated world clock / weather / rules (ARQ v2 §5, §13). The server advances the clock and broadcasts a
## snapshot on every change and every NET_WORLDSTATE_SYNC_SECONDS; clients extrapolate `hour` locally.
## Node path is fixed: /root/Game/WorldState. Replaces the clock half of the old `GameState` autoload.

static var instance: WorldState

var world_seed: int = Balance.TERRAIN_SEED
var day: int = Balance.START_DAY
var hour: float = Balance.START_HOUR
var is_night: bool = false
var weather: StringName = &"clear"
var wind_yaw: float = 0.0
var time_scale: float = 1.0
var day_length: float = Balance.DAY_LENGTH_SEC
var rules: Dictionary = {"pvp": false, "friendly_fire": "off"}
## Server test hook: false freezes the clock (screenshots / perf probe).
var running: bool = true

var _last_emitted_hour: float = -1.0
var _sync_timer: float = 0.0
var _synced_once: bool = false


static func hour_now() -> float:
	return instance.hour if instance != null else Balance.START_HOUR


static func day_now() -> int:
	return instance.day if instance != null else Balance.START_DAY


static func is_night_now() -> bool:
	return instance.is_night if instance != null else false


static func weather_now() -> StringName:
	return instance.weather if instance != null else &"clear"


static func rules_now() -> Dictionary:
	return instance.rules if instance != null else {"pvp": false, "friendly_fire": "off"}


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	if Net.is_server:
		rules = Net.rules.duplicate()
		world_seed = int(Net.cfg_get("world", "seed", Balance.TERRAIN_SEED))
		day_length = float(Net.cfg_get("world", "day_length_sec", Balance.DAY_LENGTH_SEC))
		_update_night()
		_last_emitted_hour = hour
		_synced_once = true
		Net.peer_joined.connect(func(peer_id: int, _n: String) -> void: send_snapshot(peer_id))
	set_process(true)


func _process(delta: float) -> void:
	if Net.is_server:
		if running and not get_tree().paused:
			advance(delta * time_scale)
		_sync_timer += delta
		if _sync_timer >= Balance.NET_WORLDSTATE_SYNC_SECONDS:
			_sync_timer = 0.0
			send_snapshot()
	elif _synced_once:
		# local extrapolation between the 5 s snapshots
		hour += delta * time_scale * 24.0 / day_length
		if hour >= 24.0:
			hour -= 24.0
		_update_night()
		_emit_time()


## Advances the clock by real seconds; rolls the day at NIGHT_END (server).
func advance(seconds: float) -> void:
	var prev := hour
	hour += seconds * 24.0 / day_length
	var rolled := false
	if prev < Balance.NIGHT_END and hour >= Balance.NIGHT_END:
		rolled = true
	if hour >= 24.0:
		hour -= 24.0
		if hour >= Balance.NIGHT_END:
			rolled = true
	if rolled:
		_roll_day()
	_update_night()
	_emit_time()


func _roll_day() -> void:
	day += 1
	Events.day_started.emit(day)
	AudioManager.play(&"day_start")
	send_snapshot()


func _update_night() -> void:
	var n := hour >= Balance.NIGHT_START or hour < Balance.NIGHT_END
	if n != is_night:
		is_night = n
		if n:
			Events.night_started.emit(day)


func _emit_time() -> void:
	if absf(hour - _last_emitted_hour) >= 1.0 / 60.0 or _last_emitted_hour < 0.0:
		_last_emitted_hour = hour
		Events.time_changed.emit(day, hour, is_night)


## Server / test hook: jump to a given day and hour.
func set_time(new_day: int, new_hour: float) -> void:
	if not Net.is_server:
		return
	day = new_day
	hour = fmod(new_hour, 24.0)
	var was_night := is_night
	is_night = hour >= Balance.NIGHT_START or hour < Balance.NIGHT_END
	if is_night and not was_night:
		Events.night_started.emit(day)
	_last_emitted_hour = hour
	Events.time_changed.emit(day, hour, is_night)
	send_snapshot()


## Server: weather decision (Weather node) → replicated to everybody.
func set_weather(w: StringName, yaw: float = 0.0) -> void:
	if not Net.is_server:
		return
	wind_yaw = yaw
	if w != weather:
		weather = w
		Events.weather_changed.emit(weather)
	send_snapshot()


func set_rules(new_rules: Dictionary) -> void:
	if not Net.is_server:
		return
	rules = new_rules.duplicate()
	send_snapshot()


func days_survived() -> int:
	return maxi(day - 1, 0)


func hours_into_day() -> int:
	var h := hour - Balance.NIGHT_END
	if h < 0.0:
		h += 24.0
	return int(floor(h))


func snapshot() -> Dictionary:
	return {"seed": world_seed, "day": day, "hour": hour, "weather": String(weather), "wind_yaw": wind_yaw,
		"time_scale": time_scale, "day_length": day_length, "rules": rules, "running": running}


func send_snapshot(peer: int = 0) -> void:
	if not Net.is_server:
		return
	if peer == 0:
		Net.rpc_all(self, &"_apply", [snapshot()])
	else:
		Net.rpc_to(self, &"_apply", peer, [snapshot()])


@rpc("authority", "call_remote", "reliable", 1)
func _apply(d: Dictionary) -> void:
	if Net.is_server:
		return
	var old_day := day
	var old_weather := weather
	world_seed = int(d.get("seed", world_seed))
	day = int(d.get("day", day))
	hour = float(d.get("hour", hour))
	weather = StringName(str(d.get("weather", String(weather))))
	wind_yaw = float(d.get("wind_yaw", wind_yaw))
	time_scale = float(d.get("time_scale", time_scale))
	day_length = float(d.get("day_length", day_length))
	running = bool(d.get("running", true))
	rules = d.get("rules", rules)
	_synced_once = true
	if day != old_day:
		Events.day_started.emit(day)
	_update_night()
	if weather != old_weather:
		Events.weather_changed.emit(weather)
	_last_emitted_hour = -1.0
	_emit_time()


## Server → every client toast (e.g. "Se acerca una ventisca…").
func notify_all(text: String, seconds: float) -> void:
	if Net.has_client:
		Events.notify.emit(text, seconds)
	Net.rpc_all(self, &"_notify", [text, seconds])


@rpc("authority", "call_remote", "reliable", 1)
func _notify(text: String, seconds: float) -> void:
	if Net.is_server:
		return
	Events.notify.emit(text, seconds)
