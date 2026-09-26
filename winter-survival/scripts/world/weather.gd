class_name Weather
extends Node
## Blizzard scheduler (GDD §7): hourly roll, warning, duration. Decision on the server (replicated through
## WorldState.weather); the fog/snow/wind blend runs on every client from the replicated value (ARQ v2 §13).

## Random blizzard rolls (server only; tests/screenshots turn this off for determinism).
var scheduler_enabled: bool = true

var _rng := RandomNumberGenerator.new()
var _active: bool = false
var _time_left: float = 0.0
var _warning_left: float = -1.0
var _pending_duration: float = 0.0
var _last_end_abs_hour: float = -1000.0
var _last_roll_hour: int = -1
var _blend_target: float = 0.0
var _wind_yaw: float = 0.0
var _shown_weather: StringName = &"clear"
var day_night: DayNight
var snowfall: Snowfall


func _ready() -> void:
	_rng.randomize()
	day_night = get_parent().get_node_or_null("DayNight")
	snowfall = get_parent().get_node_or_null("Snowfall")
	Events.time_changed.connect(_on_time_changed)
	Events.weather_changed.connect(_on_weather_changed)
	AudioManager.set_wind(0.2)


func _abs_hour(day: int, hour: float) -> float:
	return float(day - 1) * 24.0 + hour


func _on_time_changed(day: int, hour: float, _night: bool) -> void:
	if not Net.is_server:
		return
	var h := int(floor(hour))
	if h == _last_roll_hour:
		return
	_last_roll_hour = h
	if not scheduler_enabled or _active or _warning_left >= 0.0:
		return
	if day < Balance.BLIZZARD_FIRST_DAY or (day == Balance.BLIZZARD_FIRST_DAY and hour < Balance.BLIZZARD_FIRST_HOUR):
		return
	if _abs_hour(day, hour) - _last_end_abs_hour < Balance.BLIZZARD_MIN_GAP_HOURS:
		return
	if _rng.randf() < Balance.BLIZZARD_CHANCE_PER_HOUR:
		_start_warning(_rng.randf_range(Balance.BLIZZARD_MIN, Balance.BLIZZARD_MAX))


func _start_warning(duration: float) -> void:
	_warning_left = Balance.BLIZZARD_WARNING
	_pending_duration = duration
	Events.blizzard_warning.emit(Balance.BLIZZARD_WARNING)
	WorldState.instance.notify_all("Se acerca una ventisca…", 4.0)
	AudioManager.set_wind(0.6)


func _start(duration: float) -> void:
	_active = true
	_time_left = duration
	_warning_left = -1.0
	_wind_yaw = _rng.randf_range(0.0, TAU)
	WorldState.instance.set_weather(&"blizzard", _wind_yaw)


func _end() -> void:
	_active = false
	_last_end_abs_hour = _abs_hour(WorldState.day_now(), WorldState.hour_now())
	WorldState.instance.set_weather(&"clear", _wind_yaw)
	WorldState.instance.notify_all("La ventisca amaina", 3.0)


## Presentation (every client, offline included): follows the replicated weather.
func _on_weather_changed(w: StringName) -> void:
	_shown_weather = w
	var blizzard := w == &"blizzard"
	_blend_target = 1.0 if blizzard else 0.0
	var yaw := WorldState.instance.wind_yaw if WorldState.instance != null else _wind_yaw
	if snowfall != null:
		snowfall.set_blizzard(blizzard, yaw)
	if blizzard:
		AudioManager.set_wind(1.0)
		AudioManager.start_loop(&"wind_loop", self)
	else:
		AudioManager.set_wind(0.5 if WorldState.is_night_now() else 0.2)
		AudioManager.stop_loop(&"wind_loop", self)


## Server / test hook: start a blizzard now (skips the warning) for `seconds`.
func force_blizzard(seconds: float) -> void:
	if Net.is_server:
		_start(seconds)


## Server / test hook: clear the sky now (drops any blizzard or warning without the "amaina" notice).
func cancel() -> void:
	if not Net.is_server:
		return
	_warning_left = -1.0
	_active = false
	_time_left = 0.0
	if WorldState.instance != null:   # the main menu's decorative world has no WorldState
		WorldState.instance.set_weather(&"clear", _wind_yaw)


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if Net.is_server:
		if _warning_left >= 0.0:
			_warning_left -= delta
			if _warning_left < 0.0:
				_start(_pending_duration)
		if _active:
			_time_left -= delta
			if _time_left <= 0.0:
				_end()
	if day_night != null:
		day_night.blizzard_blend = move_toward(day_night.blizzard_blend, _blend_target, 0.5 * delta)
