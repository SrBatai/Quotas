extends RefCounted
## Body of tests/perf_horde.gd (loaded at runtime, after the autoloads exist).

const BOTS := [Vector3(2.0, 0.0, 9.0), Vector3(-9.0, 0.0, 12.0), Vector3(12.0, 0.0, -4.0), Vector3(-6.0, 0.0, -14.0)]
const WARMUP := 6.0

var tree: SceneTree
var opts: Dictionary = {}
var bots: Array[Player] = []
var _tick_us: Array[float] = []
var _sys_us: Array[float] = []
var _net_us: Array[float] = []
var _phys_us: Array[float] = []
var _nav_us: Array[float] = []
var _move_us: Array[float] = []
var _scripts_us: Array[float] = []
var _first_t: int = 0


var _busy_us: Array[float] = []
var _frame_t0: int = 0


## Probes around every node's _physics_process (priorities −10000 / +10000: the script share of the tick) and at
## the very end of the frame's _process (process priority +10000): the server's busy time per tick = from the first
## physics callback to the last process callback (scripts + Jolt step + navigation + idle processing). The engine's
## TIME_*_PROCESS monitors are the maximum over the last second, not per frame.
class Probe:
	extends Node
	var cb: Callable
	var on_process: bool = false
	func _ready() -> void:
		set_physics_process(not on_process)
		set_process(on_process)
	func _physics_process(_d: float) -> void:
		cb.call()
	func _process(_d: float) -> void:
		cb.call()
var _phys_frames: int = 0


func run(p_tree: SceneTree, p_opts: Dictionary) -> void:
	tree = p_tree
	opts = p_opts
	await tree.process_frame
	var cfg := ConfigFile.new()
	cfg.set_value("server", "name", "perf horde")
	cfg.set_value("server", "port", int(opts["port"]))
	cfg.set_value("server", "admin_port", int(opts["port"]) + 1)
	cfg.set_value("server", "max_players", 8)
	cfg.set_value("world", "seed", 1337)
	cfg.set_value("world", "save_path", "user://perf_horde_save.json")
	cfg.set_value("world", "autosave_seconds", 100000.0)
	var path := "user://perf_horde.cfg"
	cfg.save(path)
	if Net.start_server(ProjectSettings.globalize_path(path)) != OK:
		print("FAIL: cannot start the server: %s" % Net.last_error)
		tree.quit(1)
		return
	Net.load_game_scene()
	var waited := 0
	while (tree.current_scene == null or tree.current_scene.name != "Game" or ZombieSystem.instance == null or ZombieSystem.instance.world == null) and waited < 1200:
		await tree.process_frame
		waited += 1
	var game := tree.current_scene
	var sys := ZombieSystem.instance
	var world: World = game.get_node("World")
	Director.instance.enabled = false
	PopulationManager.instance.enabled = false
	world.get_node("WolfSpawner").enabled = false
	var weather := world.get_node("Weather") as Weather
	weather.scheduler_enabled = false
	weather.cancel()
	WorldState.instance.set_time(2, 11.0)
	WorldState.instance.running = false
	var pm: PlayerManager = game.get_node("PlayerManager")
	for k in BOTS.size():
		var b := pm.spawn_player(1001 + k, "bot%d" % (k + 1), "perfbot%d" % k)
		var p: Vector3 = BOTS[k]
		p.y = world.get_height(p.x, p.z) + 0.2
		b.position = p
		b.net_position = p
		b.state.inventory.add(&"hacha", 1, true)
		bots.append(b)
	if OS.get_environment("HORDE_NOBENCH") == "":
		ZombieNet.instance.bench_players = bots.duplicate()
	if OS.get_environment("HORDE_BODIES") != "":
		sys.max_bodies = int(OS.get_environment("HORDE_BODIES"))
	# every bot chunk streamed + its navmesh baked before the clock starts
	for b in bots:
		world.ensure_area(b.global_position, 2)
	waited = 0
	while (not sys.nav.is_idle() or not world.streamer.is_idle()) and waited < 3000:
		await tree.process_frame
		waited += 1
	var n := int(opts["zombies"])
	_fill(sys, n)
	print("== perf horde: %d zombies, %d bots, navmesh regions %d (bake max %d ms)" % [sys.count_alive(), bots.size(), sys.nav.regions.size(), int(sys.nav.stats["bake_usec_max"]) / 1000])
	tree.physics_frame.connect(_on_physics)
	var first := Probe.new()
	first.process_physics_priority = -10000
	first.cb = func() -> void:
		_first_t = Time.get_ticks_usec()
		if _frame_t0 == 0:
			_frame_t0 = _first_t
	game.add_child(first)
	var last := Probe.new()
	last.process_physics_priority = 10000
	last.cb = func() -> void: _scripts_us.append(float(Time.get_ticks_usec() - _first_t))
	game.add_child(last)
	var end := Probe.new()
	end.on_process = true
	end.process_priority = 10000
	end.cb = func() -> void:
		if _frame_t0 != 0:
			_busy_us.append(float(Time.get_ticks_usec() - _frame_t0))
			_frame_t0 = 0
	game.add_child(end)
	var t0 := Time.get_ticks_msec() / 1000.0
	var measuring := false
	var next_act := t0
	var q0 := 0
	var bytes0 := 0
	var kills0 := 0
	var t_meas := 0.0
	while true:
		await tree.process_frame
		var now := Time.get_ticks_msec() / 1000.0
		if not measuring and now - t0 >= WARMUP:
			measuring = true
			_tick_us.clear()
			_busy_us.clear()
			_scripts_us.clear()
			_move_us.clear()
			_net_us.clear()
			_sys_us.clear()
			_phys_frames = 0
			q0 = int(sys.queue.stats["queries"])
			bytes0 = int(ZombieNet.instance.stats["bytes"])
			kills0 = int(sys.stats["killed"])
			t_meas = now
		if measuring:
			var us := (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1e6
			_tick_us.append(us)   # engine monitors: max over the last second (informative)
			_phys_us.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1e6)
			_nav_us.append(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1e6)
		if now >= next_act:
			next_act = now + 1.0
			_bots_act(sys, now)
			_fill(sys, n)
		if measuring and now - t_meas >= float(opts["seconds"]):
			break
	tree.physics_frame.disconnect(_on_physics)
	var secs := Time.get_ticks_msec() / 1000.0 - t_meas
	var tick := _stats(_busy_us)
	var mon := _stats(_tick_us)
	var zs := _stats(_sys_us)
	var queries := int(sys.queue.stats["queries"]) - q0
	var kbps := float(int(ZombieNet.instance.stats["bytes"]) - bytes0) / secs / 1000.0 / float(bots.size())
	var result := {"zombies": n, "alive_end": sys.count_alive(), "bodies": sys.bodies_in_use(), "l0": sys.l0.size(), "l1": sys.l1.size(),
		"bots": bots.size(), "seconds": secs, "frames": _tick_us.size(), "physics_frames": _phys_frames,
		"tick_ms_p50": tick["p50"] / 1000.0, "tick_ms_p99": tick["p99"] / 1000.0, "tick_ms_max": tick["max"] / 1000.0, "tick_ms_mean": tick["mean"] / 1000.0,
		"monitor_ms_p50": mon["p50"] / 1000.0,
		"zombie_ms_p50": zs["p50"] / 1000.0, "zombie_ms_p99": zs["p99"] / 1000.0,
		"route_queries_per_s": float(queries) / secs, "route_max_per_tick": int(sys.queue.stats["max_per_tick"]),
		"kills": int(sys.stats["killed"]) - kills0, "zombie_kbps_per_bot": kbps,
		"navmesh_regions": sys.nav.regions.size(), "nav_bake_ms_max": int(sys.nav.stats["bake_usec_max"]) / 1000.0,
		"cpus": OS.get_processor_count()}
	print("tick ms      p50 %.2f  p99 %.2f  max %.2f  mean %.2f  (busy time per tick: %d ticks, %d physics ticks in %.1f s)" % [result["tick_ms_p50"], result["tick_ms_p99"], result["tick_ms_max"], result["tick_ms_mean"], _busy_us.size(), _phys_frames, secs])
	print("monitor ms   p50 %.2f  (TIME_PROCESS + TIME_PHYSICS_PROCESS: each is the max of the last second)" % result["monitor_ms_p50"])
	print("zombie ms    p50 %.2f  p99 %.2f  (ZombieSystem._physics_process; last LOD pass %.2f ms)" % [result["zombie_ms_p50"], result["zombie_ms_p99"], float(sys.stats.get("lod_usec", 0)) / 1000.0])
	var ns := _stats(_net_us)
	var ps := _stats(_phys_us)
	var nv := _stats(_nav_us)
	result["net_ms_p50"] = ns["p50"] / 1000.0
	result["physics_ms_p50"] = ps["p50"] / 1000.0
	result["navigation_ms_p50"] = nv["p50"] / 1000.0
	var sc := _stats(_scripts_us)
	result["scripts_physics_ms_p50"] = sc["p50"] / 1000.0
	print("scripts ms   all _physics_process p50 %.2f p99 %.2f" % [sc["p50"] / 1000.0, sc["p99"] / 1000.0])
	print("monitors     nodes %d objects %d · physics active %d pairs %d islands %d · nav maps %d regions %d polys %d" % [
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT), Performance.get_monitor(Performance.NAVIGATION_ACTIVE_MAPS),
		Performance.get_monitor(Performance.NAVIGATION_REGION_COUNT), Performance.get_monitor(Performance.NAVIGATION_POLYGON_COUNT)])
	var mv := _stats(_move_us)
	result["move_ms_p50"] = mv["p50"] / 1000.0
	print("parts ms     zombie_net p50 %.2f p99 %.2f · bodies move_and_slide p50 %.2f · physics frame p50 %.2f · navigation p50 %.2f" % [ns["p50"] / 1000.0, ns["p99"] / 1000.0, mv["p50"] / 1000.0, ps["p50"] / 1000.0, nv["p50"] / 1000.0])
	print("zombies      %d alive, %d bodies (L0 %d, L1 %d), %d kills, routes %.1f/s (max %d/tick)" % [result["alive_end"], result["bodies"], result["l0"], result["l1"], result["kills"], result["route_queries_per_s"], result["route_max_per_tick"]])
	print("net          %.2f kB/s of zombie data per bot (bench peers)" % kbps)
	var qs: Dictionary = sys.queue.stats
	result["route_usec_max_tick"] = int(qs["usec_max"])
	result["route_usec_avg"] = float(qs["usec_total"]) / maxf(float(qs["queries"]), 1.0)
	print("routes       %d queries, %d shared, %.0f µs per query on average, worst tick %.2f ms" % [int(qs["queries"]), int(qs["shared"]), result["route_usec_avg"], float(qs["usec_max"]) / 1000.0])
	var f := FileAccess.open(str(opts["out"]), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(result, "  "))
	var ok := true
	if bool(opts["check"]):
		var budgets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/perf_budgets.json")).get("perf_horde", {})
		if float(result["tick_ms_p50"]) > float(budgets.get("tick_ms_p50_max", 8.0)):
			print("FAIL: median server tick %.2f ms > %.2f" % [result["tick_ms_p50"], float(budgets.get("tick_ms_p50_max", 8.0))])
			ok = false
		if int(result["alive_end"]) < n * 9 / 10 or int(result["bodies"]) < mini(n, 100):
			print("FAIL: horde not in place (%d alive, %d bodies)" % [result["alive_end"], result["bodies"]])
			ok = false
	print("== perf horde %s" % ("OK" if ok else "FAILED"))
	tree.quit(0 if ok else 1)


func _on_physics() -> void:
	_phys_frames += 1
	if ZombieSystem.instance != null:
		_sys_us.append(float(ZombieSystem.instance.stats["tick_usec"]))
		_move_us.append(float(ZombieSystem.instance.stats.get("move_usec", 0)))
	if ZombieNet.instance != null:
		_net_us.append(float(ZombieNet.instance.stats["usec"]))


## Keeps `n` zombies alive around the clearing (8–70 m from the bots' centre).
func _fill(sys: ZombieSystem, n: int) -> void:
	var missing := n - sys.count_alive()
	if missing > 0:
		var made := sys.spawn_ring(Vector3(1.0, 0.0, 1.0), missing, 10.0, 70.0, ZombieKinds.Kind.WALKER)
		for i in made:
			sys.chunk[i] = -2


## Once a second: the bots walk a new way, swing at the nearest zombie and get their health back (they must stay up).
func _bots_act(sys: ZombieSystem, now: float) -> void:
	for k in bots.size():
		var b := bots[k]
		if b.dead:
			b.respawn()
		if b.downed:
			b.state.stats.revive(null)
		b.state.health = Balance.HEALTH_MAX
		var a := now * 0.7 + float(k) * 1.6
		var home: Vector3 = BOTS[k]
		var to_home := home - b.global_position
		var mv := Vector2(cos(a), sin(a)) * 0.6 + Vector2(to_home.x, to_home.z).limit_length(1.0) * 0.4
		b.net._last_cmd = {"seq": 0, "move": mv.limit_length(1.0), "aim_yaw": atan2(mv.x, mv.y), "aim": b.global_position, "btn": 0, "slot": 0, "flags": 0}
		var near := sys.near(b.global_position, 2.2)
		if not near.is_empty():
			var z := near[0]
			var d := sys.pos[z] - b.global_position
			b.melee_ready_at = 0.0
			b.state.stamina = Balance.STAMINA_MAX
			Melee.perform(b, Weapons.Mode.LIGHT, atan2(d.x, d.z), sys.net_id[z])


static func _stats(arr: Array[float]) -> Dictionary:
	if arr.is_empty():
		return {"p50": 0.0, "p99": 0.0, "max": 0.0, "mean": 0.0}
	var s := arr.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += v
	return {"p50": s[s.size() / 2], "p99": s[mini(int(s.size() * 0.99), s.size() - 1)], "max": s[s.size() - 1], "mean": sum / float(s.size())}
