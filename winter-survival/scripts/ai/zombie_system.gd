class_name ZombieSystem
extends Node
## Server-authoritative zombies (ARQ v2 §10.3, PLAN C9, M4). Every zombie is a record in structure-of-arrays form;
## only the ones near a player (L0, < Balance.ZOMBIE_L0_RADIUS) borrow a CharacterBody3D from a fixed pool so they
## collide with the world (cabin walls, truck, trees, rocks). L1 records (< ZOMBIE_L1_RADIUS) think at 2 Hz and
## slide along their route on the height field; beyond ZOMBIE_DESPAWN_RADIUS a living record goes back into its
## chunk's population counters (PopulationManager, the L2/L3 levels).
##
## Brain (round robin: L0 every ZOMBIE_THINK_L0 ticks = 10 Hz, L1 every ZOMBIE_THINK_L1 = 2 Hz):
##   idle → wander (around home) · investigate (a SoundEvent / a heard step / a smell) · chase (seen player, then
##   its last known position for ZOMBIE_MEMORY s) · attack (wind-up → damage window → cadence) · hit / stagger /
##   knocked (reactions) · dead (corpse record for ZOMBIE_CORPSE_SECONDS) · frozen (no body, no thought; wakes by a
##   loud noise nearby, a touch or heat) · waking. Kinds (ZombieKinds): the runner bursts then tires, the crawler is
##   low and slow, the bloater leaves a freezing cloud when it dies, frozen ones are walkers ×0.8 for 30 s after
##   waking. Walkers idle outdoors at night for ZOMBIE_FREEZE_AFTER s freeze (GDD §6.4 "recicla población").
## Senses: a vision cone per kind (range by day / night / blizzard, 360° within 3 m, line of sight by one ray),
## hearing (SoundEvents + the players' gait radius), minimal smell (a downed or badly hurt player within 8 m).
## Routes come from NavQueryQueue (NavBaker's per-chunk navmesh); zombies without a route (chunk not baked yet,
## last metres) steer straight. Zombies never collide with each other or with players: a spatial hash keeps them
## ZOMBIE_SEPARATION apart and chasers stop at ZOMBIE_STOP_DIST (client prediction stays exact).
## Replication: ZombieNet reads the arrays (quantized snapshots per peer) and receives the events (hit, die, wake…).

signal zombie_died(slot: int, killer_peer: int)

const EVT_HIT := 0
const EVT_CRIT := 1
const EVT_DIE := 2
const EVT_WAKE := 4
const EVT_ATTACK := 6
const EVT_STAGGER := 7
const EVT_KNOCK := 8
const EVT_CLOUD := 9
const EVT_EXECUTE := 10

const HASH_CELL := 2.0
const HISTORY := 12                 # hit-history samples per L0 zombie (30 Hz → 0.4 s)
## L0 bodies move every `move_every` ticks with that many ticks of motion (2 = 30 Hz: halves the cost).
var move_every: int = 2
const L1_STEP := 0.5                # s between two L1 moves
const NEAR_RADIUS := 22.0           # L0 zombies closer than this to a player think / move at the full rates
## Chasers with a clear straight line (one ray at knee height, re-checked every DIRECT_RECHECK s) walk straight at
## the goal within DIRECT_RADIUS: navmesh queries cost ≈ 1–2 ms each in NavigationServer3D on a 25-chunk map, so
## routes are only asked when something (a wall, the truck, a rock) is in the way.
const DIRECT_RADIUS := 14.0
const DIRECT_RECHECK := 0.35

static var instance: ZombieSystem

var enabled: bool = true
var world: World
var nav: NavBaker
var queue := NavQueryQueue.new()
var max_records: int = Balance.ZOMBIE_MAX
var max_bodies: int = Balance.ZOMBIE_L0_MAX
var rng := RandomNumberGenerator.new()

# ---- structure of arrays (index = slot)
var used := PackedByteArray()
var kind := PackedByteArray()
var variant := PackedByteArray()
var state := PackedByteArray()
var flags := PackedByteArray()
var lod := PackedByteArray()           # 0 L0 (body) · 1 L1 · 2 out of range (despawn candidate)
var net_id := PackedInt32Array()
var pos := PackedVector3Array()
var vel := PackedVector3Array()        # desired horizontal velocity (m/s)
var yaw := PackedFloat32Array()
var hp := PackedFloat32Array()
var speed := PackedFloat32Array()      # this individual's base speed
var goal := PackedVector3Array()
var target := PackedInt32Array()       # chased player's peer id (0 none)
var last_seen := PackedVector3Array()
var mem_t := PackedFloat32Array()      # last time the target was perceived
var stim_t := PackedFloat32Array()     # last stimulus (freezing clock)
var timer := PackedFloat32Array()      # state timer (wind-up end, reaction end, wait end, corpse end)
var atk_cd := PackedFloat32Array()     # next time an attack may start
var burst_t := PackedFloat32Array()    # runner burst / tired switch time; woken frozen: end of the ×0.8 phase
var home := PackedVector3Array()
var chunk := PackedInt32Array()        # population chunk key the record belongs to
var sep := PackedVector3Array()        # separation push (m/s) computed at think time
var pdist := PackedFloat32Array()      # distance to the nearest player (LOD update, 2 Hz)
var clear_t := PackedFloat32Array()    # time of the last straight-line check toward the goal
var clear_ok := PackedByteArray()      # its result (1 = nothing in the way)
var path: Array = []                   # Array[PackedVector3Array]
var path_i := PackedInt32Array()
var path_goal := PackedVector3Array()
var path_t := PackedFloat32Array()
var body: Array = []                   # CharacterBody3D or null
var killer := PackedInt32Array()
var hist := PackedVector3Array()       # HISTORY samples per slot (L0 hit history)
var hist_t := PackedFloat32Array()     # time of each ring index (shared by every slot)
var hist_head: int = 0

var l0 := PackedInt32Array()           # slots with a body (rebuilt at the LOD update)
var l1 := PackedInt32Array()
## Records in use (living zombies + corpses); capped by max_records.
var alive_count: int = 0
var _free := PackedInt32Array()
var _next_id: int = 1
var id_slot: Dictionary = {}           # net id -> slot
var _pool: Array[CharacterBody3D] = []
var _bodies_root: Node3D
var _tick: int = 0
var _lod_t: float = 0.0
var _hash: Dictionary = {}             # cell key -> PackedInt32Array of L0 slots
var _clouds: Array = []                # bloater clouds: [pos, until]
# players of this tick (≤ 4)
var _pl: Array[Player] = []
var _pp := PackedVector3Array()
var _pgait := PackedFloat32Array()
var _pvis := PackedFloat32Array()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _move_us: int = 0
var _ray := PhysicsRayQueryParameters3D.new()
## Stats: µs of the last tick and running maxima (perf_horde), thinks / moves per tick.
var stats: Dictionary = {"tick_usec": 0, "tick_usec_max": 0, "thinks": 0, "moves": 0, "spawned": 0, "killed": 0, "frozen": 0, "woken": 0}


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	name = "ZombieSystem"
	rng.seed = 0x5EED2 ^ Time.get_ticks_usec()
	if OS.has_feature("web"):
		max_records = Balance.ZOMBIE_MAX_WEB
		max_bodies = Balance.ZOMBIE_L0_MAX_WEB
	_ray.collision_mask = 1
	_ray.hit_back_faces = false
	SoundEvents.reset()


## Server: called by game.gd once the world is configured.
func setup(p_world: World) -> void:
	world = p_world
	_bodies_root = world.get_node_or_null("Zombies") as Node3D
	if _bodies_root == null:
		_bodies_root = Node3D.new()
		_bodies_root.name = "Zombies"
		world.add_child(_bodies_root)
	nav = NavBaker.new()
	nav.name = "NavBaker"
	add_child(nav)
	nav.setup(world)
	queue.map = nav.map
	hist_t.resize(HISTORY)


# ------------------------------------------------------------------ records
func _grow(n: int) -> void:
	var old := used.size()
	if n <= old:
		return
	used.resize(n)
	kind.resize(n)
	variant.resize(n)
	state.resize(n)
	flags.resize(n)
	lod.resize(n)
	net_id.resize(n)
	pos.resize(n)
	vel.resize(n)
	yaw.resize(n)
	hp.resize(n)
	speed.resize(n)
	goal.resize(n)
	target.resize(n)
	last_seen.resize(n)
	mem_t.resize(n)
	stim_t.resize(n)
	timer.resize(n)
	atk_cd.resize(n)
	burst_t.resize(n)
	home.resize(n)
	chunk.resize(n)
	sep.resize(n)
	pdist.resize(n)
	clear_t.resize(n)
	clear_ok.resize(n)
	path_i.resize(n)
	path_goal.resize(n)
	path_t.resize(n)
	killer.resize(n)
	hist.resize(n * HISTORY)
	path.resize(n)
	body.resize(n)
	for i in range(n - 1, old - 1, -1):
		_free.append(i)
		path[i] = PackedVector3Array()


## Server: a new zombie record. Returns the slot (-1 when the table is full). `chunk_key` = the resident chunk
## (PopulationManager), -1 = the chunk under `p`, -2 = none (director visitors, debug spawns).
func spawn(k: int, p: Vector3, y: float = 0.0, st: int = ZombieKinds.State.IDLE, v: int = -1, chunk_key: int = -1) -> int:
	if not Net.is_server or alive_count >= max_records:
		return -1
	if _free.is_empty():
		_grow(mini(maxi(used.size() * 2, 64), max_records))
		if _free.is_empty():
			return -1
	var i := _free[_free.size() - 1]
	_free.resize(_free.size() - 1)
	var now := _now()
	var r := ZombieKinds.row(k)
	used[i] = 1
	kind[i] = k
	variant[i] = v if v >= 0 else rng.randi_range(0, maxi(int(r["variants"]) - 1, 0))
	state[i] = st
	flags[i] = 0
	lod[i] = 2
	while id_slot.has(_next_id) or _next_id == 0:
		_next_id = (_next_id + 1) & 0xFFFF
	net_id[i] = _next_id
	id_slot[_next_id] = i
	_next_id = (_next_id + 1) & 0xFFFF
	if world != null:
		p.y = world.get_height(p.x, p.z)
	pos[i] = p
	vel[i] = Vector3.ZERO
	yaw[i] = y
	hp[i] = float(r["hp"])
	speed[i] = float(r["speed"]) + rng.randf_range(-1.0, 1.0) * float(r["speed_var"])
	goal[i] = p
	target[i] = 0
	last_seen[i] = p
	mem_t[i] = -100.0
	stim_t[i] = now
	timer[i] = 0.0
	atk_cd[i] = 0.0
	burst_t[i] = 0.0
	home[i] = p
	chunk[i] = chunk_key if chunk_key != -1 else WorldConst.key_of(p)   # -2 = director / debug (no resident chunk)
	sep[i] = Vector3.ZERO
	path[i] = PackedVector3Array()
	path_i[i] = 0
	path_t[i] = -100.0
	body[i] = null
	killer[i] = 0
	alive_count += 1
	stats["spawned"] = int(stats["spawned"]) + 1
	if st == ZombieKinds.State.FROZEN:
		stats["frozen"] = int(stats["frozen"]) + 1
	pdist[i] = _nearest_player_dist(p)
	_assign_lod(i, pdist[i])
	return i


## Server: removes a record (despawn back into the population, or a corpse that expired).
func release(i: int) -> void:
	if i < 0 or i >= used.size() or used[i] == 0:
		return
	if ZombieNet.instance != null:
		ZombieNet.instance.on_release(i)
	_drop_body(i)
	queue.cancel(i)
	id_slot.erase(net_id[i])
	used[i] = 0
	path[i] = PackedVector3Array()
	_free.append(i)
	alive_count -= 1


func slot_of(id: int) -> int:
	return int(id_slot.get(id, -1))


func is_alive(i: int) -> bool:
	return i >= 0 and i < used.size() and used[i] == 1 and state[i] != ZombieKinds.State.DEAD


func count_alive() -> int:
	var n := 0
	for i in used.size():
		if used[i] == 1 and state[i] != ZombieKinds.State.DEAD:
			n += 1
	return n


func count_state(st: int) -> int:
	var n := 0
	for i in used.size():
		if used[i] == 1 and state[i] == st:
			n += 1
	return n


func slots() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in used.size():
		if used[i] == 1:
			out.append(i)
	return out


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ------------------------------------------------------------------ body pool (L0)
func _take_body() -> CharacterBody3D:
	if not _pool.is_empty():
		return _pool.pop_back()
	var n := 0
	for i in body.size():
		if body[i] != null:
			n += 1
	if n >= max_bodies:
		return null
	var b := CharacterBody3D.new()
	b.name = "zb_%d" % (n + _pool.size())
	b.collision_layer = 128   # zombies (ARQ v2 §17.4)
	b.collision_mask = 1      # world only: never other zombies, never players (prediction stays exact)
	b.floor_max_angle = deg_to_rad(50.0)
	b.floor_snap_length = 0.4
	b.safe_margin = 0.02
	b.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = cap
	cs.position = Vector3(0, 0.8, 0)
	b.add_child(cs)
	_bodies_root.add_child(b)
	return b


func _give_body(i: int) -> bool:
	if body[i] != null:
		return true
	var b := _take_body()
	if b == null:
		return false
	var p := pos[i]
	if world != null and not world.has_collision_at(p):
		_pool.append(b)
		return false
	b.collision_layer = 128
	b.collision_mask = 1
	var cs := b.get_node("Shape") as CollisionShape3D
	var low := kind[i] == ZombieKinds.Kind.CRAWLER
	(cs.shape as CapsuleShape3D).height = 0.7 if low else 1.6
	cs.position = Vector3(0, 0.35 if low else 0.8, 0)
	b.global_position = p + Vector3(0, 0.05, 0)
	b.velocity = Vector3.ZERO
	b.process_mode = Node.PROCESS_MODE_INHERIT
	body[i] = b
	return true


func _drop_body(i: int) -> void:
	var b: CharacterBody3D = body[i]
	if b == null:
		return
	body[i] = null
	b.collision_layer = 0
	b.collision_mask = 0
	b.global_position = Vector3(0, -500.0 - float(_pool.size()), 0)
	b.process_mode = Node.PROCESS_MODE_DISABLED
	_pool.append(b)


func bodies_in_use() -> int:
	var n := 0
	for b in body:
		if b != null:
			n += 1
	return n


# ------------------------------------------------------------------ players of the tick
func _gather_players() -> void:
	_pl.clear()
	_pp.clear()
	_pgait.clear()
	_pvis.clear()
	if world == null:
		return
	var players := world.get_node_or_null("Players")
	if players == null:
		return
	var night := WorldState.is_night_now()
	for c in players.get_children():
		var p := c as Player
		if p == null or p.dead or p.disconnected:
			continue
		_pl.append(p)
		_pp.append(p.global_position)
		_pgait.append(SoundEvents.gait_radius(p))
		var v := Vector2(p.velocity.x, p.velocity.z).length()
		var m := 1.0
		if p.crouching:
			m = 0.5
		elif v < 0.3:
			m = 0.7
		elif p.running:
			m = 1.3
		if night and p.torch_lit:
			m *= 2.0
		if p.downed:
			m *= 0.8
		_pvis.append(m)


func _nearest_player_dist(p: Vector3) -> float:
	var best := INF
	if world == null:
		return best
	var players := world.get_node_or_null("Players")
	if players == null:
		return best
	for c in players.get_children():
		if c is Player and not (c as Player).disconnected:
			var q := (c as Node3D).global_position
			best = minf(best, Vector2(q.x - p.x, q.z - p.z).length())
	return best


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	if not enabled or world == null or not Net.is_server:
		return
	var t0 := Time.get_ticks_usec()
	_tick += 1
	var now := _now()
	_gather_players()
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = Balance.ZOMBIE_LOD_PERIOD
		var l0t := Time.get_ticks_usec()
		_update_lod(now)
		stats["lod_usec"] = Time.get_ticks_usec() - l0t
	var thinks := 0
	var moves := 0
	var tp := _tick % Balance.ZOMBIE_THINK_L0
	if tp == 0:
		_rebuild_hash()
	for n in l0.size():
		var i := l0[n]
		if used[i] == 0:
			continue
		# near a player (< NEAR_RADIUS): think at 10 Hz and move at 30 Hz; the rest of L0 at half those rates
		var near_p := pdist[i] < NEAR_RADIUS
		var tp_i := Balance.ZOMBIE_THINK_L0 if near_p else Balance.ZOMBIE_THINK_L0 * 2
		if (i + _tick) % tp_i == 0:
			_think(i, now, float(tp_i) / 60.0)
			thinks += 1
		var mv_i := move_every if near_p else move_every * 2
		if (i + _tick) % mv_i == 0:
			_move_l0(i, delta * mv_i, now)
			moves += 1
	var bucket := _tick % Balance.ZOMBIE_THINK_L1
	for n in l1.size():
		var i := l1[n]
		if used[i] == 0 or i % Balance.ZOMBIE_THINK_L1 != bucket:
			continue
		_think(i, now, float(Balance.ZOMBIE_THINK_L1) / 60.0)
		_move_l1(i, float(Balance.ZOMBIE_THINK_L1) / 60.0)
		thinks += 1
	if _tick % 2 == 0:
		_record_history(now)
	queue.process(_deliver_path)
	if _tick % 30 == 0:
		_update_clouds(now)
	var us := Time.get_ticks_usec() - t0
	stats["tick_usec"] = us
	stats["move_usec"] = _move_us
	_move_us = 0
	stats["tick_usec_max"] = maxi(int(stats["tick_usec_max"]), us)
	stats["thinks"] = thinks
	stats["moves"] = moves


func _assign_lod(i: int, d: float) -> void:
	var st := state[i]
	var want := 2
	if d <= Balance.ZOMBIE_L0_RADIUS:
		want = 0
	elif d <= Balance.ZOMBIE_L1_RADIUS:
		want = 1
	# frozen and dead records never need a body (a frozen one near a player is still hit/executed by distance)
	if want == 0 and (st == ZombieKinds.State.FROZEN or st == ZombieKinds.State.DEAD):
		want = 1
	if want == 0 and body[i] == null and not _give_body(i):
		want = 1
	if want != 0 and body[i] != null:
		pos[i] = (body[i] as CharacterBody3D).global_position
		_drop_body(i)
	lod[i] = want


## 2 Hz: distance to the nearest player → L0 / L1 / out; the nearest living zombies win the bodies.
func _update_lod(now: float) -> void:
	l0.clear()
	l1.clear()
	var cand: Array = []
	for i in used.size():
		if used[i] == 0:
			continue
		var p := pos[i]
		var d := INF
		for q in _pp:
			d = minf(d, Vector2(q.x - p.x, q.z - p.z).length())
		if _pl.is_empty():
			d = _nearest_player_dist(p)
		pdist[i] = d
		if state[i] == ZombieKinds.State.DEAD:
			if now >= timer[i]:
				release(i)
				continue
			_assign_lod(i, d)
			if lod[i] <= 1:
				l1.append(i)
			continue
		if d <= Balance.ZOMBIE_L0_RADIUS and state[i] != ZombieKinds.State.FROZEN:
			cand.append([d, i])
		else:
			_assign_lod(i, d)
			if lod[i] == 1:
				l1.append(i)
	# bodies for the nearest first (a full pool leaves the farthest as L1); no sort needed while they all fit
	if cand.size() > max_bodies:
		cand.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	for c in cand:
		var i := int(c[1])
		_assign_lod(i, float(c[0]))
		if lod[i] == 0:
			l0.append(i)
		else:
			l1.append(i)


func _rebuild_hash() -> void:
	_hash.clear()
	for n in l0.size():
		var i := l0[n]
		if used[i] == 0:
			continue
		var p := pos[i]
		var k := _cell(p.x, p.z)
		var cell: PackedInt32Array = _hash.get(k, PackedInt32Array())
		cell.append(i)
		_hash[k] = cell   # packed arrays in a Dictionary are values: write back


static func _cell(x: float, z: float) -> int:
	return (int(floor(x / HASH_CELL)) + 4096) * 8192 + int(floor(z / HASH_CELL)) + 4096


## L0 slots within `r` m of `p` (spatial hash, rebuilt at 10 Hz).
func near(p: Vector3, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c0x := int(floor((p.x - r) / HASH_CELL))
	var c1x := int(floor((p.x + r) / HASH_CELL))
	var c0z := int(floor((p.z - r) / HASH_CELL))
	var c1z := int(floor((p.z + r) / HASH_CELL))
	for cx in range(c0x, c1x + 1):
		for cz in range(c0z, c1z + 1):
			var k := (cx + 4096) * 8192 + cz + 4096
			if _hash.has(k):
				for i in (_hash[k] as PackedInt32Array):
					var q := pos[i]
					if Vector2(q.x - p.x, q.z - p.z).length() <= r:
						out.append(i)
	return out


## Every living record within `r` m (L0 and L1; linear, for melee candidates and tests).
func near_any(p: Vector3, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in used.size():
		if used[i] == 0:
			continue
		var q := pos[i]
		if absf(q.x - p.x) <= r and absf(q.z - p.z) <= r and Vector2(q.x - p.x, q.z - p.z).length() <= r:
			out.append(i)
	return out


# ------------------------------------------------------------------ brain
func _set_state(i: int, st: int) -> void:
	state[i] = st


func _think(i: int, now: float, dt: float) -> void:
	var st := state[i]
	match st:
		ZombieKinds.State.DEAD:
			vel[i] = Vector3.ZERO
			return
		ZombieKinds.State.FROZEN:
			vel[i] = Vector3.ZERO
			_think_frozen(i, now)
			return
		ZombieKinds.State.WAKING, ZombieKinds.State.HIT, ZombieKinds.State.STAGGER, ZombieKinds.State.KNOCKED:
			vel[i] = Vector3.ZERO
			if now < timer[i]:
				return
			if st == ZombieKinds.State.WAKING:
				burst_t[i] = now + float(ZombieKinds.row(kind[i]).get("woken_time", 30.0))
			_set_state(i, ZombieKinds.State.CHASE if target[i] != 0 else ZombieKinds.State.INVESTIGATE)
			if st == ZombieKinds.State.KNOCKED and ZombieNet.instance != null:
				ZombieNet.instance.zevent(i, EVT_STAGGER, 1, 0)   # getting up
			st = state[i]
		ZombieKinds.State.ATTACK:
			_think_attack(i, now)
			return
	_sense(i, now)
	st = state[i]
	var r := ZombieKinds.row(kind[i])
	var spd := speed[i]
	match st:
		ZombieKinds.State.IDLE:
			vel[i] = Vector3.ZERO
			if now >= timer[i]:
				if rng.randf() < 0.55:
					var a := rng.randf() * TAU
					var d := rng.randf_range(2.0, 7.0)
					goal[i] = home[i] + Vector3(cos(a) * d, 0, sin(a) * d)
					_set_state(i, ZombieKinds.State.WANDER)
					timer[i] = now + 12.0
				else:
					timer[i] = now + rng.randf_range(3.0, 8.0)
			_maybe_freeze(i, now)
		ZombieKinds.State.WANDER:
			if _steer_to(i, goal[i], spd * 0.6, now, 1) or now >= timer[i]:
				_set_state(i, ZombieKinds.State.IDLE)
				timer[i] = now + rng.randf_range(3.0, 8.0)
				vel[i] = Vector3.ZERO
			_maybe_freeze(i, now)
		ZombieKinds.State.INVESTIGATE:
			if _dist2(pos[i], goal[i]) <= 1.2:
				vel[i] = Vector3.ZERO
				if timer[i] <= 0.0 or timer[i] > now + 60.0:
					timer[i] = now + rng.randf_range(10.0, 20.0)
				elif now >= timer[i]:
					home[i] = pos[i]
					_set_state(i, ZombieKinds.State.IDLE)
					timer[i] = now + rng.randf_range(2.0, 5.0)
			else:
				_steer_to(i, goal[i], spd * 0.85, now, 2)
		ZombieKinds.State.CHASE:
			var tp := _target_pos(i)
			var have := tp != Vector3.INF and now - mem_t[i] <= Balance.ZOMBIE_MEMORY
			if not have:
				# lost: go where it was last perceived, then wait there (GDD §6.2 "ventana de emboscada")
				target[i] = 0
				goal[i] = last_seen[i]
				_set_state(i, ZombieKinds.State.INVESTIGATE)
				timer[i] = 0.0
				return
			var chase_to: Vector3 = tp if now - mem_t[i] < 0.6 else last_seen[i]
			var d := _dist2(pos[i], tp)
			if d <= float(r["reach"]) and now >= atk_cd[i] and now - mem_t[i] < 0.6:
				_start_attack(i, now, tp)
				return
			var s := _chase_speed(i, now, spd)
			if d <= Balance.ZOMBIE_STOP_DIST:
				vel[i] = Vector3.ZERO
				_face(i, tp)
			else:
				_steer_to(i, chase_to, s, now, 0)


func _chase_speed(i: int, now: float, spd: float) -> float:
	var k := kind[i]
	if k == ZombieKinds.Kind.RUNNER:
		var r := ZombieKinds.row(k)
		if burst_t[i] <= 0.0:
			burst_t[i] = now + float(r["burst"])
			flags[i] = flags[i] & ~ZombieKinds.FLAG_TIRED
		elif now >= burst_t[i]:
			if flags[i] & ZombieKinds.FLAG_TIRED:
				flags[i] = flags[i] & ~ZombieKinds.FLAG_TIRED
				burst_t[i] = now + float(r["burst"])
			else:
				flags[i] = flags[i] | ZombieKinds.FLAG_TIRED
				burst_t[i] = now + float(r["tired"])
		return float(r["tired_speed"]) if flags[i] & ZombieKinds.FLAG_TIRED else spd
	if k == ZombieKinds.Kind.FROZEN and now < burst_t[i]:
		return spd * float(ZombieKinds.row(k)["woken_mult"]) / 0.8
	return spd


func _target_pos(i: int) -> Vector3:
	var peer := target[i]
	if peer == 0:
		return Vector3.INF
	for n in _pl.size():
		if _pl[n].peer_id == peer:
			return _pp[n]
	return Vector3.INF


func _target_player(i: int) -> Player:
	var peer := target[i]
	for p in _pl:
		if p.peer_id == peer:
			return p
	return null


static func _dist2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _face(i: int, p: Vector3) -> void:
	var d := p - pos[i]
	if Vector2(d.x, d.z).length() > 0.05:
		yaw[i] = atan2(d.x, d.z)


## Perception of the players: vision cone + line of sight, gait / SoundEvents hearing, minimal smell.
func _sense(i: int, now: float) -> void:
	var k := kind[i]
	var r := ZombieKinds.row(k)
	var p := pos[i]
	var night := WorldState.is_night_now()
	var blizzard := WorldState.weather_now() == &"blizzard"
	var vr := ZombieKinds.vision(k, night, blizzard)
	var half_cone := deg_to_rad(float(r["cone"]) * 0.5)
	var fwd := Vector2(sin(yaw[i]), cos(yaw[i]))
	var hearing := float(r["hearing"]) * (1.3 if night else 1.0)
	var chasing := state[i] == ZombieKinds.State.CHASE
	var best := -1
	var best_d := INF
	for n in _pl.size():
		var q := _pp[n]
		var dv := Vector2(q.x - p.x, q.z - p.z)
		var d := dv.length()
		if d > 45.0:
			continue
		var peer := _pl[n].peer_id
		if chasing and peer == target[i] and d <= vr * 1.3 + 2.0:
			# tracking: keep the lock while in sight (one ray at 5 Hz)
			if (i + _tick) % 12 < Balance.ZOMBIE_THINK_L0 or d <= Balance.ZOMBIE_PERIPHERAL:
				if d <= Balance.ZOMBIE_PERIPHERAL or _los(p, q):
					mem_t[i] = now
					last_seen[i] = q
			else:
				mem_t[i] = maxf(mem_t[i], now - 0.3)
				last_seen[i] = q
			stim_t[i] = now
			if d < best_d:
				best_d = d
				best = n
			continue
		var seen := false
		if d <= Balance.ZOMBIE_PERIPHERAL:
			seen = true
		elif d <= vr and absf(fwd.angle_to(dv)) <= half_cone:
			var prob := clampf(1.0 - d / vr, 0.0, 1.0) * _pvis[n] * 3.0 * float(Balance.ZOMBIE_THINK_L0) / 60.0
			seen = rng.randf() < prob + 0.05 and _los(p, q)
		elif _pl[n].downed or _pl[n].state.health < 25.0:
			seen = d <= float(r["smell"])   # smell: a bleeding survivor, no line of sight needed
		if seen and d < best_d:
			best_d = d
			best = n
		elif not seen and state[i] != ZombieKinds.State.CHASE:
			var gr := _pgait[n] * hearing
			if gr > 0.0 and d <= gr and rng.randf() < maxf(1.0 - d / gr, 0.25):
				_hear(i, q, now)
	if best >= 0:
		var was := target[i]
		target[i] = _pl[best].peer_id
		mem_t[i] = now
		last_seen[i] = _pp[best]
		stim_t[i] = now
		if state[i] != ZombieKinds.State.CHASE:
			_set_state(i, ZombieKinds.State.CHASE)
			if was == 0 and ZombieNet.instance != null:
				ZombieNet.instance.zevent(i, EVT_WAKE, 1, 0)   # "te he visto" growl
		return
	if state[i] == ZombieKinds.State.CHASE:
		return
	# SoundEvents (hits, chopping, shoves…)
	for e in SoundEvents.live(now):
		var ep: Vector3 = e["pos"]
		var er := float(e["radius"]) * hearing
		var d := _dist2(p, ep)
		if d <= er and rng.randf() < maxf(1.0 - d / er, 0.3):
			_hear(i, ep, now)
			break


func _hear(i: int, at: Vector3, now: float) -> void:
	stim_t[i] = now
	goal[i] = at + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
	timer[i] = 0.0
	if state[i] != ZombieKinds.State.INVESTIGATE:
		_set_state(i, ZombieKinds.State.INVESTIGATE)
		path_t[i] = -100.0


## Nothing solid between two ground points (a ray at knee height against the world layer: walls, trunks, rocks).
func _clear_line(a: Vector3, b: Vector3) -> bool:
	if world == null:
		return true
	_ray.from = a + Vector3(0, 0.6, 0)
	_ray.to = b + Vector3(0, 0.6, 0)
	return world.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


func _los(a: Vector3, b: Vector3) -> bool:
	if world == null:
		return true
	_ray.from = a + Vector3(0, 1.5, 0)
	_ray.to = b + Vector3(0, 1.2, 0)
	return world.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


## GDD §6.4: outdoors, night (≤ −10 °C proxy) and no stimulus for ZOMBIE_FREEZE_AFTER s → frozen.
func _maybe_freeze(i: int, now: float) -> void:
	if kind[i] != ZombieKinds.Kind.WALKER and kind[i] != ZombieKinds.Kind.FROZEN:
		return
	if not (WorldState.is_night_now() or WorldState.weather_now() == &"blizzard"):
		stim_t[i] = maxf(stim_t[i], now - Balance.ZOMBIE_FREEZE_AFTER * 0.5)
		return
	if now - stim_t[i] >= Balance.ZOMBIE_FREEZE_AFTER:
		freeze(i)


## Server: turns a walker into a frozen one (standing, no body, no thought).
func freeze(i: int) -> void:
	if not is_alive(i):
		return
	kind[i] = ZombieKinds.Kind.FROZEN
	_set_state(i, ZombieKinds.State.FROZEN)
	vel[i] = Vector3.ZERO
	target[i] = 0
	stats["frozen"] = int(stats["frozen"]) + 1
	if body[i] != null:
		pos[i] = (body[i] as CharacterBody3D).global_position
		_drop_body(i)
		lod[i] = 1


## Frozen: wakes by a loud noise nearby, a player within touch or heat (fire / torch; not at night, GDD §6.5).
func _think_frozen(i: int, now: float) -> void:
	var r := ZombieKinds.row(ZombieKinds.Kind.FROZEN)
	var p := pos[i]
	for e in SoundEvents.live(now):
		if float(e["radius"]) >= float(r["wake_noise"]) and _dist2(p, e["pos"]) <= float(r["wake_noise_dist"]):
			wake(i, e["pos"])
			return
	for n in _pl.size():
		var d := _dist2(p, _pp[n])
		# a crouched survivor can sneak up to knife range (GDD §6.1 "Silencio; ejecución con cuchillo")
		if d <= (0.6 if _pl[n].crouching else float(r["wake_touch"])):
			wake(i, _pp[n])
			return
		if not WorldState.is_night_now() and _pl[n].torch_lit and d <= float(r["wake_heat"]):
			wake(i, _pp[n])
			return
	if not WorldState.is_night_now() and (i + _tick) % 60 < Balance.ZOMBIE_THINK_L1:
		for c in get_tree().get_nodes_in_group("heat_source"):
			if c is Node3D and _dist2(p, (c as Node3D).global_position) <= float(r["wake_heat"]):
				wake(i, (c as Node3D).global_position)
				return


## SoundEvents: a loud noise wakes the frozen ones within reach at once (they do not think between events).
func on_noise(at: Vector3, radius: float) -> void:
	var r := ZombieKinds.row(ZombieKinds.Kind.FROZEN)
	if radius < float(r["wake_noise"]):
		return
	var reach := float(r["wake_noise_dist"])
	for i in used.size():
		if used[i] == 1 and state[i] == ZombieKinds.State.FROZEN:
			var p := pos[i]
			if absf(p.x - at.x) <= reach and absf(p.z - at.z) <= reach and _dist2(p, at) <= reach:
				wake(i, at)


## Server: a frozen zombie cracks awake (Zom_Wake), then investigates `toward`.
func wake(i: int, toward: Vector3) -> void:
	if not is_alive(i) or state[i] != ZombieKinds.State.FROZEN:
		return
	var now := _now()
	_set_state(i, ZombieKinds.State.WAKING)
	timer[i] = now + Balance.ZOMBIE_WAKE_TIME
	goal[i] = toward
	stim_t[i] = now
	_face(i, toward)
	stats["woken"] = int(stats["woken"]) + 1
	if ZombieNet.instance != null:
		ZombieNet.instance.zevent(i, EVT_WAKE, 0, 0)
	AudioManager.play(&"frozen_wake", pos[i])


## The damage window opens at the clip's `hit_start` (data/anim_events.json: Zom_Attack_A 0.34 s, Zom_Attack_B
## 0.40 s, the crawler's Zom_Crawl_Grab 0.30 s; Balance.ZOMBIE_ATTACK_WINDUP without the file). The client plays
## the same variant (EVT_ATTACK arg).
func _start_attack(i: int, now: float, tp: Vector3) -> void:
	_set_state(i, ZombieKinds.State.ATTACK)
	var v := rng.randi_range(0, 1)
	timer[i] = now + attack_windup(kind[i], v)
	vel[i] = Vector3.ZERO
	_face(i, tp)
	flags[i] = flags[i] & ~ZombieKinds.FLAG_TIRED
	if ZombieNet.instance != null:
		ZombieNet.instance.zevent(i, EVT_ATTACK, v, 0)


static func attack_windup(k: int, v: int) -> float:
	var clip := "Zom_Crawl_Grab" if k == ZombieKinds.Kind.CRAWLER else ("Zom_Attack_A" if v == 0 else "Zom_Attack_B")
	return AnimEvents.at(clip, "hit_start", Balance.ZOMBIE_ATTACK_WINDUP)


## Wind-up → damage window (target still within reach + 0.3 m and inside the 60° cone) → back to the chase.
func _think_attack(i: int, now: float) -> void:
	vel[i] = Vector3.ZERO
	var tp := _target_pos(i)
	if tp != Vector3.INF:
		_face(i, tp)
	if now < timer[i]:
		return
	var r := ZombieKinds.row(kind[i])
	var victim := _target_player(i)
	if victim != null and not victim.dead:
		var dv := victim.global_position - pos[i]
		var d := Vector2(dv.x, dv.z).length()
		var fwd := Vector2(sin(yaw[i]), cos(yaw[i]))
		if d <= float(r["reach"]) + 0.3 and absf(fwd.angle_to(Vector2(dv.x, dv.z))) <= deg_to_rad(Balance.ZOMBIE_ATTACK_CONE_DEG * 0.5 + 15.0):
			DamageResolver.apply(DamageResolver.ref(DamageResolver.Kind.ZOMBIE, net_id[i]),
				DamageResolver.ref(DamageResolver.Kind.PLAYER, victim.peer_id), victim, float(r["dmg"]),
				DamageResolver.DamageKind.BITE, WorldState.rules_now(), null)
	atk_cd[i] = now + float(r["cadence"])
	_set_state(i, ZombieKinds.State.CHASE)


# ------------------------------------------------------------------ movement
## Sets the desired velocity toward `to` (route when one exists, straight otherwise). True when arrived.
func _steer_to(i: int, to: Vector3, spd: float, now: float, prio: int) -> bool:
	var p := pos[i]
	var d := _dist2(p, to)
	if d <= 0.8:
		vel[i] = Vector3.ZERO
		return true
	# straight line when nothing is in the way (cheap ray), else a route (ask again when the goal moved > 2 m)
	var direct := d <= 2.5
	if not direct and d <= DIRECT_RADIUS:
		if now - clear_t[i] >= DIRECT_RECHECK:
			clear_t[i] = now
			clear_ok[i] = 1 if _clear_line(p, to) else 0
		direct = clear_ok[i] == 1
	if direct:
		if not (path[i] as PackedVector3Array).is_empty():
			path[i] = PackedVector3Array()
	else:
		var need: bool = (path[i] as PackedVector3Array).is_empty() or _dist2(path_goal[i], to) > 2.0
		if need and now - path_t[i] >= Balance.ZOMBIE_REPATH_L0 and nav != null and nav.ready_at(p):
			if queue.request(i, p, to, prio * 2 + lod[i]):
				path_t[i] = now
				path_goal[i] = to
	var wp := to
	var pth: PackedVector3Array = path[i]
	if not pth.is_empty() and not direct:
		var k := path_i[i]
		while k < pth.size() - 1 and _dist2(p, pth[k]) < 0.7:
			k += 1
		path_i[i] = k
		wp = pth[mini(k, pth.size() - 1)]
		if k >= pth.size() - 1 and _dist2(p, wp) < 0.7:
			wp = to
	var dir := Vector3(wp.x - p.x, 0.0, wp.z - p.z)
	if dir.length() < 0.01:
		vel[i] = Vector3.ZERO
		return false
	dir = dir.normalized()
	vel[i] = dir * spd + _separation(i) * 0.9
	yaw[i] = lerp_angle(yaw[i], atan2(dir.x, dir.z), 0.6)
	return false


## Push away from nearby zombies and players (no physical contact between them).
func _separation(i: int) -> Vector3:
	var p := pos[i]
	var push := Vector3.ZERO
	if lod[i] == 0:
		for j in near(p, Balance.ZOMBIE_SEPARATION):
			if j == i:
				continue
			var d := Vector3(p.x - pos[j].x, 0.0, p.z - pos[j].z)
			var l := d.length()
			if l < 0.001:
				d = Vector3(float((i % 7) - 3), 0.0, float((i % 5) - 2)).normalized()
				l = 0.001
			push += d / l * (Balance.ZOMBIE_SEPARATION - l) / Balance.ZOMBIE_SEPARATION
	for n in _pp.size():
		var d := Vector3(p.x - _pp[n].x, 0.0, p.z - _pp[n].z)
		var l := d.length()
		if l < 0.75 and l > 0.001:
			push += d / l * (0.75 - l) * 2.0
	return push


func _deliver_path(i: int, pth: PackedVector3Array) -> void:
	if i < 0 or i >= used.size() or used[i] == 0:
		return
	path[i] = pth
	# a shared route starts at another zombie: begin at the waypoint nearest to this one
	var best := 0
	var best_d := INF
	for k in pth.size():
		var d := _dist2(pos[i], pth[k])
		if d < best_d:
			best_d = d
			best = k
	path_i[i] = mini(best + 1, maxi(pth.size() - 1, 0))


## L0: the pooled body slides along vel (every MOVE_EVERY ticks with that many ticks of motion).
func _move_l0(i: int, dt: float, _now_s: float) -> void:
	var b: CharacterBody3D = body[i]
	if b == null:
		return
	var st := state[i]
	var v := vel[i]
	if st == ZombieKinds.State.DEAD or st == ZombieKinds.State.FROZEN:
		v = Vector3.ZERO
	# follow the route between two thoughts (waypoint switch without waiting for the brain)
	if v != Vector3.ZERO and not (path[i] as PackedVector3Array).is_empty():
		var pth: PackedVector3Array = path[i]
		var k := path_i[i]
		if k < pth.size() and _dist2(pos[i], pth[k]) < 0.6 and k < pth.size() - 1:
			path_i[i] = k + 1
			var wp := pth[k + 1]
			var dir := Vector3(wp.x - pos[i].x, 0.0, wp.z - pos[i].z)
			if dir.length() > 0.01:
				v = dir.normalized() * Vector2(v.x, v.z).length()
				vel[i] = v
	var m0 := Time.get_ticks_usec()
	var gy := b.velocity.y
	if b.is_on_floor():
		gy = -0.5
	else:
		gy -= _gravity * dt
	var scale := dt * 60.0   # move_and_slide integrates one physics tick
	b.velocity = Vector3(v.x * scale, gy * scale, v.z * scale)
	b.move_and_slide()
	b.velocity = Vector3(v.x, gy, v.z)
	var np := b.global_position
	if np.y < pos[i].y - 20.0:   # fell through a chunk seam: back on the ground
		np.y = world.get_height(np.x, np.z) + 0.1
		b.global_position = np
	pos[i] = np
	if v.length_squared() > 0.04:
		yaw[i] = lerp_angle(yaw[i], atan2(v.x, v.z), 0.35)
	_move_us += Time.get_ticks_usec() - m0


## L1: no body; slides along the desired velocity on the height field (2 Hz).
func _move_l1(i: int, dt: float) -> void:
	var v := vel[i]
	if v == Vector3.ZERO or state[i] == ZombieKinds.State.DEAD or state[i] == ZombieKinds.State.FROZEN:
		return
	var p := pos[i] + Vector3(v.x, 0.0, v.z) * dt
	if not WorldConst.in_playable(p.x, p.z):
		vel[i] = Vector3.ZERO
		return
	p.y = world.get_height(p.x, p.z)
	pos[i] = p


func _record_history(now: float) -> void:
	hist_head = (hist_head + 1) % HISTORY
	hist_t[hist_head] = now
	for n in l0.size():
		var i := l0[n]
		hist[i * HISTORY + hist_head] = pos[i]


## Position of slot `i` about `ago` s in the past (L0 hit history; L1 = current position).
func pos_ago(i: int, ago: float) -> Vector3:
	if lod[i] != 0 or ago <= 0.0:
		return pos[i]
	var want := _now() - ago
	var best := hist_head
	for k in HISTORY:
		var idx := (hist_head - k + HISTORY) % HISTORY
		if hist_t[idx] <= want:
			best = idx
			break
		best = idx
	var h := hist[i * HISTORY + best]
	return h if h != Vector3.ZERO else pos[i]


# ------------------------------------------------------------------ damage (DamageResolver → here)
## Server: applies damage to a zombie. `dir` = horizontal push direction. Returns true when it died.
## `pop` = a killing blow bursts the head (DIE arg bit 1: the client scales the Head bone to 0 and throws
## gore/head_fragments from HeadSocket).
func apply_damage(i: int, amount: float, attacker_peer: int, dir: Vector3, crit: bool = false, knock_chance: float = 0.0, silent: bool = false, pop: bool = false) -> bool:
	if not is_alive(i):
		return false
	var now := _now()
	hp[i] -= amount
	stim_t[i] = now
	if attacker_peer != 0:
		target[i] = attacker_peer
		mem_t[i] = now
		for n in _pl.size():
			if _pl[n].peer_id == attacker_peer:
				last_seen[i] = _pp[n]
	var dir8 := int(round(fposmod(atan2(dir.x, dir.z), TAU) / TAU * 255.0)) & 0xFF
	if hp[i] <= 0.0:
		_kill(i, attacker_peer, dir, silent, pop)
		return true
	var st := state[i]
	if st == ZombieKinds.State.FROZEN or st == ZombieKinds.State.WAKING:
		if st == ZombieKinds.State.FROZEN:
			wake(i, pos[i] - dir)
	elif st != ZombieKinds.State.KNOCKED:
		if knock_chance > 0.0 and rng.randf() < knock_chance:
			knock(i, dir)
		else:
			_set_state(i, ZombieKinds.State.HIT)
			timer[i] = now + Balance.ZOMBIE_HIT_STAGGER
			vel[i] = Vector3.ZERO
			_push(i, dir, 0.4)
	if ZombieNet.instance != null:
		ZombieNet.instance.zevent(i, EVT_CRIT if crit else EVT_HIT, clampi(int(hp[i] / ZombieKinds.max_hp(kind[i]) * 100.0), 0, 100), dir8)
	return false


## Server: knocked down (shove / heavy hit): on the ground ZOMBIE_KNOCKED_TIME s, stompable meanwhile.
func knock(i: int, dir: Vector3) -> void:
	if not is_alive(i) or state[i] == ZombieKinds.State.FROZEN:
		return
	_set_state(i, ZombieKinds.State.KNOCKED)
	timer[i] = _now() + Balance.ZOMBIE_KNOCKED_TIME
	vel[i] = Vector3.ZERO
	_push(i, dir, 0.6)
	if ZombieNet.instance != null:
		ZombieNet.instance.zevent(i, EVT_KNOCK, 0, int(round(fposmod(atan2(dir.x, dir.z), TAU) / TAU * 255.0)) & 0xFF)


## Server: held still `secs` s (a knife execution grabbed it: Act_Execute `stab`); a frozen one stays frozen.
func hold(i: int, secs: float) -> void:
	if not is_alive(i) or state[i] == ZombieKinds.State.FROZEN:
		return
	_set_state(i, ZombieKinds.State.HIT)
	timer[i] = _now() + secs
	vel[i] = Vector3.ZERO
	queue.cancel(i)


## Server: shove without knockdown: a short stagger (0.6 s) and a push.
func stagger(i: int, dir: Vector3) -> void:
	if not is_alive(i) or state[i] == ZombieKinds.State.FROZEN or state[i] == ZombieKinds.State.KNOCKED:
		return
	_set_state(i, ZombieKinds.State.STAGGER)
	timer[i] = _now() + 0.6
	vel[i] = Vector3.ZERO
	_push(i, dir, 0.5)
	if ZombieNet.instance != null:
		ZombieNet.instance.zevent(i, EVT_STAGGER, 0, 0)


func _push(i: int, dir: Vector3, dist: float) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.01:
		return
	d = d.normalized() * dist
	var b: CharacterBody3D = body[i]
	if b != null:
		b.velocity = d * 60.0
		b.move_and_slide()
		b.velocity = Vector3.ZERO
		pos[i] = b.global_position
	else:
		var p := pos[i] + d
		p.y = world.get_height(p.x, p.z) if world != null else p.y
		pos[i] = p


func _kill(i: int, killer_peer: int, dir: Vector3, silent: bool, pop: bool = false) -> void:
	var now := _now()
	_set_state(i, ZombieKinds.State.DEAD)
	hp[i] = 0.0
	vel[i] = Vector3.ZERO
	killer[i] = killer_peer
	timer[i] = now + Balance.ZOMBIE_CORPSE_SECONDS
	queue.cancel(i)
	path[i] = PackedVector3Array()
	stats["killed"] = int(stats["killed"]) + 1
	if body[i] != null:
		pos[i] = (body[i] as CharacterBody3D).global_position
		_drop_body(i)
		lod[i] = 1
	var dir8 := int(round(fposmod(atan2(dir.x, dir.z), TAU) / TAU * 255.0)) & 0xFF
	if ZombieNet.instance != null:
		ZombieNet.instance.zevent(i, EVT_DIE, (1 if silent else 0) | (2 if pop else 0), dir8)
	if kind[i] == ZombieKinds.Kind.BLOATER:
		var r := ZombieKinds.row(kind[i])
		_clouds.append([pos[i], now + float(r["cloud_time"])])
		if ZombieNet.instance != null:
			ZombieNet.instance.zevent(i, EVT_CLOUD, int(r["cloud_time"]), 0)
	if PopulationManager.instance != null:
		PopulationManager.instance.on_killed(chunk[i])
	if Director.instance != null:
		Director.instance.on_kill(pos[i], killer_peer)
	zombie_died.emit(i, killer_peer)
	AudioManager.play(&"zombie_die", pos[i])


## Bloater clouds (GDD §6.1): players inside lose warmth (Balance per second) while it lasts.
func _update_clouds(now: float) -> void:
	for c in _clouds.duplicate():
		if now >= float(c[1]):
			_clouds.erase(c)
			continue
		var r := float(ZombieKinds.row(ZombieKinds.Kind.BLOATER)["cloud_radius"])
		var w := float(ZombieKinds.row(ZombieKinds.Kind.BLOATER)["cloud_warmth"]) * 0.5
		for p in _pl:
			if _dist2(p.global_position, c[0]) <= r and p.state.stats != null:
				p.state.warmth = maxf(p.state.warmth - w, 0.0)
				p.state.mark(&"stats")


## Execution (knife on a frozen / unaware zombie, or a stomp on a knocked one): instant, optionally silent.
func execute(i: int, attacker_peer: int, dir: Vector3, silent: bool, pop: bool = false) -> void:
	if not is_alive(i):
		return
	if ZombieNet.instance != null:
		ZombieNet.instance.zevent(i, EVT_EXECUTE, 1 if silent else 0, 0)
	apply_damage(i, hp[i] + 1.0, attacker_peer, dir, false, 0.0, silent, pop)


## True when `i` does not know about the attacker (frozen or still waking, idle / wandering / investigating, knocked
## down) — knife executions.
func is_unaware(i: int, attacker_peer: int) -> bool:
	if not is_alive(i):
		return false
	var st := state[i]
	if st == ZombieKinds.State.FROZEN or st == ZombieKinds.State.WAKING:
		return true   # still stiff while it cracks awake (Zom_Wake)
	if st == ZombieKinds.State.CHASE or st == ZombieKinds.State.ATTACK:
		return target[i] != attacker_peer and target[i] != 0
	return st == ZombieKinds.State.IDLE or st == ZombieKinds.State.WANDER or st == ZombieKinds.State.INVESTIGATE or st == ZombieKinds.State.KNOCKED


# ------------------------------------------------------------------ debug / tests
## Server: `n` zombies of kind `k` on a ring of radius `r0`–`r1` around `center` (debug `/zombies`, tests).
func spawn_ring(center: Vector3, n: int, r0: float, r1: float, k: int = -1, st: int = ZombieKinds.State.IDLE) -> PackedInt32Array:
	var out := PackedInt32Array()
	for q in n:
		var a := rng.randf() * TAU
		var d := rng.randf_range(r0, r1)
		var p := center + Vector3(cos(a) * d, 0.0, sin(a) * d)
		if world != null and (not WorldConst.in_playable(p.x, p.z) or world.terrain.is_lake(p.x, p.z) and k != -2):
			continue
		var kk := k if k >= 0 else ZombieKinds.pick(rng.randf(), WorldState.day_now())
		var i := spawn(kk, p, rng.randf() * TAU, st)
		if i >= 0:
			out.append(i)
	return out


func clear_all() -> void:
	for i in used.size():
		if used[i] == 1:
			release(i)
	_clouds.clear()
