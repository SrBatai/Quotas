extends RefCounted
## Body of tests/perf_walk.gd (loaded at runtime, after the autoloads exist).

## W1 route (default, 6.5 km through the four quadrants, world metres): out of the clearing to the Gasolinera Norte,
## over the Sierra del Cierzo by the Carretera del Puerto (NW → NE), along the Gran Vía into Altavega, south
## through the barriada to the río Albo, down the ice past the dársena into the SE quadrant, across Vega Baja
## and west along the railway into the SW quadrant (Sierra de Peña Blanca foothills).
const ROUTE_W1 := [Vector2(0, 30), Vector2(632, -392), Vector2(1792, -384), Vector2(2300, -384), Vector2(2300, 500),
	Vector2(2432, 700), Vector2(2432, 1700), Vector2(1900, 2100), Vector2(1300, 2560), Vector2(800, 2600), Vector2(780, 2640)]
## M3 route (--route=m3): out of the clearing to the north-east, down the N‑140 and back west through forest and
## past the Embarcadero road ≈ 2.26 km.
const ROUTE_M3 := [Vector2(0, 30), Vector2(160, -60), Vector2(420, -200), Vector2(640, -250), Vector2(650, 120),
	Vector2(630, 360), Vector2(380, 380), Vector2(120, 330), Vector2(-150, 300), Vector2(-296, 240)]
## C0 route (--route=c0, PLAN C0 acceptance): down the Carretera del Puerto, along the Gran Vía, over the Puente de
## Hierro (on the ice under it: the walk follows the terrain) into Las Torres and round the superblock LT-01 by its
## west, back and east streets ≈ 2.4 km.
const ROUTE_C0 := [Vector2(640, -392), Vector2(1792, -384), Vector2(2250, -384), Vector2(2614, -384), Vector2(2614, -496),
	Vector2(2746, -496), Vector2(2746, -392), Vector2(2800, -384)]
var ROUTE: Array = ROUTE_W1
const WARMUP_FRAMES := 60
const HITCH_MS := 33.3

var tree: SceneTree
var opts: Dictionary = {}


func run(p_tree: SceneTree, p_opts: Dictionary) -> void:
	tree = p_tree
	opts = p_opts
	ROUTE = ROUTE_M3 if str(opts.get("route", "w1")) == "m3" else (ROUTE_C0 if str(opts.get("route", "w1")) == "c0" else ROUTE_W1)
	await tree.process_frame
	if bool(opts.get("cpu", false)):
		WorldStreamer.force_visual = true
	elif not Quality.is_compat_renderer():
		Quality.set_preset(&"alto", false)
	# --nothreads: the web (nothreads template) path, chunks generated on the main thread (informative, not gated)
	WorldStreamer.force_no_threads = bool(opts.get("nothreads", false))
	# W1 (--cpu): the streaming cost per frame is also measured without the time the OS kept the main thread off the
	# CPU inside the streaming window (run-queue wait, SchedProbe; Linux). The budget gates use that "work" time when
	# it is available; the raw wall time is reported next to it (ARQ v2 §8.10: the 9–22 ms single-step spikes of M3
	# were the main thread preempted by other processes / threads on the pinned cores, not streaming work).
	var probe := bool(opts.get("cpu", false)) and SchedProbe.available() and not bool(opts.get("no_probe", false))
	WorldStreamer.sched_probe = probe
	# --sched: diagnostics, scheduler counters around every streaming step and every frame
	var sched := bool(opts.get("sched", false)) and SchedProbe.available()
	WorldStreamer.sched_probe = probe or sched
	WorldStreamer.sched_steps = sched
	var ready := [false]
	Events.world_ready.connect(func() -> void:
		ready[0] = true
		var w := tree.current_scene.get_node_or_null("World/Weather")
		if w != null:
			w.scheduler_enabled = false
			w.cancel())
	GameFlow.play_offline()
	var waited := 0
	while (not ready[0] or GameFlow.local_player() == null) and waited < 1200:
		await tree.process_frame
		waited += 1
	var player: Player = GameFlow.local_player()
	var world: World = tree.current_scene.get_node("World")
	if player == null:
		print("FAIL: no local player")
		tree.quit(1)
		return
	WorldState.instance.set_time(1, 11.0)
	WorldState.instance.running = false
	world.get_node("WolfSpawner").enabled = false
	world.get_node("DeerSpawner").enabled = false
	Events.notify.emit("", 0.1)
	# the walk drives the body directly (no input / prediction): car speed along the route
	player.set_physics_process(false)
	player.net.set_physics_process(false)
	var st := world.streamer
	# C0: a route that does not start at the spawn (--route=c0) begins where it starts, its ring loaded (the W1 / M3
	# routes start at the porch: nothing changes for them)
	var r0: Vector2 = ROUTE[0]
	if Vector2(player.global_position.x, player.global_position.z).distance_to(r0) > 64.0:
		player.global_position = Vector3(r0.x, world.get_height(r0.x, r0.y) + 0.05, r0.y)
		st.ensure_loaded(player.global_position, WorldConst.RING_PREFETCH)
	for i in WARMUP_FRAMES:
		await tree.process_frame
	var speed := float(opts["speed"])
	var total_len := 0.0
	for i in ROUTE.size() - 1:
		total_len += (ROUTE[i] as Vector2).distance_to(ROUTE[i + 1])
	var stats0: Dictionary = st.stats.duplicate(true)
	var frame_ms: Array[float] = []
	var stream_ms: Array[float] = []
	var hitches := 0
	var hitches_streaming := 0
	var missing_ground := 0
	var dist := 0.0
	var seg := 0
	var seg_d := 0.0
	var last_us := Time.get_ticks_usec()
	var rss_max := 0.0
	var draw_calls: Array[float] = []
	var frames := 0
	var worst: Array = []
	var over_budget := 0
	var work_ms: Array[float] = []
	var wait_ms: Array[float] = []
	var worst_work: Array = []
	var fw0 := SchedProbe.wait_ns() if probe else 0
	var frame_wait_total := 0.0
	# hypervisor steal on the CPUs we may run on (a frame during which it grew is flagged, see below)
	var cpus := SchedProbe.allowed_cpus() if probe else PackedInt32Array()
	var st0 := SchedProbe.steal_of(cpus) if probe else 0
	var steal_frames := 0
	var blocked_frames := 0
	var hitch_frames: Array = []
	var work_ms_nosteal: Array[float] = []
	var preempted := 0
	var over_budget_work := 0
	var fprobe: PackedInt64Array = SchedProbe.sample() if sched else PackedInt64Array()
	var fsteal := SchedProbe.steal_jiffies() if sched else 0
	var sched_frames: Array = []
	while seg < ROUTE.size() - 1:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		if sched:
			var fp := SchedProbe.sample()
			var fd := SchedProbe.delta(fprobe, fp)
			fprobe = fp
			var stl := SchedProbe.steal_jiffies()
			var fwall := float(now - last_us) / 1000.0
			if fwall > 8.0 or float(st.frame_usec) > 2000.0:
				sched_frames.append([snappedf(fwall, 0.01), snappedf(float(st.frame_usec) / 1000.0, 0.01), snappedf(float(fd[0]) / 1e6, 0.01),
					snappedf(float(fd[1]) / 1e6, 0.01), int(fd[2]), int(fd[3]), stl - fsteal, str(st.last_phases[4]) if st.last_phases.size() > 4 else ""])
			fsteal = stl
		var dt := float(now - last_us) / 1000000.0
		last_us = now
		frames += 1
		var fms := dt * 1000.0
		# W1: the main thread's run-queue wait over the whole frame (preempted anywhere in it, not only in streaming)
		var fq := 0.0
		if probe:
			var fw := SchedProbe.wait_ns()
			fq = minf(float(fw - fw0) / 1e6, fms)
			fw0 = fw
			frame_wait_total += fq
		var stolen := false
		if probe:
			# stolen = the streaming window lost more than one scheduler tick to neither running nor the run queue:
			# the vCPU was taken by the hypervisor (the thread's on-CPU counter excludes steal). The system steal
			# counter of our CPUs must have grown too (it is only 10 ms granular, so alone it flags too many frames).
			var st1 := SchedProbe.steal_of(cpus)
			var lost := float(st.frame_usec - st.frame_wait_usec - st.frame_cpu_usec) / 1000.0
			stolen = st1 != st0 and lost > float(SchedProbe.TICK_USEC) / 1000.0 + 0.5 and st.frame_blocks == 0
			st0 = st1
			if stolen:
				steal_frames += 1
		var sms := float(st.frame_usec) / 1000.0
		var qms := float(st.frame_wait_usec) / 1000.0
		var wms := maxf(sms - qms, 0.0)
		frame_ms.append(fms)
		stream_ms.append(sms)
		work_ms.append(wms)
		wait_ms.append(qms)
		if st.frame_blocks > 0:
			blocked_frames += 1
		if not stolen and st.frame_blocks == 0:
			work_ms_nosteal.append(wms)
		var budget_ms := WorldConst.STREAM_BUDGET_USEC / 1000.0
		if sms > budget_ms:
			over_budget += 1
			if wms <= budget_ms:
				preempted += 1
		if wms > budget_ms:
			over_budget_work += 1
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if wms > 2.0:
			worst_work.append([snappedf(wms, 0.001), snappedf(fms, 0.01), st.last_phases.duplicate() + ["steal" if stolen else "", "blocked %d" % st.frame_blocks if st.frame_blocks > 0 else "", "cpu %.1f ms" % (float(st.frame_cpu_usec) / 1000.0)]])
			worst_work.sort_custom(func(a, b) -> bool: return a[0] > b[0])
			if worst_work.size() > 6:
				worst_work.pop_back()
		if sms > 2.0:
			worst.append([sms, fms, st.last_phases.duplicate() + [snappedf(qms, 0.01)]])
			worst.sort_custom(func(a, b) -> bool: return a[0] > b[0])
			if worst.size() > 6:
				worst.pop_back()
		if fms > HITCH_MS:
			hitches += 1
			# attributable to streaming when the frame would not have been a hitch without it, or the streamer took a
			# real share of it (under a software GPU every frame is > 33 ms: only the second test can fire there)
			# (W1: with the probe, the frame's own time is its wall time minus the run-queue wait of the main thread over
			# the whole frame, and the streaming share is its work time: a frame the OS preempted elsewhere is not a
			# streaming hitch unless it is one without the preemption)
			# W1: and streaming itself must have overrun its budget — a frame whose non-streaming time spiked (steal,
			# physics, a block elsewhere) to ≥ 31.3 ms is not made a streaming hitch by ≤ 2 ms of streaming work
			var sh := wms if probe else sms
			if stolen:
				sh = minf(sh, float(st.frame_cpu_usec) / 1000.0 + float(SchedProbe.TICK_USEC) / 1000.0)
			# C0: a main thread that blocked inside the streaming window (voluntary switch: the WorkerThreadPool mutex
			# held by a preempted worker, ARQ v2 §8.10) did no streaming work while off the CPU: like a stolen frame, its
			# streaming share is its measured on-CPU time (+1 tick). The single-frame max already excluded these frames.
			if probe and st.frame_blocks > 0:
				sh = minf(sh, float(st.frame_cpu_usec) / 1000.0 + float(SchedProbe.TICK_USEC) / 1000.0)
			var own := fms - fq if probe else fms
			var over := sh > WorldConst.STREAM_BUDGET_USEC / 1000.0 if probe else true
			if own > HITCH_MS and over and (own - sh <= HITCH_MS or sh > own * 0.25):
				hitches_streaming += 1
			if hitch_frames.size() < 12 and sh > 0.5:
				hitch_frames.append([snappedf(fms, 0.1), snappedf(fq, 0.1), snappedf(sms, 0.01), snappedf(wms, 0.01), stolen, st.frame_blocks, st.last_phases.duplicate(), snappedf(float(st.frame_cpu_usec) / 1000.0, 0.1)])
		# advance along the route (game time = real time: a slow software-rendered frame moves the player further)
		var step := speed * minf(dt, 0.1)
		dist += step
		seg_d += step
		while seg < ROUTE.size() - 1 and seg_d > (ROUTE[seg] as Vector2).distance_to(ROUTE[seg + 1]):
			seg_d -= (ROUTE[seg] as Vector2).distance_to(ROUTE[seg + 1])
			seg += 1
		if seg >= ROUTE.size() - 1:
			break
		var a: Vector2 = ROUTE[seg]
		var b: Vector2 = ROUTE[seg + 1]
		var dir := (b - a).normalized()
		var p := a + dir * seg_d
		var y := world.get_height(p.x, p.y)
		player.global_position = Vector3(p.x, y + 0.05, p.y)
		player.velocity = Vector3(dir.x, 0.0, dir.y) * speed
		player.aim_yaw = atan2(dir.x, dir.y)
		if not st.has_collision_at(p.x, p.y):
			missing_ground += 1
		if frames % 30 == 0:
			rss_max = maxf(rss_max, _rss_mb())
	rss_max = maxf(rss_max, _rss_mb())
	var s1: Dictionary = st.stats
	var report := {
		"label": "perf_walk_cpu" if bool(opts.get("cpu", false)) else "perf_walk",
		"route": str(opts.get("route", "w1")),
		"timestamp": Time.get_datetime_string_from_system(true),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"cpu_cores": OS.get_processor_count(),
		"speed_mps": speed,
		"route_m": snappedf(total_len, 0.1),
		"frames": frames,
		"frame_ms": {"p50": _pct(frame_ms, 0.5), "p99": _pct(frame_ms, 0.99), "max": frame_ms.max()},
		"stream_ms": {"p50": _pct(stream_ms, 0.5), "p99": _pct(stream_ms, 0.99), "p999": _pct(stream_ms, 0.999), "max": stream_ms.max()},
		"sched_probe": probe,
		"stream_work_ms": {"p50": _pct(work_ms, 0.5), "p99": _pct(work_ms, 0.99), "p999": _pct(work_ms, 0.999), "max": work_ms.max()},
		"stream_wait_ms": {"total": snappedf(_sum(wait_ms), 0.1), "max": wait_ms.max(), "frames": wait_ms.filter(func(v: float) -> bool: return v > 0.05).size()},
		"frames_over_stream_budget_preempted": preempted,
		"frames_over_stream_budget_work": over_budget_work,
		"frames_over_stream_budget_work_pct": snappedf(100.0 * over_budget_work / maxf(frames, 1), 0.01),
		"worst_work_frames": worst_work,
		"steal_frames": steal_frames,
		"hitch_frames": hitch_frames,
		"blocked_frames": blocked_frames,
		"stream_work_ms_max_without_steal": work_ms_nosteal.max() if not work_ms_nosteal.is_empty() else 0.0,
		"frame_run_queue_wait_ms_total": snappedf(frame_wait_total, 0.1),
		"frames_over_33ms": hitches,
		"frames_over_33ms_streaming": hitches_streaming,
		"missing_ground_frames": missing_ground,
		"chunks_generated": int(s1["generated"]) - int(stats0["generated"]),
		"chunks_unloaded": int(s1["unloaded"]) - int(stats0["unloaded"]),
		"gen_ms_avg": float(int(s1["gen_usec"]) - int(stats0["gen_usec"])) / 1000.0 / maxf(float(int(s1["generated"]) - int(stats0["generated"])), 1.0),
		"gen_ms_max": float(s1["gen_usec_max"]) / 1000.0,
		"step_ms_max": float(s1["step_usec_max"]) / 1000.0,
		"step_max_by_kind_us": s1.get("step_max_by_kind", {}),
		"sync_loads": int(s1["sync_loads"]) - int(stats0["sync_loads"]),
		"phase_usec_max": s1.get("phase_usec_max", {}),
		"frames_over_stream_budget": over_budget,
		"frames_over_stream_budget_pct": snappedf(100.0 * over_budget / maxf(frames, 1), 0.01),
		"worst_stream_frames": worst,
		"unload_usec_max": int(s1.get("unload_usec_max", 0)),
		"loaded_chunks_end": st.loaded_keys().size(),
		"draw_calls_p50": _pct(draw_calls, 0.5),
		"rss_mb_max": snappedf(rss_max, 0.1),
		"memory_static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}
	print("== perf walk%s (%s, %d cores): %.0f m at %.0f m/s, %d frames" % [" --cpu (headless, visual streaming forced)" if bool(opts.get("cpu", false)) else "", report["rendering_method"], report["cpu_cores"], total_len, speed, frames])
	print("  frame ms      p50 %.1f  p99 %.1f  max %.1f  (> 33 ms: %d, caused by streaming: %d)" % [report["frame_ms"]["p50"], report["frame_ms"]["p99"], report["frame_ms"]["max"], hitches, hitches_streaming])
	print("  streaming ms  p50 %.2f  p99 %.2f  p99.9 %.2f  max %.2f  (budget %.1f)  max step %.2f ms %s" % [report["stream_ms"]["p50"], report["stream_ms"]["p99"], report["stream_ms"]["p999"], report["stream_ms"]["max"], WorldConst.STREAM_BUDGET_USEC / 1000.0, report["step_ms_max"], report["step_max_by_kind_us"]])
	if probe:
		print("  streaming work ms (wall − run-queue wait) p50 %.2f  p99 %.2f  p99.9 %.2f  max %.2f; over budget %d (%.2f %%); raw over budget only because the OS preempted the main thread: %d frames; run-queue wait inside streaming %.1f ms total in %d frames (max %.2f ms)" % [
			report["stream_work_ms"]["p50"], report["stream_work_ms"]["p99"], report["stream_work_ms"]["p999"], report["stream_work_ms"]["max"],
			over_budget_work, report["frames_over_stream_budget_work_pct"], preempted, report["stream_wait_ms"]["total"], report["stream_wait_ms"]["frames"], report["stream_wait_ms"]["max"]])
		print("  frames > 33 ms with streaming work > 0.5 ms (first 12) [frame ms, run-queue ms, stream ms, stream work ms, steal, blocked, phases, streaming on-CPU ms]: %s" % [hitch_frames])
		print("  worst streaming work frames [work ms, frame ms, [refresh, collect, instantiate, unload µs, step]]: %s; main-thread run-queue wait over all frames %.1f ms; frames with hypervisor steal on CPUs %s: %d, frames where the main thread blocked inside streaming: %d (streaming work max without both %.2f ms)" % [
			worst_work, frame_wait_total, cpus, steal_frames, blocked_frames, report["stream_work_ms_max_without_steal"]])
	print("  phases µs max %s, unload one chunk max %d µs" % [report["phase_usec_max"], report["unload_usec_max"]])
	print("  frames over the 2 ms streaming budget: %d of %d (%.2f %%); worst [stream ms, frame ms, [refresh, collect, instantiate, unload µs, step]]: %s" % [over_budget, frames, 100.0 * over_budget / maxf(frames, 1), worst])
	print("  chunks        %d generated (avg %.1f ms, max %.1f ms in workers), %d unloaded, %d loaded at the end, %d sync loads, ground missing %d frames" % [report["chunks_generated"], report["gen_ms_avg"], report["gen_ms_max"], report["chunks_unloaded"], report["loaded_chunks_end"], report["sync_loads"], missing_ground])
	print("  memory        RSS max %.0f MB, static %.0f MB, video %.0f MB, nodes %d, draw calls p50 %d" % [report["rss_mb_max"], report["memory_static_mb"], report["video_mem_mb"], int(report["nodes"]), int(report["draw_calls_p50"])])
	if sched:
		report["sched_slow_steps"] = st.probe_steps
		report["sched_slow_frames"] = sched_frames
		print("  sched: slow steps (>= %d µs) [kind, wall µs, on-CPU µs, run-queue µs, slices, minflt, majflt, blocked]:" % WorldStreamer.PROBE_SLOW_USEC)
		for r in st.probe_steps:
			print("    %s" % [r])
		print("  sched: frames > 8 ms or streaming > 2 ms [frame ms, stream ms, main on-CPU ms, main run-queue ms, slices, minflt, steal jiffies (all CPUs), last step]:")
		for r in sched_frames:
			print("    %s" % [r])
	var ok := true
	if bool(opts["check"]):
		ok = _check(report)
	_write(report)
	print("== perf walk %s" % ("OK" if ok else "FAILED"))
	tree.quit(0 if ok else 1)


func _check(report: Dictionary) -> bool:
	var data = JSON.parse_string(FileAccess.get_file_as_string(String(opts["budgets"]))) if FileAccess.file_exists(String(opts["budgets"])) else {}
	var b: Dictionary = data.get("perf_walk_cpu" if bool(opts.get("cpu", false)) else "perf_walk", {}) if data is Dictionary else {}
	var ok := true
	# W1: with the scheduler probe the per-frame streaming numbers are the work time (raw wall − run-queue wait)
	var sk := "stream_work_ms" if bool(report.get("sched_probe", false)) else "stream_ms"
	var pct: float = report["frames_over_stream_budget_work_pct"] if bool(report.get("sched_probe", false)) else report["frames_over_stream_budget_pct"]
	# the single-frame max excludes the frames during which the hypervisor stole our vCPUs (steal counter grew) or the
	# main thread blocked inside the streaming window (voluntary switch: a lock held by a preempted thread)
	var mx: float = report["stream_work_ms_max_without_steal"] if bool(report.get("sched_probe", false)) else report[sk]["max"]
	var checks := [["stream_ms_p99_max", report[sk]["p99"]], ["stream_ms_p999_max", report[sk]["p999"]],
		["stream_ms_max", mx], ["frames_over_stream_budget_pct_max", pct],
		["frames_over_33ms_streaming_max", report["frames_over_33ms_streaming"]],
		["missing_ground_frames_max", report["missing_ground_frames"]], ["rss_mb_max", report["rss_mb_max"]]]
	for c in checks:
		if not b.has(c[0]):
			continue
		var limit := float(b[c[0]])
		if float(c[1]) > limit:
			ok = false
			print("FAIL: %s = %.2f > budget %.2f" % [c[0], float(c[1]), limit])
		else:
			print("  ok   %s = %.2f <= %.2f" % [c[0], float(c[1]), limit])
	return ok


func _write(report: Dictionary) -> void:
	var path := String(opts["out"])
	if not path.begins_with("res://") and not path.begins_with("user://") and not path.begins_with("/"):
		path = "res://" + path
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
		print("  wrote %s" % path)


## Resident memory of the whole process (MB): /proc/self/status VmRSS (procfs reports no length, so it is read
## line by line); falls back to Godot's static memory elsewhere.
static func _rss_mb() -> float:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f != null:
		while not f.eof_reached():
			var line := f.get_line()
			if line.begins_with("VmRSS:"):
				return float(line.split(":")[1].strip_edges().split(" ")[0]) / 1024.0
			if line == "":
				break
	return Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0


static func _sum(values: Array[float]) -> float:
	var t := 0.0
	for v in values:
		t += v
	return t


static func _pct(values: Array[float], p: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(floor(p * float(sorted.size() - 1))), 0, sorted.size() - 1)]
