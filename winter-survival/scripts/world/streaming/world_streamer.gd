class_name WorldStreamer
extends Node
## Chunk streaming (ARQ v2 §8.5, PLAN C7 / M3). Keeps the chunks around the focus loaded:
##   client / offline / menu: ring 1 (3 × 3) full + ring 2 (5 × 5) prefetched around the local player (or the
##     camera / a tool's focus); the focus moves one chunk ahead when |v| > 8 m/s (car / teleport walks).
##   dedicated server: union of every player's ring 1 = HOT, ring 2 = WARM; a chunk with no player within
##     HIBERNATE_RADIUS chunks for HIBERNATE_SECONDS hibernates (NetWorld saves its ChunkDelta, then it is freed).
## Generation (heights, scatter, AO, mesh arrays, MultiMesh buffers) runs in WorkerThreadPool tasks (ChunkJob);
## the main thread only instantiates, in small WorldChunk steps, within STREAM_BUDGET_USEC per frame (the step
## that would overrun is left for the next frame). `ensure_loaded` builds synchronously (spawn, teleport).

enum Mode { CLIENT, SERVER, OFFLINE, DECORATIVE }

signal chunk_loaded(key: int)
signal chunk_unloaded(key: int)

const LOOKAHEAD_SPEED := 8.0
const UNLOAD_MARGIN := 1
## Safety margin on the per-step cost estimate (EMA) so the step that closes a frame rarely overruns the budget.
const STEP_MARGIN_USEC := 250
## A chunk built by `ensure_loaded` is kept this long even when the desired set (refreshed every 0.2 s, and the
## focus that moves right after a teleport) does not include it yet: otherwise it is unloaded and rebuilt at once.
const SYNC_PIN_SECONDS := 2.0

var mode: int = Mode.OFFLINE
var visual: bool = true
var with_nodes: bool = true
var hf: HeightFunction
var clearing: Array = []
var static_occ: Array = []
var chunks_root: Node3D
var enabled: bool = false
## Tools / screenshots: stream around this point instead of the player (Vector3.INF = off) and with this radius.
var focus_override: Vector3 = Vector3.INF
var ring_prefetch: int = WorldConst.RING_PREFETCH
var budget_usec: int = WorldConst.STREAM_BUDGET_USEC
var max_tasks: int = 2
## Tools (perf_walk --cpu): build the client's visual data (meshes, MultiMeshes) even on the headless dummy
## renderer, to measure the streaming CPU cost without a (software) GPU competing for the cores.
static var force_visual: bool = false
## Tools: behave as the web nothreads build (chunk generation on the main thread, one per refresh).
static var force_no_threads: bool = false

var chunks: Dictionary = {}        # key -> WorldChunk (building or loaded)
var _jobs: Dictionary = {}         # key -> ChunkJob in flight
var _ready_jobs: Array[ChunkJob] = []
var _building: Array[WorldChunk] = []
var _dying: Array[WorldChunk] = []    # unloaded chunks being freed a few nodes per frame
var _desired: Dictionary = {}      # key -> priority (lower first)
var _last_near: Dictionary = {}    # server: key -> last time a player was within HIBERNATE_RADIUS (s)
var _pinned: Dictionary = {}       # key -> time (s) until which a synchronously loaded chunk is not unloaded
var _focus_keys: Array[int] = []
var _refresh_t: float = 0.0
## Main-thread µs spent this frame (streaming cost, PLAN M3 budget) and running stats.
var frame_usec: int = 0
## [refresh, collect, instantiate, unload] µs of the last frame + the last step kind (perf tools).
var last_phases: Array = []
var _last_step_kind: String = ""
var stats: Dictionary = {"generated": 0, "gen_usec": 0, "gen_usec_max": 0, "loaded": 0, "unloaded": 0,
	"hibernated": 0, "sync_loads": 0, "frame_usec_max": 0, "step_usec_max": 0, "over_budget_frames": 0, "steps": 0, "steps_over_budget": 0}
var _step_costs: Dictionary = {}   # step kind -> EMA µs (budget planning)


func setup(p_mode: int, p_hf: HeightFunction, p_clearing: Array, p_static_occ: Array, root: Node3D) -> void:
	mode = p_mode
	hf = p_hf
	clearing = p_clearing
	static_occ = p_static_occ
	chunks_root = root
	visual = mode != Mode.SERVER and (DisplayServer.get_name() != "headless" or force_visual)
	with_nodes = mode != Mode.DECORATIVE
	max_tasks = clampi(OS.get_processor_count() - 1, 1, 3) if OS.get_processor_count() > 1 else 1
	enabled = true
	if not Quality.preset_changed.is_connected(_on_quality):
		Quality.preset_changed.connect(_on_quality)


func _on_quality(_p: StringName) -> void:
	for k in chunks:
		(chunks[k] as WorldChunk).apply_quality()


func _exit_tree() -> void:
	# never leave a task running against a freed streamer
	for k in _jobs:
		var j: ChunkJob = _jobs[k]
		j.cancelled = true
		if j.task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(j.task_id)
	_jobs.clear()


# ------------------------------------------------------------------ queries
func chunk_at(x: float, z: float) -> WorldChunk:
	return chunks.get(WorldConst.key(WorldConst.chunk_of(x), WorldConst.chunk_of(z)))


func loaded_chunk_at(x: float, z: float) -> WorldChunk:
	var c: WorldChunk = chunk_at(x, z)
	return c if c != null and c.state == WorldChunk.State.LOADED else null


## True when the terrain collider under (x, z) exists (the collision step ran).
func has_collision_at(x: float, z: float) -> bool:
	var c: WorldChunk = chunk_at(x, z)
	return c != null and c.terrain_body != null


func loaded_keys() -> Array[int]:
	var out: Array[int] = []
	for k in chunks:
		if (chunks[k] as WorldChunk).state == WorldChunk.State.LOADED:
			out.append(k)
	out.sort()
	return out


## Loaded chunk that owns a choppable scatter wid (and its entry index) — [chunk, index] or [].
func find_scatter(wid: int) -> Array:
	for k in chunks:
		var c: WorldChunk = chunks[k]
		if c.wid_index.has(wid):
			return [c, int(c.wid_index[wid])]
	return []


# ------------------------------------------------------------------ foci and the desired set
func _foci() -> Array:
	var out: Array = []
	if focus_override != Vector3.INF:
		out.append([focus_override, Vector3.ZERO])
		return out
	if mode == Mode.SERVER:
		var world := get_parent()
		var players: Node = world.get_node_or_null("Players") if world != null else null
		if players != null:
			for p in players.get_children():
				if p is Node3D:
					out.append([(p as Node3D).global_position, (p as Node3D).get("velocity") if p is CharacterBody3D else Vector3.ZERO])
		return out
	var lp := GameFlow.local_player() if mode != Mode.DECORATIVE else null
	if lp != null and is_instance_valid(lp) and lp.is_inside_tree():
		out.append([(lp as Node3D).global_position, (lp as CharacterBody3D).velocity])
		return out
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		var t := cam.global_position + (-cam.global_basis.z) * 20.0
		out.append([t, Vector3.ZERO])
	elif World.instance != null:
		out.append([World.instance.default_focus(), Vector3.ZERO])
	return out


func _refresh_desired() -> void:
	_desired.clear()
	_focus_keys.clear()
	var now := Time.get_ticks_msec() / 1000.0
	for k in _pinned.keys():
		if float(_pinned[k]) <= now:
			_pinned.erase(k)
	for f in _foci():
		var pos: Vector3 = f[0]
		var vel: Vector3 = f[1]
		var fcx := WorldConst.chunk_of(pos.x)
		var fcz := WorldConst.chunk_of(pos.z)
		_focus_keys.append(WorldConst.key(fcx, fcz))
		var ahead := Vector2(vel.x, vel.z)
		var lcx := fcx
		var lcz := fcz
		if ahead.length() > LOOKAHEAD_SPEED:
			var d := ahead.normalized()
			lcx += int(round(d.x))
			lcz += int(round(d.y))
		for k in WorldConst.ring_keys(fcx, fcz, ring_prefetch):
			var kx := WorldConst.key_cx(k)
			var kz := WorldConst.key_cz(k)
			var ring := WorldConst.ring_dist(kx, kz, fcx, fcz)
			var cdir := Vector2(float(kx - fcx), float(kz - fcz))
			var ahead_bonus := 0.0
			if ahead.length() > 0.5 and cdir.length() > 0.0:
				ahead_bonus = -0.4 * cdir.normalized().dot(ahead.normalized())
			var pri := float(ring) * 10.0 + Vector2(float(kx - lcx), float(kz - lcz)).length() + ahead_bonus
			if not _desired.has(k) or float(_desired[k]) > pri:
				_desired[k] = pri
		if mode == Mode.SERVER:
			for k in WorldConst.ring_keys(fcx, fcz, WorldConst.HIBERNATE_RADIUS):
				_last_near[k] = now


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if not enabled:
		return
	var t0 := Time.get_ticks_usec()
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.2
		_refresh_desired()
		_launch_jobs()
	var t1 := Time.get_ticks_usec()
	_collect_jobs()
	var t2 := Time.get_ticks_usec()
	_instantiate(t0)
	var t3 := Time.get_ticks_usec()
	_unload_some(t0)
	frame_usec = Time.get_ticks_usec() - t0
	last_phases = [t1 - t0, t2 - t1, t3 - t2, frame_usec - (t3 - t0), _last_step_kind]
	var parts: Dictionary = stats.get("phase_usec_max", {})
	parts["refresh"] = maxi(int(parts.get("refresh", 0)), t1 - t0)
	parts["collect"] = maxi(int(parts.get("collect", 0)), t2 - t1)
	parts["instantiate"] = maxi(int(parts.get("instantiate", 0)), t3 - t2)
	parts["unload"] = maxi(int(parts.get("unload", 0)), frame_usec - (t3 - t0))
	stats["phase_usec_max"] = parts
	stats["frame_usec_max"] = maxi(int(stats["frame_usec_max"]), frame_usec)
	if frame_usec > budget_usec:
		stats["over_budget_frames"] = int(stats["over_budget_frames"]) + 1


func _launch_jobs() -> void:
	if _jobs.size() >= max_tasks:
		return
	var missing: Array = []
	for k in _desired:
		if not chunks.has(k) and not _jobs.has(k) and not _is_ready_job(k):
			missing.append([float(_desired[k]), k])
	missing.sort_custom(func(a, b) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for m in missing:
		if _jobs.size() >= max_tasks:
			break
		_start_job(int(m[1]), true)
		if not threads_ok():
			break   # no worker threads (web nothreads build, 1 core): one chunk generated per refresh on this thread


## Worker threads available (the web export uses the nothreads template, where WorkerThreadPool would run the task
## synchronously inside add_task anyway).
static func threads_ok() -> bool:
	return OS.get_processor_count() > 1 and OS.has_feature("threads") and not force_no_threads


func _is_ready_job(k: int) -> bool:
	for j in _ready_jobs:
		if j.key == k:
			return true
	return false


func _make_job(k: int) -> ChunkJob:
	var j := ChunkJob.new()
	j.cx = WorldConst.key_cx(k)
	j.cz = WorldConst.key_cz(k)
	j.key = k
	j.hf = hf
	j.visual = visual
	j.clearing = clearing
	j.static_occ = _static_occ_for(j.cx, j.cz)
	if NetWorld.instance != null:
		if mode == Mode.SERVER:
			NetWorld.instance.wake_chunk(k)
		j.felled = NetWorld.instance.felled.duplicate()
	return j


func _static_occ_for(cx: int, cz: int) -> Array:
	var rect := WorldConst.chunk_rect(cx, cz).grow(1.0)
	var out: Array = []
	for o in static_occ:
		var r := ChunkJob.occluder_reach(o)
		var p: Vector2 = o["pos"]
		if rect.grow(r).has_point(p):
			out.append(o)
	return out


func _start_job(k: int, threaded: bool) -> ChunkJob:
	var j := _make_job(k)
	if threaded and threads_ok():
		j.task_id = WorkerThreadPool.add_task(j.run, false, "chunk %d,%d" % [j.cx, j.cz])
		_jobs[k] = j
	else:
		j.run()
		_finish_job(j)
	return j


## True while chunks are being generated (worker jobs) or instantiated (NavBaker waits: streaming first).
func is_busy() -> bool:
	return not _jobs.is_empty() or not _ready_jobs.is_empty() or not _building.is_empty()


func _collect_jobs() -> void:
	for k in _jobs.keys():
		var j: ChunkJob = _jobs[k]
		if WorkerThreadPool.is_task_completed(j.task_id):
			WorkerThreadPool.wait_for_task_completion(j.task_id)
			_jobs.erase(k)
			_finish_job(j)


func _finish_job(j: ChunkJob) -> void:
	stats["generated"] = int(stats["generated"]) + 1
	stats["gen_usec"] = int(stats["gen_usec"]) + j.usec
	stats["gen_usec_max"] = maxi(int(stats["gen_usec_max"]), j.usec)
	if not _desired.has(j.key) and not _wanted_sync.has(j.key):
		return   # the focus moved on meanwhile: drop it
	_ready_jobs.append(j)


var _wanted_sync: Dictionary = {}


func _instantiate(t0: int) -> void:
	# new chunks from finished jobs (highest priority first)
	if not _ready_jobs.is_empty():
		_ready_jobs.sort_custom(func(a: ChunkJob, b: ChunkJob) -> bool: return float(_desired.get(a.key, 99.0)) < float(_desired.get(b.key, 99.0)))
	var ran := 0
	while not _ready_jobs.is_empty() or not _building.is_empty():
		var elapsed := Time.get_ticks_usec() - t0
		if _building.is_empty():
			var j: ChunkJob = _ready_jobs.pop_front()
			if chunks.has(j.key):
				continue
			var c := WorldChunk.new()
			c.setup(j, visual, with_nodes)
			chunks_root.add_child(c)
			chunks[j.key] = c
			_building.append(c)
		var ch: WorldChunk = _building[0]
		var kind := ch.step_kind()
		var est := int(_step_costs.get(kind, 800))
		# the step that would overrun (with a margin for estimate noise) waits for the next frame
		if ran > 0 and elapsed + est + STEP_MARGIN_USEC > budget_usec:
			break
		ran += 1
		var s0 := Time.get_ticks_usec()
		_last_step_kind = kind
		var done := ch.step()
		var cost := Time.get_ticks_usec() - s0
		_step_costs[kind] = int(lerpf(float(_step_costs.get(kind, cost)), float(cost), 0.3))
		stats["step_usec_max"] = maxi(int(stats["step_usec_max"]), cost)
		stats["steps"] = int(stats["steps"]) + 1
		if cost > budget_usec:
			stats["steps_over_budget"] = int(stats["steps_over_budget"]) + 1
		var by: Dictionary = stats.get("step_max_by_kind", {})
		by[kind] = maxi(int(by.get(kind, 0)), cost)
		stats["step_max_by_kind"] = by
		if done:
			_building.pop_front()
			stats["loaded"] = int(stats["loaded"]) + 1
			chunk_loaded.emit(ch.key)


func _unload_some(t0: int) -> void:
	# finish freeing chunks unloaded earlier, a few nodes at a time, inside the frame budget
	while not _dying.is_empty():
		var left := budget_usec - (Time.get_ticks_usec() - t0)
		if left <= 150:
			return
		var d: WorldChunk = _dying[0]
		var t1 := Time.get_ticks_usec()
		var done := d.teardown_step(left - 100)
		stats["unload_usec_max"] = maxi(int(stats.get("unload_usec_max", 0)), Time.get_ticks_usec() - t1)
		if done:
			_dying.pop_front()
			chunks_root.remove_child(d)
			d.free()
	if Time.get_ticks_usec() - t0 > budget_usec or _dying.size() >= 2:
		return
	var now := Time.get_ticks_msec() / 1000.0
	for k in chunks.keys():
		if _desired.has(k) or float(_pinned.get(k, 0.0)) > now:
			continue
		var c: WorldChunk = chunks[k]
		var far := true
		for fk in _focus_keys:
			if WorldConst.ring_dist(WorldConst.key_cx(k), WorldConst.key_cz(k), WorldConst.key_cx(fk), WorldConst.key_cz(fk)) <= ring_prefetch + UNLOAD_MARGIN:
				far = false
		if not far:
			continue
		if mode == Mode.SERVER:
			if now - float(_last_near.get(k, 0.0)) < WorldConst.HIBERNATE_SECONDS:
				continue
			if NetWorld.instance != null:
				NetWorld.instance.hibernate_chunk(k)
			stats["hibernated"] = int(stats["hibernated"]) + 1
			_last_near.erase(k)
		_free_chunk(k, c)
		return   # one per frame


func _free_chunk(k: int, c: WorldChunk) -> void:
	chunks.erase(k)
	_building.erase(c)
	c.begin_teardown()
	_dying.append(c)
	stats["unloaded"] = int(stats["unloaded"]) + 1
	chunk_unloaded.emit(k)


## Synchronous load (spawn, teleport, first frame): every chunk within `radius` of `pos` is fully built on
## return. Missing chunks are generated in parallel tasks, then instantiated without budget.
func ensure_loaded(pos: Vector3, radius: int = 1) -> int:
	if not enabled:
		return 0
	var cx := WorldConst.chunk_of(pos.x)
	var cz := WorldConst.chunk_of(pos.z)
	var keys := WorldConst.ring_keys(cx, cz, radius)
	var started: Array[ChunkJob] = []
	var built := 0
	var pin_until := Time.get_ticks_msec() / 1000.0 + SYNC_PIN_SECONDS
	for k in keys:
		if chunks.has(k) or _is_ready_job(k):
			continue
		_wanted_sync[k] = true
		if _jobs.has(k):
			started.append(_jobs[k])
			_jobs.erase(k)
		else:
			var j := _make_job(k)
			if threads_ok():
				j.task_id = WorkerThreadPool.add_task(j.run, true, "chunk sync")
			else:
				j.run()
			started.append(j)
	for j in started:
		if j.task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(j.task_id)
			j.task_id = -1
		stats["generated"] = int(stats["generated"]) + 1
		stats["gen_usec"] = int(stats["gen_usec"]) + j.usec
		_ready_jobs.append(j)
	for k in keys:
		var c: WorldChunk = chunks.get(k)
		if c == null:
			var j: ChunkJob = null
			for rj in _ready_jobs:
				if rj.key == k:
					j = rj
			if j == null:
				continue
			_ready_jobs.erase(j)
			c = WorldChunk.new()
			c.setup(j, visual, with_nodes)
			chunks_root.add_child(c)
			chunks[k] = c
		if c.state != WorldChunk.State.LOADED:
			c.build_all()
			_building.erase(c)
			built += 1
			stats["loaded"] = int(stats["loaded"]) + 1
			chunk_loaded.emit(k)
		_wanted_sync.erase(k)
		if chunks.has(k):
			_pinned[k] = pin_until
	if built > 0:
		stats["sync_loads"] = int(stats["sync_loads"]) + 1
		_refresh_t = 0.0   # the focus (teleport, spawn) is where these chunks are: re-plan on the next frame
	if mode == Mode.SERVER:
		var now := Time.get_ticks_msec() / 1000.0
		for k in WorldConst.ring_keys(cx, cz, WorldConst.HIBERNATE_RADIUS):
			_last_near[k] = now
	return built


## Blocks until everything desired right now is loaded (tools, tests).
func flush_all() -> void:
	_refresh_desired()
	var keys := _desired.keys()
	for k in keys:
		var p := WorldConst.chunk_center(WorldConst.key_cx(k), WorldConst.key_cz(k))
		ensure_loaded(p, 0)


func is_idle() -> bool:
	if not _jobs.is_empty() or not _ready_jobs.is_empty() or not _building.is_empty() or not _dying.is_empty():
		return false
	for k in _desired:
		if not chunks.has(k):
			return false
	return true


## AO re-bake of one occluder in every loaded chunk it reaches (felled tree → stump disc).
func update_occluder(id: String, r: float, strength: float) -> void:
	for k in chunks:
		(chunks[k] as WorldChunk).update_occluder(id, r, strength, true)


## Chunk keys a focus position needs (tests: interest vs loaded).
static func ring_of(pos: Vector3, r: int) -> Array[int]:
	return WorldConst.ring_keys(WorldConst.chunk_of(pos.x), WorldConst.chunk_of(pos.z), r)
