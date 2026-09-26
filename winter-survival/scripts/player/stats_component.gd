class_name StatsComponent
extends Node
## Server-side health / warmth / hunger / stamina simulation of one player (the old player_stats.gd, GDD v2 §5).
## Writes PlayerState and marks the owner mirror dirty whenever an integer value changes; also burns the torch.
## M4 (GDD v2 §12.2, ARQ v2 §11.5): combat damage at 0 health DOWNS the player (crawl 0.8 m/s, bleed-out 60 s /
## 40 s when cold, each bite −5 s, a teammate revives by holding interact 4 s → 30 PV and "Malherido" ×0.85 for
## 5 min); the third down between rests (dawn, until beds exist), bleeding out or giving up kills. Alone on the
## server the player gets up by itself once per day after SOLO_GETUP_TIME. Cold and hunger kill directly (nobody
## can "revive" a frozen body). Death leaves a lootable corpse with the whole inventory (StructureSpawner kind
## "corpse") and allows a respawn at the cabin's bed after RESPAWN_DELAY s.

## Test hook: seconds a dead player waits before `request_respawn` is accepted (Balance.RESPAWN_DELAY).
static var respawn_delay: float = Balance.RESPAWN_DELAY
## Test hook: seconds a lone downed player waits before getting up by itself (Balance.SOLO_GETUP_TIME).
static var solo_getup_time: float = Balance.SOLO_GETUP_TIME

var state: PlayerState
var player: Player
var _heat_sources: Array[HeatZone] = []
var _last_wolf_time: float = -100.0
var _warned: Dictionary = {}
var _last_ints: Dictionary = {}
var _run_blocked: bool = false
var _downs: int = 0
var _down_day: int = -1
var _solo_day: int = -1
var _bleed_left: float = 0.0
var _down_t: float = 0.0
var _hurt_until: float = 0.0
var _last_hit_t: float = -100.0
var _last_source: StringName = &""
var _last_attacker: String = ""
## Time of death (s): request_respawn is refused before respawn_delay has passed.
var died_at: float = -100.0


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
	if player.downed:
		dh = minf(dh, 0.0)
	state.health = clampf(state.health + dh * delta, 0.0, Balance.HEALTH_MAX)
	_stamina(delta)
	# movement parameters the owner predicts with
	var run_ok := state.hunger > 0.0 and not _run_blocked and not player.downed
	if player.can_run != run_ok:
		player.can_run = run_ok
	var mult := Balance.FREEZING_SPEED_MULT if state.warmth < Balance.FREEZING_SLOW_BELOW else 1.0
	if Time.get_ticks_msec() / 1000.0 < _hurt_until:
		mult *= Balance.HURT_SPEED_MULT
	if not is_equal_approx(player.speed_mult, mult):
		player.speed_mult = mult
	var is_cold := state.warmth < Balance.COLD_VIGNETTE_START
	if is_cold != player.cold:
		player.cold = is_cold
	_burn_torch(delta)
	if player.downed:
		_downed_tick(delta)
	_emit_changes()
	_check_warnings()
	if state.health <= 0.0 and not player.downed and not state.dead:
		# cold / hunger (combat damage downs the player in take_damage)
		_die()


## GDD v2 §5 "Aguante": running drains, standing / walking regenerates; below STAMINA_MIN_RUN no running and no
## charged swings until STAMINA_RESUME_RUN.
func _stamina(delta: float) -> void:
	var v := Vector2(player.velocity.x, player.velocity.z).length()
	if player.running and v > 0.5:
		state.stamina -= Balance.STAMINA_RUN_DRAIN * delta
	elif v < 0.3:
		state.stamina += Balance.STAMINA_REGEN_IDLE * delta
	else:
		state.stamina += Balance.STAMINA_REGEN_WALK * delta
	state.stamina = clampf(state.stamina, 0.0, Balance.STAMINA_MAX)
	if _run_blocked and state.stamina >= Balance.STAMINA_RESUME_RUN:
		_run_blocked = false
	elif not _run_blocked and state.stamina < Balance.STAMINA_MIN_RUN:
		_run_blocked = true


## Server: spends stamina for an action; false (nothing spent) when there is not enough.
func spend_stamina(amount: float, need_min: float = 0.0) -> bool:
	if state.stamina < maxf(amount * 0.5, need_min):
		return false
	state.stamina = maxf(state.stamina - amount, 0.0)
	state.mark(&"stats")
	return true


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
	for pair in [[&"health", state.health], [&"warmth", state.warmth], [&"hunger", state.hunger], [&"stamina", state.stamina]]:
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


func take_damage(amount: float, source: StringName, attacker_name: String = "") -> void:
	if state.dead or amount <= 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	_last_hit_t = now
	_last_source = source
	_last_attacker = attacker_name
	if source == &"lobo":
		_last_wolf_time = now
	if player.revive_by != 0:
		cancel_revive("daño")
	if player.downed:
		# bites on a downed survivor shorten the bleed-out (GDD §12.2)
		_bleed_left -= Balance.ZOMBIE_BITE_BLEED
		player.fx(&"hurt", amount)
		return
	state.health = clampf(state.health - amount, 0.0, Balance.HEALTH_MAX)
	state.emit_sim(&"player_damaged", [amount, source])
	state.mark(&"stats")
	player.fx(&"hurt", amount)
	if Director.instance != null:
		Director.instance.on_player_damaged(player, amount)
	if state.health <= 0.0:
		go_down()


## Server: health reached 0 from combat damage → downed (or dead on the third down).
func go_down() -> void:
	if state.dead or player.downed:
		return
	var day := WorldState.day_now()
	if day != _down_day:
		_down_day = day
		_downs = 0   # "entre descansos": beds arrive later, dawn resets the counter until then
	_downs += 1
	if _downs > Balance.DOWNED_MAX:
		_die()
		return
	player.downed = true
	_bleed_left = Balance.DOWNED_BLEED_COLD if state.warmth < 30.0 else Balance.DOWNED_BLEED
	_down_t = 0.0
	state.health = 0.0
	state.mark(&"stats")
	state.mark(&"dead")
	player.bleed = int(ceil(_bleed_left))
	print("[EVT] player %d downed (%d/%d, bleed %.0f s)" % [player.peer_id, _downs, Balance.DOWNED_MAX, _bleed_left])
	state.notify("¡Estás derribado! Aguanta hasta que te reanimen", 4.0)
	player.fx(&"shake", Balance.SHAKE_HURT)


func _downed_tick(delta: float) -> void:
	_bleed_left -= delta
	_down_t += delta
	var b := int(ceil(maxf(_bleed_left, 0.0)))
	if b != player.bleed:
		player.bleed = b
	if _bleed_left <= 0.0:
		_die()
		return
	# alone on the server: get up once per day (GDD "Solo")
	if _down_t >= solo_getup_time and _solo_day != WorldState.day_now() and _alone():
		_solo_day = WorldState.day_now()
		print("[EVT] player %d gets up alone" % player.peer_id)
		revive(null)


func _alone() -> bool:
	var n := 0
	for p in get_tree().get_nodes_in_group("player"):
		if p is Player and not (p as Player).disconnected and not (p as Player).dead:
			n += 1
	return n <= 1


## Server: back on the feet with REVIVE_HEALTH and "Malherido" (by a teammate, or alone once a day).
func revive(by: Player) -> void:
	if not player.downed or state.dead:
		return
	player.downed = false
	player.revive_by = 0
	player.revive_pct = 0
	player.bleed = 0
	state.health = Balance.REVIVE_HEALTH
	_hurt_until = Time.get_ticks_msec() / 1000.0 + Balance.HURT_SECONDS
	state.mark(&"stats")
	state.mark(&"dead")
	print("[EVT] player %d revived by %s" % [player.peer_id, by.peer_id if by != null else "self"])
	state.notify("Te han reanimado · Malherido" if by != null else "Te levantas a duras penas · Malherido", 3.0)
	if by != null:
		by.state.notify("Has reanimado a %s" % player.display_name, 2.5)


func cancel_revive(_why: String) -> void:
	player.revive_by = 0
	player.revive_pct = 0


## Server: "Rendirse" (hold X): a downed player dies now.
func give_up() -> void:
	if player.downed and not state.dead:
		_last_source = &"rendirse"
		_die()


func death_cause() -> StringName:
	var now := Time.get_ticks_msec() / 1000.0
	if _last_source == &"rendirse":
		return &"rendirse"
	if now - _last_hit_t < 90.0 and (player.downed or now - _last_hit_t < 5.0):
		if _last_source in [&"zombi", &"lobo", &"jugador"]:
			return _last_source
	if now - _last_wolf_time < 5.0:
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
	player.downed = false
	player.revive_by = 0
	player.revive_pct = 0
	player.bleed = 0
	state.health = 0.0
	died_at = Time.get_ticks_msec() / 1000.0
	state.mark(&"dead")
	state.mark(&"stats")
	print("[EVT] player %d died (%s)" % [player.peer_id, state.death_cause])
	state.emit_sim(&"player_died", [state.death_cause])
	player.drop_corpse()


func on_item_consumed(id: StringName) -> void:
	state.hunger = clampf(state.hunger + Items.food_delta(id, "hunger"), 0.0, Balance.HUNGER_MAX)
	state.warmth = clampf(state.warmth + Items.food_delta(id, "warmth"), 0.0, Balance.WARMTH_MAX)
	state.health = clampf(state.health + Items.food_delta(id, "health"), 0.0, Balance.HEALTH_MAX)
	_emit_changes()


## Respawn (after death) / test hook: fresh stats (GDD §12.2: warmth 60 after a death).
func reset_stats(after_death: bool = false) -> void:
	state.dead = false
	state.death_cause = &""
	state.health = Balance.HEALTH_MAX
	state.warmth = 60.0 if after_death else Balance.WARMTH_START
	state.hunger = Balance.HUNGER_START
	state.stamina = Balance.STAMINA_MAX
	player.downed = false
	player.bleed = 0
	_last_source = &""
	_run_blocked = false
	_hurt_until = 0.0
	_warned.clear()
	state.mark(&"stats")


func can_respawn() -> bool:
	return state.dead and Time.get_ticks_msec() / 1000.0 - died_at >= respawn_delay


## Test hook (kept from the slice): revive in place without moving.
func debug_revive() -> void:
	reset_stats()
	player.dead = false
	state.mark(&"dead")
