extends Node
## Run state: day/hour clock, weather flag, scene flow, best score.

const GAME_SCENE := "res://scenes/main/game.tscn"
const MENU_SCENE := "res://scenes/main/main_menu.tscn"
const BEST_PATH := "user://best.cfg"

var day: int = Balance.START_DAY
var hour: float = Balance.START_HOUR
var is_night: bool = false
var weather: StringName = &"clear"
var time_scale: float = 1.0
var is_paused: bool = false
var is_game_over: bool = false
var is_running: bool = false
var death_cause: StringName = &""
var best_days: int = 0

var _last_emitted_hour: float = -1.0


func _ready() -> void:
	_load_best()


func _process(delta: float) -> void:
	if not is_running or is_game_over or is_paused:
		return
	advance(delta * time_scale)


## Advances the clock by real seconds; rolls the day at 06:00 and checks the win.
func advance(seconds: float) -> void:
	var prev := hour
	hour += seconds * 24.0 / Balance.DAY_LENGTH_SEC
	var rolled := false
	if prev < Balance.NIGHT_END and hour >= Balance.NIGHT_END:
		rolled = true
	if hour >= 24.0:
		hour -= 24.0
		if hour >= Balance.NIGHT_END:
			rolled = true
	if rolled:
		_roll_day()
		if is_game_over:
			return
	_update_night()
	if absf(hour - _last_emitted_hour) >= 1.0 / 60.0:
		_last_emitted_hour = hour
		Events.time_changed.emit(day, hour, is_night)


func _roll_day() -> void:
	day += 1
	if day >= Balance.WIN_DAY:
		win()
		return
	Events.day_started.emit(day)
	AudioManager.play(&"day_start")


func _update_night(force_emit: bool = false) -> void:
	var n := hour >= Balance.NIGHT_START or hour < Balance.NIGHT_END
	if n != is_night or force_emit:
		is_night = n
		if n:
			Events.night_started.emit(day)


## Test/tool hook: jump to a given day and hour.
func set_time(new_day: int, new_hour: float) -> void:
	day = new_day
	hour = fmod(new_hour, 24.0)
	var was_night := is_night
	is_night = hour >= Balance.NIGHT_START or hour < Balance.NIGHT_END
	if is_night and not was_night:
		Events.night_started.emit(day)
	_last_emitted_hour = hour
	Events.time_changed.emit(day, hour, is_night)


func reset_run() -> void:
	day = Balance.START_DAY
	hour = Balance.START_HOUR
	is_night = false
	weather = &"clear"
	time_scale = 1.0
	is_paused = false
	is_game_over = false
	death_cause = &""
	_last_emitted_hour = -1.0
	Inventory.clear()


## Called by the menus: resets and loads the game scene.
func start_game() -> void:
	reset_run()
	is_running = false
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


## Called by game.gd once the game scene is on the tree.
func begin_run() -> void:
	reset_run()
	is_running = true
	get_tree().paused = false
	QuestManager.reset_for_day(day)
	Events.time_changed.emit(day, hour, is_night)


func restart() -> void:
	start_game()


func to_main_menu() -> void:
	is_running = false
	is_paused = false
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func set_paused(paused: bool) -> void:
	is_paused = paused
	get_tree().paused = paused
	Events.game_paused.emit(paused)


func days_survived() -> int:
	return maxi(day - 1, 0)


func hours_into_day() -> int:
	var h := hour - Balance.NIGHT_END
	if h < 0.0:
		h += 24.0
	return int(floor(h))


func game_over(cause: StringName) -> void:
	if is_game_over:
		return
	is_game_over = true
	death_cause = cause
	_save_best(days_survived())
	Events.game_over.emit(days_survived(), hours_into_day(), cause)
	AudioManager.play(&"player_die")


func win() -> void:
	if is_game_over:
		return
	is_game_over = true
	_save_best(days_survived())
	Events.game_won.emit(days_survived())
	AudioManager.play(&"win")


## Test hook: clear the game-over flag so the clock runs again.
func debug_revive() -> void:
	is_game_over = false
	death_cause = &""


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
