class_name Director
extends Node
## Server: Director v0 (GDD v2 §6.6, ARQ v2 §10.6). Watches one intensity per player (0–1): damage taken +0.3
## (+0.5 below 30 PV), a kill within 5 m +0.1, ≥ 4 zombies within 8 m +0.15/s, downed = 1.0, no threat −0.03/s; the
## group value is the maximum. Phases: BUILD_UP (tops up the active zombies around each player to the budget,
## spawning out of view at 35–55 m, never within 15 m behind anyone; one event every 45–120 s: a wandering horde that
## walks in from the forest, or frozen ones cracking awake nearby) → PEAK (intensity ≥ 0.8 for 15 s, or 4 min of
## build-up: stops spawning) → RELIEF (intensity < 0.3: 30–45 s without spawns) → BUILD_UP.
## Budget per player zone = BASE × (1 + 0.5 (n − 1)) × day ramp, ×1.3 at night, ×0.5 in a blizzard (no hordes then),
## hard cap 60 per zone. Early days are forgiving (PLAN M4: a new player survives day 1 with the axe): day 1 in
## daylight nothing comes to the clearing; the first night sends a handful of walkers; the pressure grows by day.

enum Phase { BUILD_UP, PEAK, RELIEF }

const ZONE_RADIUS := 60.0
const SPAWN_MIN := 35.0
const SPAWN_MAX := 55.0
const ZONE_CAP := 60
const BASE := 12

static var instance: Director

var enabled: bool = true
var sys: ZombieSystem
var world: World
var phase: int = Phase.BUILD_UP
var intensity: Dictionary = {}     # peer -> 0..1
var group_intensity: float = 0.0
var events_fired: int = 0
var spawned: int = 0
var _phase_t: float = 0.0
var _high_t: float = 0.0
var _relief_until: float = 0.0
var _next_event: float = 0.0
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func setup(p_sys: ZombieSystem, p_world: World) -> void:
	sys = p_sys
	world = p_world
	name = "Director"
	_rng.randomize()
	_next_event = _now() + 90.0


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Active-zombie budget around one player for the current day / light / weather and player count.
func budget(n_players: int) -> int:
	var day := WorldState.day_now()
	var night := WorldState.is_night_now()
	var b := 0.0
	if day <= 1:
		b = 3.0 if night else 0.0
	elif day == 2:
		b = 5.0 if night else 2.0
	else:
		var ramp := minf(1.0, 0.4 + 0.15 * float(day - 1))
		b = float(BASE) * ramp * (1.3 if night else 1.0)
	b *= 1.0 + 0.5 * float(maxi(n_players, 1) - 1)
	if WorldState.weather_now() == &"blizzard":
		b *= 0.5
	b *= clampf(float(WorldState.rules_now().get("zombie_count_scale", 1.0)), 0.0, 4.0)
	if OS.has_feature("web"):
		b *= 0.6
	return mini(int(round(b)), ZONE_CAP)


func on_player_damaged(p: Player, amount: float) -> void:
	if amount <= 0.0:
		return
	var v := float(intensity.get(p.peer_id, 0.0)) + (0.5 if p.state.health < 30.0 else 0.3)
	intensity[p.peer_id] = clampf(v, 0.0, 1.0)


func on_kill(at: Vector3, killer_peer: int) -> void:
	if killer_peer == 0 or world == null:
		return
	var p := world.get_node("Players").get_node_or_null(str(killer_peer)) as Player
	if p != null and p.global_position.distance_to(at) < 5.0:
		intensity[killer_peer] = clampf(float(intensity.get(killer_peer, 0.0)) + 0.1, 0.0, 1.0)


func _process(delta: float) -> void:
	if not enabled or sys == null or world == null or not world.is_configured:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0
	var now := _now()
	var players: Array[Player] = []
	for c in world.get_node("Players").get_children():
		if c is Player and not (c as Player).dead and not (c as Player).disconnected:
			players.append(c)
	if players.is_empty():
		return
	SoundEvents.decay_heat(1.0)
	# intensities
	group_intensity = 0.0
	for p in players:
		var v := float(intensity.get(p.peer_id, 0.0))
		var close := sys.near(p.global_position, 8.0).size()
		if p.downed:
			v = 1.0
		elif close >= 4:
			v += 0.15
		elif close == 0:
			v -= 0.03
		intensity[p.peer_id] = clampf(v, 0.0, 1.0)
		group_intensity = maxf(group_intensity, float(intensity[p.peer_id]))
	# phases
	_phase_t += 1.0
	match phase:
		Phase.BUILD_UP:
			_high_t = _high_t + 1.0 if group_intensity >= 0.8 else 0.0
			if _high_t >= 15.0 or _phase_t >= 240.0:
				_set_phase(Phase.PEAK)
		Phase.PEAK:
			if group_intensity < 0.3:
				_set_phase(Phase.RELIEF)
				_relief_until = now + _rng.randf_range(30.0, 45.0)
		Phase.RELIEF:
			if now >= _relief_until:
				_set_phase(Phase.BUILD_UP)
	if phase != Phase.BUILD_UP:
		return
	var b := budget(players.size())
	if b <= 0:
		return
	for p in players:
		var active := 0
		for i in sys.near_any(p.global_position, ZONE_RADIUS):
			if sys.is_alive(i) and sys.state[i] != ZombieKinds.State.FROZEN:
				active += 1
		if (active < b and not p.in_house) or active < b / 2:
			_spawn_near(p, players, mini(b - active, 2), ZombieKinds.State.INVESTIGATE)
	if now >= _next_event:
		_next_event = now + _rng.randf_range(45.0, 120.0)
		_event(players, b)


func _set_phase(p: int) -> void:
	phase = p
	_phase_t = 0.0
	_high_t = 0.0


## Spawns up to `n` visitors out of view around `p`, walking in toward it (investigate its position).
func _spawn_near(p: Player, players: Array[Player], n: int, st: int, kind_override: int = -1) -> int:
	var made := 0
	for k in n:
		var at := _spawn_point(p, players)
		if at == Vector3.INF:
			continue
		var kd := kind_override if kind_override >= 0 else ZombieKinds.pick(_rng.randf(), WorldState.day_now(), WorldState.day_now() >= 5)
		var i := sys.spawn(kd, at, _rng.randf() * TAU, st, -1, -2)
		if i < 0:
			continue
		sys.goal[i] = p.global_position + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6))
		sys.home[i] = sys.goal[i]
		sys.stim_t[i] = _now()
		made += 1
	spawned += made
	return made


func _spawn_point(p: Player, players: Array[Player]) -> Vector3:
	for attempt in 8:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var q := p.global_position + Vector3(cos(a), 0.0, sin(a)) * d
		if not WorldConst.in_playable(q.x, q.z) or world.terrain.is_lake(q.x, q.z) or not world.has_collision_at(q):
			continue
		var ok := true
		for o in players:
			var dv := q - o.global_position
			var dist := Vector2(dv.x, dv.z).length()
			# never inside anyone's view (the camera frames ~25 m around the player) nor right behind them
			if dist < 30.0 or dist < 15.0 and o.facing().dot(dv.normalized()) < 0.0:
				ok = false
				break
		# never inside the hunter's cabin area
		if Vector2(q.x, q.z).length() < 9.0:
			ok = false
		if ok:
			return q
	return Vector3.INF


## A weighted event: a wandering horde (none in a blizzard) or frozen ones waking nearby.
func _event(players: Array[Player], b: int) -> void:
	var p: Player = players[_rng.randi() % players.size()]
	var day := WorldState.day_now()
	var blizzard := WorldState.weather_now() == &"blizzard"
	var roll := _rng.randf()
	if not blizzard and roll < 0.6 and (day >= 2 or WorldState.is_night_now()):
		var size := clampi(b / 2 + _rng.randi_range(1, 3), 2, 20) if day >= 2 else 2
		var made := _spawn_near(p, players, size, ZombieKinds.State.INVESTIGATE)
		if made > 0:
			events_fired += 1
			print("[EVT] director: wandering horde of %d toward %s (day %d)" % [made, p.display_name, day])
	else:
		var woken := 0
		for i in sys.near_any(p.global_position, 50.0):
			if woken >= 3:
				break
			if sys.is_alive(i) and sys.state[i] == ZombieKinds.State.FROZEN and sys.pos[i].distance_to(p.global_position) > 12.0:
				sys.wake(i, p.global_position)
				woken += 1
		if woken > 0:
			events_fired += 1
			print("[EVT] director: %d frozen woke near %s" % [woken, p.display_name])
