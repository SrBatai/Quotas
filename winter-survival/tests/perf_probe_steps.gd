extends RefCounted
## Perf probe body (loaded at runtime by tests/perf_probe.gd): fixed clearing scene, fixed clock/weather/camera;
## samples draw calls, objects, primitives and frame times; writes JSON; compares with perf_budgets.json.

const WARMUP_FRAMES := 90
const SAMPLE_FRAMES := 180

var tree: SceneTree
var opts: Dictionary = {}
var _ready: bool = false


func run(p_tree: SceneTree, p_opts: Dictionary) -> void:
	tree = p_tree
	opts = p_opts
	await tree.process_frame
	if bool(opts["placeholders"]):
		Assets.force_placeholders = true
	Events.world_ready.connect(func() -> void: _ready = true)
	GameFlow.play_offline()   # M1: the authoritative local server runs in-process
	var waited := 0
	while not _ready and waited < 900:
		await tree.process_frame
		waited += 1
	if not _ready:
		print("FAIL: world never became ready")
		tree.quit(1)
		return
	waited = 0
	while GameFlow.local_player() == null and waited < 600:
		await tree.process_frame
		waited += 1
	await tree.process_frame
	await tree.process_frame
	var game := tree.current_scene
	var player: Node3D = GameFlow.local_player()
	var world: Node = game.get_node("World")
	if player == null:
		print("FAIL: no local player")
		tree.quit(1)
		return
	# Fixed conditions: day 1 11:00, clear, no scheduler, no wolves, player still at the porch spawn.
	WorldState.instance.set_time(1, 11.0)
	world.get_node("Weather").scheduler_enabled = false
	world.get_node("WolfSpawner").enabled = false
	Events.notify.emit("", 0.1)
	var spawn: Vector3 = world.get_spawn_point()
	player.global_position = spawn + Vector3(0, 0.15, 0)
	player.set("input_enabled", false)
	WorldState.instance.running = false
	var rig := CameraRig.active()
	if rig != null:
		rig.snap_to_player()
	for i in WARMUP_FRAMES:
		await tree.process_frame
	var draw_calls: Array[float] = []
	var objects: Array[float] = []
	var prims: Array[float] = []
	var frame_ms: Array[float] = []
	var last_us := Time.get_ticks_usec()
	for i in SAMPLE_FRAMES:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - last_us) / 1000.0)
		last_us = now
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var cam_pos := Vector3.ZERO
	var cam_far := 0.0
	if rig != null:
		cam_pos = rig.camera.global_position
		cam_far = rig.camera.far
	var report := {
		"label": String(opts["label"]),
		"timestamp": Time.get_datetime_string_from_system(true),
		"godot": Engine.get_version_info()["string"],
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"physics_engine": str(ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT")),
		"placeholders": bool(opts["placeholders"]),
		"scene": "res://scenes/main/game.tscn",
		"camera": {"position": _v3(cam_pos), "yaw_deg": Balance.CAMERA_YAW_DEG, "pitch_deg": Balance.CAMERA_PITCH_DEG,
			"dist": Balance.CAMERA_DIST, "far": cam_far},
		"frames": SAMPLE_FRAMES,
		"draw_calls": {"median": _median(draw_calls), "max": draw_calls.max(), "min": draw_calls.min()},
		"objects": {"median": _median(objects), "max": objects.max()},
		"primitives": {"median": _median(prims), "max": prims.max()},
		"frame_ms": {"p50": _percentile(frame_ms, 0.5), "p99": _percentile(frame_ms, 0.99), "max": frame_ms.max()},
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"physics_active_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"memory_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"mesh_surfaces": _count_surfaces(game),
	}
	print("== perf probe (%s, %s, physics=%s, placeholders=%s)" % [report["rendering_method"], report["rendering_driver"], report["physics_engine"], report["placeholders"]])
	print("  draw calls  median %d (min %d / max %d)" % [int(report["draw_calls"]["median"]), int(report["draw_calls"]["min"]), int(report["draw_calls"]["max"])])
	print("  objects     median %d" % int(report["objects"]["median"]))
	print("  primitives  median %d" % int(report["primitives"]["median"]))
	print("  frame ms    p50 %.2f  p99 %.2f  max %.2f" % [report["frame_ms"]["p50"], report["frame_ms"]["p99"], report["frame_ms"]["max"]])
	print("  nodes %d  mesh surfaces %d  physics objects %d" % [int(report["nodes"]), int(report["mesh_surfaces"]), int(report["physics_active_objects"])])
	var ok := true
	if bool(opts["check"]):
		ok = _check_budgets(report)
	_write(report)
	print("== perf probe %s" % ("OK" if ok else "FAILED"))
	tree.quit(0 if ok else 1)


func _check_budgets(report: Dictionary) -> bool:
	var path := String(opts["budgets"])
	if not FileAccess.file_exists(path):
		print("  (no budgets file at %s)" % path)
		return true
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary) or not data.has("perf_probe"):
		print("  (budgets file has no perf_probe section)")
		return true
	var b: Dictionary = data["perf_probe"]
	var ok := true
	var checks := [
		["draw_calls_max", report["draw_calls"]["median"]],
		["objects_max", report["objects"]["median"]],
		["primitives_max", report["primitives"]["median"]],
		["nodes_max", report["nodes"]],
	]
	if bool(b.get("enforce_gpu", false)):
		checks.append(["frame_ms_p99_max", report["frame_ms"]["p99"]])
	for c in checks:
		if not b.has(c[0]):
			continue
		var limit := float(b[c[0]])
		var value := float(c[1])
		if value > limit:
			ok = false
			print("FAIL: %s = %.1f > budget %.1f" % [c[0], value, limit])
		else:
			print("  ok   %s = %.1f <= %.1f" % [c[0], value, limit])
	return ok


func _write(report: Dictionary) -> void:
	var path := String(opts["out"])
	if not path.begins_with("res://") and not path.begins_with("user://") and not path.begins_with("/"):
		path = "res://" + path
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("FAIL: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("  wrote %s" % path)


func _count_surfaces(root: Node) -> int:
	var n := 0
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		n += (root as MeshInstance3D).mesh.get_surface_count()
	for c in root.get_children():
		n += _count_surfaces(c)
	return n


static func _median(values: Array[float]) -> float:
	return _percentile(values, 0.5)


static func _percentile(values: Array[float], p: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var idx := int(floor(p * float(sorted.size() - 1)))
	return sorted[clampi(idx, 0, sorted.size() - 1)]


static func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
