extends RefCounted
## Body of tests/perf_walk.gd (loaded at runtime, after the autoloads exist).

## The route (world metres): out of the clearing to the north-east, down the N‑140 and back west through forest
## and past the Embarcadero road ≈ 1.6 km.
const ROUTE := [Vector2(0, 30), Vector2(160, -60), Vector2(420, -200), Vector2(640, -250), Vector2(650, 120),
	Vector2(630, 360), Vector2(380, 380), Vector2(120, 330), Vector2(-150, 300), Vector2(-296, 240)]
const WARMUP_FRAMES := 60
const HITCH_MS := 33.3

var tree: SceneTree
var opts: Dictionary = {}


func run(p_tree: SceneTree, p_opts: Dictionary) -> void:
	tree = p_tree
	opts = p_opts
	await tree.process_frame
	if bool(opts.get("cpu", false)):
		WorldStreamer.force_visual = true
	elif not Quality.is_compat_renderer():
		Quality.set_preset(&"alto", false)
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
	while seg < ROUTE.size() - 1:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last_us) / 1000000.0
		last_us = now
		frames += 1
		var fms := dt * 1000.0
		var sms := float(st.frame_usec) / 1000.0
		frame_ms.append(fms)
		stream_ms.append(sms)
		if sms > WorldConst.STREAM_BUDGET_USEC / 1000.0:
			over_budget += 1
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if sms > 2.0:
			worst.append([sms, fms, st.last_phases.duplicate()])
			worst.sort_custom(func(a, b) -> bool: return a[0] > b[0])
			if worst.size() > 6:
				worst.pop_back()
		if fms > HITCH_MS:
			hitches += 1
			# attributable to streaming when the streamer took a real share of that frame
			if sms > 2.0 or sms > fms * 0.25:
				hitches_streaming += 1
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
		"timestamp": Time.get_datetime_string_from_system(true),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"cpu_cores": OS.get_processor_count(),
		"speed_mps": speed,
		"route_m": snappedf(total_len, 0.1),
		"frames": frames,
		"frame_ms": {"p50": _pct(frame_ms, 0.5), "p99": _pct(frame_ms, 0.99), "max": frame_ms.max()},
		"stream_ms": {"p50": _pct(stream_ms, 0.5), "p99": _pct(stream_ms, 0.99), "p999": _pct(stream_ms, 0.999), "max": stream_ms.max()},
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
	print("  phases µs max %s, unload one chunk max %d µs" % [report["phase_usec_max"], report["unload_usec_max"]])
	print("  frames over the 2 ms streaming budget: %d of %d (%.2f %%); worst [stream ms, frame ms, [refresh, collect, instantiate, unload µs, step]]: %s" % [over_budget, frames, 100.0 * over_budget / maxf(frames, 1), worst])
	print("  chunks        %d generated (avg %.1f ms, max %.1f ms in workers), %d unloaded, %d loaded at the end, %d sync loads, ground missing %d frames" % [report["chunks_generated"], report["gen_ms_avg"], report["gen_ms_max"], report["chunks_unloaded"], report["loaded_chunks_end"], report["sync_loads"], missing_ground])
	print("  memory        RSS max %.0f MB, static %.0f MB, video %.0f MB, nodes %d, draw calls p50 %d" % [report["rss_mb_max"], report["memory_static_mb"], report["video_mem_mb"], int(report["nodes"]), int(report["draw_calls_p50"])])
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
	var checks := [["stream_ms_p99_max", report["stream_ms"]["p99"]], ["stream_ms_p999_max", report["stream_ms"]["p999"]],
		["stream_ms_max", report["stream_ms"]["max"]], ["frames_over_stream_budget_pct_max", report["frames_over_stream_budget_pct"]],
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


static func _pct(values: Array[float], p: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(floor(p * float(sorted.size() - 1))), 0, sorted.size() - 1)]
