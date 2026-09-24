class_name PlayerStats
extends Node
## Health / warmth / hunger simulation (GDD §5, ARCHITECTURE §12).

var health: float = Balance.HEALTH_MAX
var warmth: float = Balance.WARMTH_START
var hunger: float = Balance.HUNGER_START
var dead: bool = false

var _heat_sources: Array[HeatZone] = []
var _last_wolf_time: float = -100.0
var _warned: Dictionary = {}
var _last_ints: Dictionary = {}
var _player: Node


func _ready() -> void:
	_player = get_parent()
	Events.item_consumed.connect(_on_item_consumed)
	_emit_all()


func _emit_all() -> void:
	Events.stat_changed.emit(&"health", health, Balance.HEALTH_MAX)
	Events.stat_changed.emit(&"warmth", warmth, Balance.WARMTH_MAX)
	Events.stat_changed.emit(&"hunger", hunger, Balance.HUNGER_MAX)


func add_heat_source(zone: HeatZone) -> void:
	if not _heat_sources.has(zone):
		_heat_sources.append(zone)


func remove_heat_source(zone: HeatZone) -> void:
	_heat_sources.erase(zone)


func heat_gain() -> float:
	var g := 0.0
	for z in _heat_sources:
		if is_instance_valid(z) and z.active:
			g += z.gain
	return g


func warmth_rate() -> float:
	var base: float
	var in_house: bool = bool(_player.get("in_house"))
	if in_house:
		base = Balance.WARMTH_HOUSE_STOVE_ON if bool(_player.get("stove_on")) else Balance.WARMTH_HOUSE_STOVE_OFF
	else:
		base = -(Balance.WARMTH_DRAIN_NIGHT if GameState.is_night else Balance.WARMTH_DRAIN_DAY)
		if GameState.weather == &"blizzard":
			base *= Balance.BLIZZARD_WARMTH_MULT
		if bool(_player.get("torch_lit")):
			base *= Balance.TORCH_DRAIN_MULT
		if Inventory.has_coat:
			base *= Balance.COAT_DRAIN_MULT
	return base + heat_gain()


func _process(delta: float) -> void:
	if dead or GameState.is_game_over or not GameState.is_running:
		return
	warmth = clampf(warmth + warmth_rate() * delta, 0.0, Balance.WARMTH_MAX)
	var hd := Balance.HUNGER_DRAIN
	if bool(_player.get("is_running")):
		hd *= Balance.RUN_HUNGER_MULT
	hunger = clampf(hunger - hd * delta, 0.0, Balance.HUNGER_MAX)
	var dh := 0.0
	if warmth <= 0.0:
		dh -= Balance.HEALTH_LOSS_FREEZING
	if hunger <= 0.0:
		dh -= Balance.HEALTH_LOSS_STARVING
	if warmth > Balance.REGEN_MIN_STAT and hunger > Balance.REGEN_MIN_STAT:
		dh += Balance.HEALTH_REGEN
	health = clampf(health + dh * delta, 0.0, Balance.HEALTH_MAX)
	_emit_changes()
	_check_warnings()
	if health <= 0.0:
		_die()


func _emit_changes() -> void:
	for pair in [[&"health", health, Balance.HEALTH_MAX], [&"warmth", warmth, Balance.WARMTH_MAX], [&"hunger", hunger, Balance.HUNGER_MAX]]:
		var key: StringName = pair[0]
		var iv := int(pair[1])
		if _last_ints.get(key, -1) != iv:
			_last_ints[key] = iv
			Events.stat_changed.emit(key, pair[1], pair[2])


func _warn_once(key: String, condition: bool, text: String) -> void:
	if condition:
		if not _warned.get(key, false):
			_warned[key] = true
			Events.notify.emit(text, 3.0)
	else:
		_warned[key] = false


func _check_warnings() -> void:
	_warn_once("cold", warmth < Balance.COLD_VIGNETTE_START, "Tienes frío")
	_warn_once("freezing", warmth < Balance.FREEZING_SLOW_BELOW, "Te estás congelando")
	_warn_once("hungry", hunger < Balance.HUNGRY_WARN, "Tienes hambre")
	_warn_once("starving", hunger <= 0.0, "Te mueres de hambre")


func take_damage(amount: float, source: StringName) -> void:
	if dead or GameState.is_game_over:
		return
	health = clampf(health - amount, 0.0, Balance.HEALTH_MAX)
	if source == &"lobo":
		_last_wolf_time = Time.get_ticks_msec() / 1000.0
	Events.player_damaged.emit(amount, source)
	Events.stat_changed.emit(&"health", health, Balance.HEALTH_MAX)
	AudioManager.play(&"player_hurt")
	if health <= 0.0:
		_die()


func death_cause() -> StringName:
	if Time.get_ticks_msec() / 1000.0 - _last_wolf_time < 5.0:
		return &"lobo"
	if warmth <= 0.0:
		return &"frio"
	if hunger <= 0.0:
		return &"hambre"
	return &"frio"


func _die() -> void:
	if dead:
		return
	dead = true
	var cause := death_cause()
	Events.player_died.emit(cause)
	GameState.game_over(cause)


func _on_item_consumed(id: StringName) -> void:
	hunger = clampf(hunger + Items.food_delta(id, "hunger"), 0.0, Balance.HUNGER_MAX)
	warmth = clampf(warmth + Items.food_delta(id, "warmth"), 0.0, Balance.WARMTH_MAX)
	health = clampf(health + Items.food_delta(id, "health"), 0.0, Balance.HEALTH_MAX)
	_emit_changes()


## Test hook.
func debug_revive() -> void:
	dead = false
	health = Balance.HEALTH_MAX
	warmth = Balance.WARMTH_START
	hunger = Balance.HUNGER_START
	_emit_changes()
