class_name StatsComponent
extends Node
## Server-side health / warmth / hunger simulation of one player (the old player_stats.gd, GDD §5). Writes
## PlayerState and marks the owner mirror dirty whenever an integer value changes; also burns the torch.

var state: PlayerState
var player: Player
var _heat_sources: Array[HeatZone] = []
var _last_wolf_time: float = -100.0
var _warned: Dictionary = {}
var _last_ints: Dictionary = {}


func setup(s: PlayerState) -> void:
	state = s
	player = s.player


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
	if player.in_house:
		base = Balance.WARMTH_HOUSE_STOVE_ON if player.stove_on else Balance.WARMTH_HOUSE_STOVE_OFF
	else:
		base = -(Balance.WARMTH_DRAIN_NIGHT if WorldState.is_night_now() else Balance.WARMTH_DRAIN_DAY)
		if WorldState.weather_now() == &"blizzard":
			base *= Balance.BLIZZARD_WARMTH_MULT
		if player.torch_lit:
			base *= Balance.TORCH_DRAIN_MULT
		if state.has_coat:
			base *= Balance.COAT_DRAIN_MULT
	return base + heat_gain()


func _process(delta: float) -> void:
	if state == null or state.dead or player.disconnected:
		return
	if WorldState.instance != null and not WorldState.instance.running:
		return
	state.warmth = clampf(state.warmth + warmth_rate() * delta, 0.0, Balance.WARMTH_MAX)
	var hd := Balance.HUNGER_DRAIN
	if player.running:
		hd *= Balance.RUN_HUNGER_MULT
	state.hunger = clampf(state.hunger - hd * delta, 0.0, Balance.HUNGER_MAX)
	var dh := 0.0
	if state.warmth <= 0.0:
		dh -= Balance.HEALTH_LOSS_FREEZING
	if state.hunger <= 0.0:
		dh -= Balance.HEALTH_LOSS_STARVING
	if state.warmth > Balance.REGEN_MIN_STAT and state.hunger > Balance.REGEN_MIN_STAT:
		dh += Balance.HEALTH_REGEN
	state.health = clampf(state.health + dh * delta, 0.0, Balance.HEALTH_MAX)
	# movement parameters the owner predicts with
	player.can_run = state.hunger > 0.0
	player.speed_mult = Balance.FREEZING_SPEED_MULT if state.warmth < Balance.FREEZING_SLOW_BELOW else 1.0
	var is_cold := state.warmth < Balance.COLD_VIGNETTE_START
	if is_cold != player.cold:
		player.cold = is_cold
	_burn_torch(delta)
	_emit_changes()
	_check_warnings()
	if state.health <= 0.0:
		_die()


func _burn_torch(delta: float) -> void:
	if state.hand_tool() != &"antorcha":
		return
	state.torch_seconds_left -= delta
	if state.torch_seconds_left <= 0.0:
		state.torch_seconds_left = Balance.TORCH_DURATION
		state.inventory.torch_burnt()
		state.mark(&"torch")


func _emit_changes() -> void:
	var changed := false
	for pair in [[&"health", state.health], [&"warmth", state.warmth], [&"hunger", state.hunger]]:
		var key: StringName = pair[0]
		var iv := int(pair[1])
		if _last_ints.get(key, -1) != iv:
			_last_ints[key] = iv
			changed = true
	if changed:
		state.mark(&"stats")


func _warn_once(key: String, condition: bool, text: String) -> void:
	if condition:
		if not _warned.get(key, false):
			_warned[key] = true
			state.notify(text, 3.0)
	else:
		_warned[key] = false


func _check_warnings() -> void:
	_warn_once("cold", state.warmth < Balance.COLD_VIGNETTE_START, "Tienes frío")
	_warn_once("freezing", state.warmth < Balance.FREEZING_SLOW_BELOW, "Te estás congelando")
	_warn_once("hungry", state.hunger < Balance.HUNGRY_WARN, "Tienes hambre")
	_warn_once("starving", state.hunger <= 0.0, "Te mueres de hambre")


func take_damage(amount: float, source: StringName) -> void:
	if state.dead:
		return
	state.health = clampf(state.health - amount, 0.0, Balance.HEALTH_MAX)
	if source == &"lobo":
		_last_wolf_time = Time.get_ticks_msec() / 1000.0
	state.emit_sim(&"player_damaged", [amount, source])
	state.mark(&"stats")
	player.fx(&"hurt", amount)
	if state.health <= 0.0:
		_die()


func death_cause() -> StringName:
	if Time.get_ticks_msec() / 1000.0 - _last_wolf_time < 5.0:
		return &"lobo"
	if state.warmth <= 0.0:
		return &"frio"
	if state.hunger <= 0.0:
		return &"hambre"
	return &"frio"


func _die() -> void:
	if state.dead:
		return
	state.dead = true
	state.death_cause = death_cause()
	player.dead = true
	state.mark(&"dead")
	state.mark(&"stats")
	print("[EVT] player %d died (%s)" % [player.peer_id, state.death_cause])
	state.emit_sim(&"player_died", [state.death_cause])


func on_item_consumed(id: StringName) -> void:
	state.hunger = clampf(state.hunger + Items.food_delta(id, "hunger"), 0.0, Balance.HUNGER_MAX)
	state.warmth = clampf(state.warmth + Items.food_delta(id, "warmth"), 0.0, Balance.WARMTH_MAX)
	state.health = clampf(state.health + Items.food_delta(id, "health"), 0.0, Balance.HEALTH_MAX)
	_emit_changes()


## Respawn / test hook.
func revive() -> void:
	state.dead = false
	state.death_cause = &""
	state.health = Balance.HEALTH_MAX
	state.warmth = Balance.WARMTH_START
	state.hunger = Balance.HUNGER_START
	_warned.clear()
	state.mark(&"stats")


## Test hook (kept from the slice): revive in place without moving.
func debug_revive() -> void:
	revive()
	player.dead = false
	state.mark(&"dead")
