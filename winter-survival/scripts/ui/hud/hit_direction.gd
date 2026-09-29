class_name HitDirection
extends Node
## Direction of the hits taken by the local player (H3; docs/research/10_hud_ux.md appendix §6.6.6 "Daño
## direccional", §8.5 `player_hit_from`). The owner client only hears `Events.player_damaged(amount, source)` (the
## server's `_fx hurt`, without an attacker), so the direction is resolved here from what this client saw in the
## last 0.7 s, most specific first:
##   1. a shot (`Events.shot_fired`) whose ends pass within 1.6 m of the player → toward the shooter;
##   2. an attack sound (`AudioManager.event_played`: zombie_attack, wolf_bite, melee_swing / melee_stab of another
##      player) within 4 m → toward it;
##   3. the nearest zombie attacking / chasing within 4 m, or a wolf.
## Then `Events.player_hit_from(dir, amount)`: the WorldLayer draws the red arc on the ground ellipse toward the
## attacker (600 ms). No source (cold, hunger, a fall) = no arc. The offline double signal (sim + owner fx) is one hit.

const ATTACK_EVENTS := [&"zombie_attack", &"wolf_bite", &"wolf_growl", &"melee_swing", &"melee_stab", &"melee_shove"]

var emitted: int = 0
## Tests: the last resolution {dir, amount, via}.
var last: Dictionary = {}
var _clock: float = 0.0
var _last_hit: float = -10.0
var _sources: Array = []   # [{t, pos, via}]
## A hit with no source yet (the attack sound / shot may arrive a moment after the damage): [t, amount] or [].
var _pending: Array = []


func _ready() -> void:
	Events.player_damaged.connect(_on_damaged)
	Events.shot_fired.connect(_on_shot)
	if not AudioManager.event_played.is_connected(_on_sound):
		AudioManager.event_played.connect(_on_sound)


func _exit_tree() -> void:
	if AudioManager.event_played.is_connected(_on_sound):
		AudioManager.event_played.disconnect(_on_sound)


func _process(delta: float) -> void:
	_clock += delta
	while not _sources.is_empty() and _clock - float(_sources[0]["t"]) > UiTokens.HIT_SOURCE_WINDOW:
		_sources.pop_front()
	if not _pending.is_empty() and _clock - float(_pending[0]) > 0.25:
		_pending = []


func _me() -> Player:
	return GameFlow.local_player() as Player


func _on_sound(event: StringName, _voice: Node, at: Vector3) -> void:
	if at == Vector3.INF or not ATTACK_EVENTS.has(event):
		return
	var p := _me()
	if p == null:
		return
	var d := Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length()
	if d < 0.35 or d > UiTokens.HIT_MELEE_RANGE:
		return   # our own swing (at our feet) or too far to be the hit
	_sources.append({"t": _clock, "pos": at, "via": event})
	_retry()


func _on_shot(shooter_peer: int, _weapon: StringName, origin: Vector3, ends: PackedVector3Array, _flags: int) -> void:
	var p := _me()
	if p == null or shooter_peer == p.peer_id:
		return
	var me := p.global_position + Vector3(0, 1.0, 0)
	for e in ends:
		if _seg_dist(origin, e, me) <= UiTokens.HIT_SHOT_RADIUS:
			_sources.append({"t": _clock, "pos": origin, "via": &"shot"})
			_retry()
			return


static func _seg_dist(a: Vector3, b: Vector3, q: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return a.distance_to(q)
	var t := clampf((q - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_to(q)


func _on_damaged(amount: float, _source: StringName) -> void:
	if _clock - _last_hit < 0.06:
		return   # offline: the sim signal and the owner fx arrive together
	_last_hit = _clock
	var p := _me()
	if p == null:
		return
	var src := resolve(p.global_position)
	if src.is_empty():
		_pending = [_clock, amount]
		return
	_emit(p, src, amount)


func _retry() -> void:
	if _pending.is_empty():
		return
	var p := _me()
	var src := resolve(p.global_position) if p != null else {}
	if not src.is_empty():
		var amount := float(_pending[1])
		_pending = []
		_emit(p, src, amount)


func _emit(p: Player, src: Dictionary, amount: float) -> void:
	var dir: Vector3 = src["pos"] - p.global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	emitted += 1
	last = {"dir": dir.normalized(), "amount": amount, "via": src["via"]}
	Events.player_hit_from.emit(dir.normalized(), amount)


## The most likely source of a hit taken now at `me`: {pos, via} or {}.
func resolve(me: Vector3) -> Dictionary:
	# 1–2: shots and attack sounds seen in the window, the newest first (a shot beats a sound of the same moment)
	var best: Dictionary = {}
	for i in range(_sources.size() - 1, -1, -1):
		var s: Dictionary = _sources[i]
		if best.is_empty() or (s["via"] == &"shot" and best["via"] != &"shot"):
			best = s
	if not best.is_empty():
		return {"pos": best["pos"], "via": best["via"]}
	# 3: the nearest zombie attacking or chasing, or a wolf
	var bd := UiTokens.HIT_MELEE_RANGE
	var out: Dictionary = {}
	if ZombieClient.instance != null:
		for id in ZombieClient.instance.records:
			var r: ZombieClient.ZRec = ZombieClient.instance.records[id]
			if r.state != ZombieKinds.State.ATTACK and r.state != ZombieKinds.State.CHASE:
				continue
			var d := Vector2(r.render_pos.x - me.x, r.render_pos.z - me.z).length()
			if d < bd:
				bd = d
				out = {"pos": r.render_pos, "via": &"zombie"}
		if out.is_empty():
			var z := ZombieClient.instance.nearest_to(me, 3.0)
			if z != null:
				out = {"pos": z.render_pos, "via": &"zombie"}
				bd = Vector2(z.render_pos.x - me.x, z.render_pos.z - me.z).length()
	for w in get_tree().get_nodes_in_group("wolves"):
		var q := (w as Node3D).global_position
		var d := Vector2(q.x - me.x, q.z - me.z).length()
		if d < bd:
			bd = d
			out = {"pos": q, "via": &"wolf"}
	return out
