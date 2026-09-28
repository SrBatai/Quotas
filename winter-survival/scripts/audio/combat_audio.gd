class_name CombatAudio
extends Node
## Combat and player audio that hangs off existing signals / state (S1): nothing here changes gameplay.
##   anim events    AudioManager.clip_started(clip, view) — PlayerView.on_swing calls it for the owner's predicted
##                  swing and for every remote player's replicated one — schedules the table's `anim` entries at the
##                  clip's data/anim_events.json times: reload steps (magazine out / in, slide, cylinder, shells,
##                  bolt), unjam, bow draw, melee swings by weapon weight, shove, stomp, execution, throw.
##   bullet ends    Events.shot_fired (every client in reach): an impact per bullet / pellet end by material (snow,
##                  wood, metal, concrete; ends at a zombie or a player are left to their hit event), a rare ricochet
##                  on hard surfaces, the whiz of a round passing close to the listener (other shooters only).
##   arrows         Events.projectile_spawned: the arrow lands `flight` s later (snow / wood / flesh).
##   owner events   fire_result «encasquillada» → gun_jam (clients: the jam roll is on the server); loot_opened →
##                  the container (wood / metal footlocker / backpack by LootTables.model_for) and a rummage;
##                  hit_result blocked → melee_blocked.
##   players        downed (every player, 4 Hz), and the local player's breath in the cold, running breaths, shiver.
##   danger         ≥ DANGER_COUNT zombies chasing within 30 m → stinger_danger (the event's cooldown spaces them).

const DANGER_COUNT := 5
const MELEE_MEMORY := 0.7

var _swings: Array = []       # [time, position, hand item id]
var _downed: Dictionary = {}  # peer -> bool
var _poll_t: float = 0.0
var _breath_t: float = 0.0
var _run_t: float = 0.0
var _rng := RandomNumberGenerator.new()
## Tests.
var impacts: int = 0
var whizzes: int = 0
var anim_scheduled: int = 0


func _ready() -> void:
	name = "CombatAudio"
	_rng.randomize()
	Events.shot_fired.connect(_on_shot)
	Events.projectile_spawned.connect(_on_projectile)
	Events.fire_result.connect(_on_fire_result)
	Events.loot_opened.connect(_on_loot)
	Events.hit_result.connect(func(_v: int, blocked: bool, _r: String) -> void:
		if blocked:
			AudioManager.play(&"melee_blocked", AudioManager.listener_position()))


## A clip started on a player view (owner or remote): schedule its sounds.
func clip_started(clip: StringName, source: Node, from: float = 0.0) -> void:
	var map: Dictionary = AudioManager.table.anim.get(String(clip), {})
	if map.is_empty():
		return
	var hand := &""
	var pl: Player = source.get("player") as Player if source != null else null
	if pl != null:
		hand = StringName(str(pl.hand_tool))
	var pos := (source as Node3D).global_position if source is Node3D else AudioManager.listener_position()
	for k: String in map:
		var ev := StringName(str(map[k]))
		var t := float(k.substr(1)) if k.begins_with("@") else AnimEvents.at(String(clip), k, -1.0)
		if t < 0.0 or t < from - 0.001:
			continue
		t -= from
		var opts := {}
		if ev == &"melee_swing":
			opts["hand"] = hand
			if clip == &"Melee_Charged":
				opts["weight"] = &"heavy"
				opts["volume_db"] = 2.0
			_swings.append([Time.get_ticks_msec() / 1000.0 + t, pos, hand])
			if _swings.size() > 16:
				_swings.pop_front()
		AudioManager.schedule(ev, t, source as Node3D if source is Node3D else null, pos, opts)
		anim_scheduled += 1


## The hand item of a melee swing that connected near `at` in the last MELEE_MEMORY s, or null.
func recent_melee(at: Vector3) -> Variant:
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(_swings.size() - 1, -1, -1):
		var s: Array = _swings[i]
		if now - float(s[0]) < MELEE_MEMORY + 0.3 and (s[1] as Vector3).distance_to(at) < 3.5:
			return s[2]
	return null


func _on_shot(shooter: int, weapon: StringName, origin: Vector3, ends: PackedVector3Array, _flags: int) -> void:
	if Firearms.is_bow(weapon):
		return
	var lpos := AudioManager.listener_position()
	var local := shooter == Net.local_peer_id()
	var zc := ZombieClient.instance
	var n := 0
	for e in ends:
		if e.distance_to(lpos) > 45.0:
			continue
		n += 1
		if n > 4:   # a shotgun's 12 pellets: 4 impacts are plenty
			break
		if zc != null and zc.nearest_to(e, 0.9) != null:
			continue
		if _player_near(e, 0.9):
			continue
		var mat := AudioManager.impact_material(e)
		var delay := origin.distance_to(e) / 700.0
		AudioManager.schedule(StringName("impact_" + String(mat)), delay, null, e, {})
		impacts += 1
		if (mat == &"metal" or mat == &"concrete") and _rng.randf() < 0.12:
			AudioManager.schedule(&"ricochet", delay + 0.02, null, e, {})
	if not local and not ends.is_empty():
		var q := Geometry3D.get_closest_point_to_segment(lpos, origin, ends[0])
		if q.distance_to(lpos) < 3.0 and origin.distance_to(lpos) > 4.0:
			AudioManager.play(&"bullet_whiz", q)
			whizzes += 1


func _player_near(p: Vector3, r: float) -> bool:
	for n in get_tree().get_nodes_in_group("player"):
		var pl := n as Node3D
		if pl != null and pl.global_position.distance_to(p) < r + 0.8 and absf(pl.global_position.y + 1.0 - p.y) < 1.5:
			return true
	return false


func _on_projectile(kind: int, _from: Vector3, to: Vector3, flight: float, _shooter: int) -> void:
	if kind != Projectiles.Kind.ARROW:
		return
	var zc := ZombieClient.instance
	var hit_z := zc != null and zc.nearest_to(to, 1.0) != null
	var mat := &"flesh" if hit_z else AudioManager.impact_material(to)
	if mat == &"concrete" or mat == &"metal":
		mat = &"wood"
	AudioManager.schedule(StringName("impact_" + String(mat)), maxf(flight, 0.05), null, to, {"volume_db": -5.0})


func _on_fire_result(_seq: int, ok: bool, reason: String, _hits: int, _kills: int, _crit: bool) -> void:
	if not ok and reason == "encasquillada":
		AudioManager.play(&"gun_jam", AudioManager.listener_position())


func _on_loot(_wid: int, table: StringName, _items: int) -> void:
	var at := AudioManager.listener_position()
	var model := LootTables.model_for(table, false)
	var ev := &"container_open_wood"
	if model == "footlocker":
		ev = &"container_open_metal"
	elif model == "backpack":
		ev = &"container_rummage"
	AudioManager.play(ev, at)
	if ev != &"container_rummage":
		AudioManager.schedule(&"container_rummage", 0.35, null, at, {})


func _process(delta: float) -> void:
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = 0.25
		_poll_players()
	var lp := GameFlow.local_player() as Player
	if lp == null or lp.dead:
		return
	# breath: running (after 3 s of it) and the cold puffs outside at night / in a blizzard; shiver when cold
	var moving := Vector2(lp.velocity.x, lp.velocity.z).length() > 3.0
	_run_t = _run_t + delta if lp.running and moving else 0.0
	_breath_t -= delta
	if _breath_t <= 0.0:
		if _run_t > 3.0:
			AudioManager.play(&"player_breath_run")
			_breath_t = _rng.randf_range(0.65, 0.8)
		elif not lp.in_house and (WorldState.is_night_now() or WorldState.weather_now() == &"blizzard"):
			AudioManager.play(&"player_breath_cold")
			_breath_t = _rng.randf_range(3.5, 5.5)
		else:
			_breath_t = 1.0
		if lp.cold and _rng.randf() < 0.25:
			AudioManager.play(&"player_shiver")


func _poll_players() -> void:
	var chasing := 0
	var lpos := AudioManager.listener_position()
	for n in get_tree().get_nodes_in_group("player"):
		var pl := n as Player
		if pl == null:
			continue
		var was := bool(_downed.get(pl.peer_id, pl.downed))
		_downed[pl.peer_id] = pl.downed
		if pl.downed and not was and not pl.dead:
			if pl.is_local:
				AudioManager.play(&"player_downed", pl.global_position)
			else:
				AudioManager.play(&"player_downed", pl.global_position)
				AudioManager.play(&"ui_mate_down")
	var zc := ZombieClient.instance
	if zc != null:
		for id in zc.records:
			var r: ZombieClient.ZRec = zc.records[id]
			if r.state == ZombieKinds.State.CHASE and r.render_pos.distance_to(lpos) < 30.0:
				chasing += 1
				if chasing >= DANGER_COUNT:
					AudioManager.play(&"stinger_danger")
					break
