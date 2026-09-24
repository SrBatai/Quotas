class_name Weather
extends Node
## Blizzard scheduler (GDD §7): hourly roll, warning, duration, fog/snow/wind blending.

## Random blizzard rolls (tests/screenshots turn this off for determinism).
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
var day_night: DayNight
var snowfall: Snowfall


func _ready() -> void:
	_rng.randomize()
	day_night = get_parent().get_node_or_null("DayNight")
	snowfall = get_parent().get_node_or_null("Snowfall")
	Events.time_changed.connect(_on_time_changed)
	AudioManager.set_wind(0.2)


func _abs_hour(day: int, hour: float) -> float:
	return float(day - 1) * 24.0 + hour


func _on_time_changed(day: int, hour: float, _night: bool) -> void:
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
	Events.notify.emit("Se acerca una ventisca…", 4.0)
	AudioManager.set_wind(0.6)


func _start(duration: float) -> void:
	_active = true
	_time_left = duration
	_warning_left = -1.0
	_wind_yaw = _rng.randf_range(0.0, TAU)
	_blend_target = 1.0
	GameState.weather = &"blizzard"
	Events.weather_changed.emit(&"blizzard")
	if snowfall != null:
		snowfall.set_blizzard(true, _wind_yaw)
	AudioManager.set_wind(1.0)
	AudioManager.start_loop(&"wind_loop", self)


func _end() -> void:
	_active = false
	_blend_target = 0.0
	_last_end_abs_hour = _abs_hour(GameState.day, GameState.hour)
	GameState.weather = &"clear"
	Events.weather_changed.emit(&"clear")
	Events.notify.emit("La ventisca amaina", 3.0)
	if snowfall != null:
		snowfall.set_blizzard(false)
	AudioManager.set_wind(0.5 if GameState.is_night else 0.2)


## Test hook: start a blizzard now (skips the warning) for `seconds`.
func force_blizzard(seconds: float) -> void:
	_start(seconds)


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if GameState.is_game_over:
		return
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
