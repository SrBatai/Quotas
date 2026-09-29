extends RefCounted
## Body of tests/g2b_bench.gd (G2b): see the runner. The city view and the weather switches come from
## tests/g2b_shots.gd (the same presets the screenshots use).

const WARM := 6
const SAMPLE := 12
const RATIO_MAX := 1.25
const LUT_US_MAX := 100.0

var tree: SceneTree
var opts: Dictionary
var shots: RefCounted
var world: World
var player: Player
var _ready := false


func run(p_tree: SceneTree, p_opts: Dictionary) -> void:
	tree = p_tree
	opts = p_opts
	await tree.process_frame
	if not Quality.is_compat_renderer():
		Quality.set_preset(&"alto", false)   # lavapipe is a CPU device (-> compat): measure the real Forward+ preset
	Events.world_ready.connect(func() -> void:
		_ready = true
		var w := tree.current_scene.get_node_or_null("World/Weather") as Weather
		if w != null:
			w.scheduler_enabled = false
			w.cancel())
	GameFlow.play_offline()
	var waited := 0
	while (not _ready or GameFlow.local_player() == null) and waited < 1800:
		await tree.process_frame
		waited += 1
	await tree.process_frame
	var game := tree.current_scene
	world = game.get_node("World")
	player = GameFlow.local_player()
	if player == null or Atmosphere.instance == null:
		print("FAIL: no player / no Atmosphere (display needed)")
		tree.quit(1)
		return
	Events.notify.emit("", 0.1)
	shots = load("res://tests/g2b_shots.gd").new()
	var no_flags: Array[String] = []
	shots.set("tree", tree)
	shots.set("world", world)
	shots.set("player", player)
	shots.set("flags", no_flags)
	for n in ["WolfSpawner", "DeerSpawner"]:
		world.get_node(n).enabled = false
	if Director.instance != null:
		Director.instance.enabled = false
	if PopulationManager.instance != null:
		PopulationManager.instance.enabled = false
	if ZombieSystem.instance != null:
		ZombieSystem.instance.clear_all()
	var ui := game.get_node_or_null("UI") as CanvasLayer
	if ui != null:
		ui.visible = false
	WorldState.instance.set_time(3, 11.0)
	await shots.call("_to_city", Vector3(2667.0, 0.0, -390.0), 24.0)
	var ok := true
	if str(opts["mode"]) == "depth":
		ok = await _depth()
	else:
		ok = await _ratio()
	print("== g2b bench %s %s" % [opts["mode"], "OK" if ok else "FAILED"])
	tree.quit(0 if ok else 1)


# ------------------------------------------------------------------ frame cost: blizzard vs day in the city
func _sample(cond: Array) -> Dictionary:
	Atmosphere.instance.shadow_cut = str(cond[0]) != "blizzard_shadows"
	await shots.call("set_conditions", float(cond[1]), str(cond[2]))
	var rig := CameraRig.active()
	if rig != null:
		rig.snap_to_player()
	var vp := tree.root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in WARM:
		await tree.process_frame
	var ms: Array[float] = []
	var gpu: Array[float] = []
	var dc: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in SAMPLE:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		ms.append(float(now - last) / 1000.0)
		last = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		dc.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	return {"ms": _median(ms), "gpu": _median(gpu), "dc": _median(dc)}


func _ratio() -> bool:
	var atmo := Atmosphere.instance
	# blizzard_shadows: the same blizzard without the whiteout shadow cut (information: what the cut saves)
	var conds := [["day", 11.0, "clear"], ["blizzard", 11.0, "blizzard"], ["blizzard_shadows", 11.0, "blizzard"], ["night", 22.5, "clear"], ["night_blizzard", 22.5, "blizzard"]]
	var res := {}
	for c in conds:
		res[c[0]] = {"ms": [], "gpu": [], "dc": []}
	for r in int(opts["rounds"]):
		for c in conds:
			var s: Dictionary = await _sample(c)
			for k in ["ms", "gpu", "dc"]:
				(res[c[0]][k] as Array).append(s[k])
			print("  round %d %-15s frame %7.1f ms  gpu %7.1f ms  draw calls %d  vol %s (%.4f)" % [r, c[0], s["ms"], s["gpu"], int(s["dc"]), atmo.volumetric_on, atmo.volumetric_density])
	var out := {"renderer": RenderingServer.get_current_rendering_method(), "preset": String(Quality.preset), "rounds": int(opts["rounds"])}
	for c in conds:
		out[c[0]] = {"ms": _median(res[c[0]]["ms"]), "gpu": _median(res[c[0]]["gpu"]), "dc": _median(res[c[0]]["dc"])}
	var day: Dictionary = out["day"]
	var bz: Dictionary = out["blizzard"]
	# the ratio of each round (day and blizzard measured a minute apart), then the median: other processes on the
	# machine change the absolute frame time from minute to minute far more than the scene does
	var per_round: Array = []
	for r in (res["day"]["ms"] as Array).size():
		per_round.append(float(res["blizzard"]["ms"][r]) / maxf(float(res["day"]["ms"][r]), 0.001))
	out["ratio_per_round"] = per_round
	var ratio := _median(per_round)
	var gratio := float(bz["gpu"]) / maxf(float(day["gpu"]), 0.001) if float(day["gpu"]) > 0.0 else 0.0
	var nratio := float(out["night"]["ms"]) / maxf(float(day["ms"]), 0.001)
	var nbratio := float(out["night_blizzard"]["ms"]) / maxf(float(day["ms"]), 0.001)
	out["ratio_blizzard_day"] = ratio
	out["ratio_blizzard_day_gpu"] = gratio
	out["ratio_night_day"] = nratio
	out["ratio_night_blizzard_day"] = nbratio
	var sratio := float(out["blizzard_shadows"]["ms"]) / maxf(float(day["ms"]), 0.001)
	out["ratio_blizzard_with_shadows_day"] = sratio
	print("  city frame ms (median of %d rounds): day %.1f, blizzard %.1f, night %.1f, night blizzard %.1f" % [int(opts["rounds"]), day["ms"], bz["ms"], out["night"]["ms"], out["night_blizzard"]["ms"]])
	print("  ratio blizzard / day %.3f (median of the rounds %s; gpu time %.3f), blizzard without the whiteout shadow cut / day %.3f, night / day %.3f, night blizzard / day %.3f" % [ratio, per_round, gratio, sratio, nratio, nbratio])
	# the LUT blend inside the real frame loop: force transitions and time every step
	var lut_us := await _lut_in_loop()
	out["lut_step_us_median"] = lut_us[0]
	out["lut_step_us_p95"] = lut_us[1]
	out["lut_rest_us"] = lut_us[2]
	_write(out)
	var ok := true
	if ratio > RATIO_MAX:
		print("FAIL: blizzard costs %.1f %% over the day (limit +%.0f %%)" % [(ratio - 1.0) * 100.0, (RATIO_MAX - 1.0) * 100.0])
		ok = false
	else:
		print("  ok   blizzard in the city %+.1f %% over the day (limit +%.0f %%)" % [(ratio - 1.0) * 100.0, (RATIO_MAX - 1.0) * 100.0])
	if lut_us[0] > LUT_US_MAX:
		print("FAIL: LUT blend step median %.0f µs > %.0f" % [lut_us[0], LUT_US_MAX])
		ok = false
	else:
		print("  ok   LUT blend step median %.0f µs, p95 %.0f µs; at rest %.0f µs" % [lut_us[0], lut_us[1], lut_us[2]])
	return ok


func _lut_in_loop() -> Array:
	var atmo := Atmosphere.instance
	var g := atmo.lut
	var steps: Array[float] = []
	for hour in [18.4, 19.8]:
		atmo.overcast_override = 0.5
		WorldState.instance.set_time(3, hour)
		(world.get_node("DayNight") as DayNight).apply(hour)
		var f := 0
		while f < 150:
			await tree.process_frame
			f += 1
			if g.last_step_usec > 0:
				steps.append(float(g.last_step_usec))
			if not g.is_busy():
				break
	var rest := 0.0
	for i in 20:
		await tree.process_frame
		rest += float(g.last_step_usec)
	steps.sort()
	if steps.is_empty():
		return [0.0, 0.0, rest]
	return [steps[steps.size() / 2], steps[int(steps.size() * 0.95)], rest]


# ------------------------------------------------------------------ depth: how far toward the fog colour, far vs near
## Three captures per condition: A as the game draws it, B without any fog, C with the fog saturated (density 2: every
## surface becomes the fog colour). Gate: the share of local contrast the fog takes away in the far (top) and near
## (bottom) thirds of the frame, `depth` = far − near (aerial perspective: the far street fades, the near one does not).
## Information: t = (A − B)·(C − B) / |C − B|², how far the fog moved each pixel toward the exponential fog's colour.
## Compatibility has no volumetric fog: it keeps the depth if its far share and its depth reach 80 % of Forward+'s
## (run_g2b_bench.sh compares the two JSON files).
func _depth() -> bool:
	var out := {"renderer": RenderingServer.get_current_rendering_method(), "preset": String(Quality.preset)}
	var dn: DayNight = world.get_node("DayNight")
	var e := (world.get_node("Env") as WorldEnvironment).environment
	var sf := world.get_node_or_null("Snowfall") as Node3D
	var drift := world.get_node_or_null("SnowDrift") as Node3D
	var shots_dir := str(opts["shots"])
	var ok := true
	for c in [["night", 22.5, "clear"], ["dusk", 19.1, "overcast"], ["blizzard", 15.0, "blizzard"]]:
		await shots.call("set_conditions", float(c[1]), str(c[2]))
		# the falling snow is noise for this measure (random flakes near and far): off for the three captures
		if sf != null:
			sf.visible = false
		if drift != null:
			drift.visible = false
		var rig := CameraRig.active()
		if rig != null:
			rig.snap_to_player()
		for i in 10:
			await tree.process_frame
		var a := await _grab()
		var vol := e.volumetric_fog_enabled
		dn.set_process(false)
		var keep := [e.fog_density, e.fog_height_density, e.fog_aerial_perspective, e.fog_sun_scatter]
		e.fog_enabled = false
		e.volumetric_fog_enabled = false
		var b := await _grab()
		e.fog_enabled = true
		e.fog_density = 2.0
		e.fog_height_density = 0.0
		e.fog_aerial_perspective = 0.0
		e.fog_sun_scatter = 0.0
		var sat := await _grab()
		e.fog_density = keep[0]
		e.fog_height_density = keep[1]
		e.fog_aerial_perspective = keep[2]
		e.fog_sun_scatter = keep[3]
		dn.set_process(true)
		if sf != null:
			sf.visible = true
		if drift != null:
			drift.visible = true
		# the gate: local contrast the fog takes away (1 − contrast with fog / without), far third vs near third —
		# independent of the fog's colour, so Forward+'s volumetric fog (lit, not the exponential colour) counts too
		var far := 1.0 - _contrast(a, 0.0, 0.33) / maxf(_contrast(b, 0.0, 0.33), 1e-4)
		var near := 1.0 - _contrast(a, 0.67, 1.0) / maxf(_contrast(b, 0.67, 1.0), 1e-4)
		# information: how far toward the exponential fog's own colour (Compatibility's only fog)
		var t_far := _fog_t(a, b, sat, 0.0, 0.33)
		var t_near := _fog_t(a, b, sat, 0.67, 1.0)
		out[c[0]] = {"far": far, "near": near, "depth": far - near, "volumetric": vol, "t_far": t_far, "t_near": t_near}
		print("  %-9s contrast the fog takes: far %.3f near %.3f -> depth %.3f (toward the fog colour: far %.3f near %.3f; volumetric %s)" % [c[0], far, near, far - near, t_far, t_near, vol])
		if far <= near:
			print("FAIL: %s: the far third is not foggier than the near third" % c[0])
			ok = false
		if shots_dir != "":
			DirAccess.make_dir_recursive_absolute(shots_dir)
			var suffix := "compat" if Quality.is_compat_renderer() else "forward"
			a.save_png("%s/g2b_depth_%s_%s.png" % [shots_dir, c[0], suffix])
	_write(out)
	return ok


func _grab() -> Image:
	for i in 5:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	return tree.root.get_viewport().get_texture().get_image()


## Mean local contrast of a horizontal band [y0, y1]: the luma standard deviation inside 16 × 16 px blocks (sampled
## every 4 px), averaged over the blocks.
static func _contrast(img: Image, y0: float, y1: float) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var total := 0.0
	var blocks := 0
	for by in range(int(h * y0), int(h * y1) - 15, 16):
		for bx in range(0, w - 15, 16):
			var s1 := 0.0
			var s2 := 0.0
			for y in range(by, by + 16, 4):
				for x in range(bx, bx + 16, 4):
					var c := img.get_pixel(x, y)
					var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
					s1 += l
					s2 += l * l
			var m := s1 / 16.0
			total += sqrt(maxf(s2 / 16.0 - m * m, 0.0))
			blocks += 1
	return total / float(maxi(blocks, 1))


## Mean fog fraction t in a horizontal band [y0, y1] (fractions of the height); pixels whose fog colour is too close to
## their own colour (|C − B| < 0.06) carry no information and are skipped.
static func _fog_t(a: Image, b: Image, c: Image, y0: float, y1: float) -> float:
	var w := a.get_width()
	var h := a.get_height()
	var sum := 0.0
	var n := 0
	for y in range(int(h * y0), int(h * y1), 4):
		for x in range(0, w, 4):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var cc := c.get_pixel(x, y)
			var d := Vector3(cc.r - cb.r, cc.g - cb.g, cc.b - cb.b)
			var l2 := d.length_squared()
			if l2 < 0.0036:
				continue
			var t := Vector3(ca.r - cb.r, ca.g - cb.g, ca.b - cb.b).dot(d) / l2
			sum += clampf(t, 0.0, 1.0)
			n += 1
	return sum / float(maxi(n, 1))


static func _median(v: Array) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	return float(s[s.size() / 2])


func _write(d: Dictionary) -> void:
	var f := FileAccess.open(str(opts["json"]), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d, "  "))
		f.close()
		print("  wrote %s" % opts["json"])
