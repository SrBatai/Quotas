class_name ZombieClient
extends Node3D
## Client side of the zombie replication (ARQ v2 §10.5): decodes ZombieNet's packets into records (id → kind,
## variant, state, hp %, a short buffer of timed poses) and gives the nearest ones a ZombieView from a fixed pool
## (≤ POOL; web and headless clients use fewer or none). Views are placed by interpolation between the two poses
## around `now − delay` (delay adapts to the band: ~1.2 sample periods, 100–300 ms) and animated by state and
## speed with an animation LOD (every frame < 30 m, 15 Hz < 60 m, frozen beyond). Events drive one-shots
## (attack, hit, wake), the death / knockdown poses, blood decals, noise rings and the bloater cloud; the local
## player's own hits get hitstop + camera shake (GDD §7.5). Records never spawn nodes: 200 zombies in interest
## cost 200 small objects and at most POOL views.

const POOL := 48
const POOL_WEB := 24
const POOL_HEADLESS := 16
const ASSIGN_PERIOD := 0.25
const BUFFER := 6
const DEAD_KEEP := 30.0

static var instance: ZombieClient

var records: Dictionary = {}      # id -> ZRec
var pool_size: int = POOL
var views: Array[ZombieView] = []
var free_views: Array[ZombieView] = []
var world: World
## Test hooks.
var packets: int = 0
var snap_entries: int = 0
var events: Dictionary = {}       # event code -> count
var died_ids: Dictionary = {}     # id -> true (every zombie seen dying)
var fx_count: Dictionary = {}     # fx code -> count
var _assign_t: float = 0.0


class ZRec:
	extends RefCounted
	var id: int
	var kind: int
	var variant: int
	var state: int
	var flags: int
	var hp: int = 100
	var t := PackedFloat32Array()
	var p := PackedVector3Array()
	var y := PackedFloat32Array()
	var view: ZombieView
	var speed: float = 0.0
	var render_pos: Vector3
	var render_yaw: float
	var dead_at: float = -1.0
	var interval: float = 0.1

	func push(now: float, pos: Vector3, yaw: float) -> void:
		if not t.is_empty():
			var dt := now - t[t.size() - 1]
			if dt > 0.001:
				interval = lerpf(interval, clampf(dt, 0.03, 0.4), 0.3)
		t.append(now)
		p.append(pos)
		y.append(yaw)
		while t.size() > BUFFER:
			t.remove_at(0)
			p.remove_at(0)
			y.remove_at(0)

	## Interpolated pose at `at` (clamped to the buffer; ≤ 100 ms of extrapolation).
	func sample(at: float) -> Array:
		var n := t.size()
		if n == 0:
			return [render_pos, render_yaw, 0.0]
		if n == 1 or at <= t[0]:
			return [p[0], y[0], 0.0]
		for k in range(n - 1, 0, -1):
			if t[k - 1] <= at:
				var a := t[k - 1]
				var b := t[k]
				var f := clampf((at - a) / maxf(b - a, 0.001), 0.0, 1.4)
				var pos := p[k - 1].lerp(p[k], f)
				var spd := Vector2(p[k].x - p[k - 1].x, p[k].z - p[k - 1].z).length() / maxf(b - a, 0.001)
				return [pos, lerp_angle(y[k - 1], y[k], clampf(f, 0.0, 1.0)), spd]
		return [p[n - 1], y[n - 1], 0.0]


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	name = "ZombieViews"
	top_level = true
	if OS.has_feature("web"):
		pool_size = POOL_WEB
	elif DisplayServer.get_name() == "headless":
		pool_size = 0 if Net.is_client else POOL_HEADLESS


# ------------------------------------------------------------------ packets
func on_packet(bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	packets += 1
	var now := Time.get_ticks_msec() / 1000.0
	if bytes[0] == ZombieNet.PKT_ZSNAP:
		var d := ZombieNet.decode_snapshot(bytes)
		for e in d.get("entries", []):
			var r: ZRec = records.get(int(e["id"]))
			if r == null:
				continue
			snap_entries += 1
			r.push(now, e["pos"], float(e["yaw"]))
			_set_state(r, int(e["state"]), int(e["flags"]))
	elif bytes[0] == ZombieNet.PKT_ZREL:
		for rec in ZombieNet.decode_rel(bytes):
			match int(rec["r"]):
				ZombieNet.REC_ENTER:
					var r := ZRec.new()
					r.id = int(rec["id"])
					r.kind = int(rec["kind"])
					r.variant = int(rec["variant"])
					r.hp = int(rec["hp"])
					r.render_pos = rec["pos"]
					r.render_yaw = float(rec["yaw"])
					r.push(now, rec["pos"], float(rec["yaw"]))
					var old: ZRec = records.get(r.id)
					if old != null:
						_release_view(old)
					records[r.id] = r
					_set_state(r, int(rec["state"]), int(rec["flags"]))
					if r.state == ZombieKinds.State.DEAD:
						r.dead_at = now
				ZombieNet.REC_LEAVE:
					var r: ZRec = records.get(int(rec["id"]))
					if r != null:
						_release_view(r)
						records.erase(int(rec["id"]))
				ZombieNet.REC_EVENT:
					_on_event(int(rec["id"]), int(rec["ev"]), int(rec["arg"]), float(rec["dir"]))
				ZombieNet.REC_FX:
					_on_fx(int(rec["fx"]), rec["pos"], int(rec["a"]), int(rec["b"]))


func _set_state(r: ZRec, st: int, fl: int) -> void:
	var was := r.state
	r.state = st
	r.flags = fl
	if st == ZombieKinds.State.DEAD and r.dead_at < 0.0:
		r.dead_at = Time.get_ticks_msec() / 1000.0
		died_ids[r.id] = true
	if r.view != null:
		if st == ZombieKinds.State.DEAD:
			r.view.die(r.render_yaw + PI)
		elif was == ZombieKinds.State.KNOCKED and st != ZombieKinds.State.KNOCKED:
			r.view.knock(false)
		elif st == ZombieKinds.State.CHASE and was in [ZombieKinds.State.IDLE, ZombieKinds.State.WANDER, ZombieKinds.State.INVESTIGATE]:
			r.view.play_action(&"alert")   # Zom_Alert: it has seen someone


func _on_event(id: int, ev: int, arg: int, dir: float) -> void:
	events[ev] = int(events.get(ev, 0)) + 1
	var r: ZRec = records.get(id)
	if r == null:
		return
	var v := r.view
	match ev:
		ZombieSystem.EVT_HIT, ZombieSystem.EVT_CRIT:
			r.hp = arg
			if v != null:
				v.play_action(&"hit")
			if CombatFx.instance != null:
				CombatFx.instance.blood(r.render_pos + Vector3(sin(dir), 0, cos(dir)) * 0.6, 1.1 if ev == ZombieSystem.EVT_CRIT else 0.7, dir)
			AudioManager.play(&"zombie_hit", r.render_pos)
			_local_hit_feedback(r, ev == ZombieSystem.EVT_CRIT)
		ZombieSystem.EVT_DIE:
			r.hp = 0
			r.state = ZombieKinds.State.DEAD
			if r.dead_at < 0.0:
				r.dead_at = Time.get_ticks_msec() / 1000.0
			died_ids[id] = true
			if v != null:
				v.die(dir)
			if CombatFx.instance != null:
				CombatFx.instance.blood(r.render_pos, 1.2, dir)
				if arg & 2 != 0:
					# a critical blow / a stomp burst the head (gore-lite): stump + skull fragments from HeadSocket
					var at := v.pop_head() if v != null else Transform3D(Basis.IDENTITY, r.render_pos + Vector3(0, 1.6, 0))
					CombatFx.instance.head_pop(at, Vector3(sin(dir), 0, cos(dir)))
			if arg & 1 == 0:
				AudioManager.play(&"zombie_die", r.render_pos)
			_local_hit_feedback(r, true)
		ZombieSystem.EVT_WAKE:
			if v != null and arg == 0:
				v.play_action(&"wake")
			AudioManager.play(&"frozen_wake" if arg == 0 else &"zombie_alert", r.render_pos)
		ZombieSystem.EVT_ATTACK:
			if v != null:
				v.play_action(&"attack_a" if arg == 0 else &"attack_b")
			AudioManager.play(&"zombie_attack", r.render_pos)
		ZombieSystem.EVT_STAGGER:
			if v != null:
				if arg == 1:
					v.knock(false)
				else:
					v.play_action(&"stagger")
		ZombieSystem.EVT_KNOCK:
			if v != null:
				v.knock(true, dir)
		ZombieSystem.EVT_CLOUD:
			if CombatFx.instance != null:
				CombatFx.instance.cloud(r.render_pos, float(arg))
			AudioManager.play(&"bloater_pop", r.render_pos)


func _on_fx(kind: int, pos: Vector3, a: int, _b: int) -> void:
	fx_count[kind] = int(fx_count.get(kind, 0)) + 1
	if CombatFx.instance == null:
		return
	match kind:
		ZombieNet.FX_NOISE:
			CombatFx.instance.ring(pos, float(a) / 2.0)
		ZombieNet.FX_BLOOD:
			CombatFx.instance.blood(pos, float(a) / 100.0)
		ZombieNet.FX_PLAYER_HIT:
			CombatFx.instance.blood(pos, float(a) / 100.0)
			var hurt := _player_at(pos)
			if hurt != null and hurt.view != null:
				hurt.view.visual.play_hit()
		ZombieNet.FX_CLOUD:
			CombatFx.instance.cloud(pos, float(a))


## The survivor standing at `pos` (the FX_PLAYER_HIT position is the victim's), or null.
func _player_at(pos: Vector3) -> Player:
	var best: Player = null
	var bd := 1.5
	for p in get_tree().get_nodes_in_group("player"):
		var pl := p as Player
		if pl == null:
			continue
		var d := pl.global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = pl
	return best


## The local player's swing connected (a hit on a zombie right in front of it within the last half second):
## hitstop on both (GDD §7.5: 50–80 ms, 100 ms charged / kill) and a small camera shake.
func _local_hit_feedback(r: ZRec, heavy: bool) -> void:
	var lp := GameFlow.local_player() as Player
	if lp == null or lp.view == null:
		return
	if Time.get_ticks_msec() / 1000.0 - lp.view.last_swing_t > 0.6:
		return
	if lp.global_position.distance_to(r.render_pos) > 3.0:
		return
	var stop := Balance.HITSTOP_CHARGED if heavy else Balance.HITSTOP_MELEE
	lp.view.hitstop = stop
	if r.view != null:
		r.view.hitstop = stop
	Events.camera_shake.emit(Balance.SHAKE_HIT * (1.5 if heavy else 1.0))


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var focus := _focus()
	_assign_t -= delta
	if _assign_t <= 0.0:
		_assign_t = ASSIGN_PERIOD
		_assign_views(focus, now)
	for id in records:
		var r: ZRec = records[id]
		var delay := clampf(r.interval * 1.2, 0.1, 0.3)
		var s := r.sample(now - delay)
		r.render_pos = s[0]
		r.render_yaw = float(s[1])
		r.speed = lerpf(r.speed, float(s[2]), 1.0 - exp(-10.0 * delta))
		var v := r.view
		if v == null:
			continue
		v.global_position = r.render_pos
		v.rotation.y = lerp_angle(v.rotation.y, r.render_yaw, 1.0 - exp(-12.0 * delta))
		var d := focus.distance_to(r.render_pos)
		v.anim_period = 0.0 if d < 30.0 else (1.0 / 15.0 if d < 60.0 else -1.0)
		v.set_motion(r.state, 0.0 if r.state in [ZombieKinds.State.ATTACK, ZombieKinds.State.HIT, ZombieKinds.State.DEAD] else r.speed,
			(r.flags & ZombieKinds.FLAG_TIRED) != 0)
		v.advance(delta)


func _focus() -> Vector3:
	var lp := GameFlow.local_player() as Node3D
	if lp != null and lp.is_inside_tree():
		return lp.global_position
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	return cam.global_position if cam != null else Vector3.ZERO


## Nearest records get the views (dead ones only while they are close); corpses expire after DEAD_KEEP s.
func _assign_views(focus: Vector3, now: float) -> void:
	var order: Array = []
	for id in records:
		var r: ZRec = records[id]
		if r.dead_at >= 0.0 and now - r.dead_at > DEAD_KEEP:
			_release_view(r)
			continue
		order.append([focus.distance_to(r.render_pos), r])
	order.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	var keep := {}
	for k in mini(order.size(), pool_size):
		if float(order[k][0]) > 75.0:
			break
		keep[(order[k][1] as ZRec).id] = true
	for e in order:
		var r: ZRec = e[1]
		if r.view != null and not keep.has(r.id):
			_release_view(r)
	for e in order:
		var r: ZRec = e[1]
		if keep.has(r.id) and r.view == null:
			_take_view(r)


func _take_view(r: ZRec) -> void:
	var v: ZombieView = null
	for k in free_views.size():
		if free_views[k].kind == r.kind and free_views[k].variant == r.variant:
			v = free_views[k]
			free_views.remove_at(k)
			break
	if v == null and not free_views.is_empty():
		v = free_views.pop_back()
	if v == null:
		if views.size() >= pool_size:
			return
		v = ZombieView.new()
		v.name = "zv_%d" % views.size()
		add_child(v)
		views.append(v)
	v.visible = true
	v.setup(r.kind, r.variant)
	v.reset_for_reuse()
	v.id = r.id
	v.global_position = r.render_pos
	v.rotation.y = r.render_yaw
	r.view = v
	if r.state == ZombieKinds.State.DEAD:
		v.die(r.render_yaw + PI, true)   # already on the ground
	elif r.state == ZombieKinds.State.KNOCKED:
		v.knock(true, r.render_yaw + PI)


func _release_view(r: ZRec) -> void:
	if r.view == null:
		return
	var v := r.view
	r.view = null
	v.visible = false
	v.id = 0
	free_views.append(v)


# ------------------------------------------------------------------ queries (UI, input, tests)
func record(id: int) -> ZRec:
	return records.get(id)


## Nearest living record to `p` within `r` m (cursor magnetism, GDD §7.1: 1.2 m).
func nearest_to(p: Vector3, r: float, alive_only: bool = true) -> ZRec:
	var best: ZRec = null
	var best_d := r
	for id in records:
		var z: ZRec = records[id]
		if alive_only and z.state == ZombieKinds.State.DEAD:
			continue
		var d := Vector2(z.render_pos.x - p.x, z.render_pos.z - p.z).length()
		if d <= best_d:
			best_d = d
			best = z
	return best


func count_alive() -> int:
	var n := 0
	for id in records:
		if (records[id] as ZRec).state != ZombieKinds.State.DEAD:
			n += 1
	return n


func views_in_use() -> int:
	var n := 0
	for v in views:
		if v.visible and v.id != 0:
			n += 1
	return n
