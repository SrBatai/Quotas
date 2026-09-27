extends RefCounted
## City bench body (loaded by tests/city_bench_run.gd). Modes:
##   gate   visibility of the local player / zombies through the «corte urbano» (flat key colours, like doc 09
##          §3.8): per view × zoom, pixels of the player and zombies with the buildings (cut on) against a
##          reference frame without buildings; blocking: player ≥ 99 % visible at 24 / 38 m (default profile) and at
##          the city profile's max zoom, zombies ≥ 95 % readable (visible or silhouette). Also: the cut keeps the
##          tower shadows on the street (mean luminance around the player's feet within 5 % of the frame where the
##          buildings only cast shadows), and nothing beyond the player is removed.
##   perf   the real look (DayNight, windows, lamps, silhouettes) day and night: draw calls / primitives against
##          tests/city_bench_budgets.json (blocking) and frame / render times with the cut on vs off (informative:
##          software rasterisers only give proportions, doc 06 §5.1).
##   shots  screenshot presets: city_day, city_night, city_cut, city_inside, city_rooftop, city_hlod,
##          profile_compare (default vs city).

const BENCH := "res://tests/city_bench/city_bench.tscn"
const W := 1280
const H := 720
## Edge pixels of the key capsules that aliasing can flip between two frames (full-resolution counts).
const PIXEL_SLACK := 6

var tree: SceneTree
var opts: Dictionary
var bench: Node3D
var ok: bool = true
var results: Array = []


func run(p_tree: SceneTree, p_opts: Dictionary) -> void:
	tree = p_tree
	opts = p_opts
	await tree.process_frame
	if not Quality.is_compat_renderer():
		Quality.set_preset(&"alto", false)   # lavapipe is a CPU device (Quality.detect -> compat): measure alto
	print("== city bench %s (%s, %s, preset %s)" % [opts["mode"], RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name(), Quality.preset])
	if ResourceLoader.exists("res://assets/models/city/towers/tower_d.glb"):
		print("  (A1 art city set present: art towers / vehicles / lamps used where the bench places them)")
	match str(opts["mode"]):
		"gate":
			await _gate()
		"perf":
			await _perf()
		"shots":
			await _shots(str(opts["preset"]), str(opts["out"]))
		_:
			print("FAIL: unknown mode %s" % opts["mode"])
			ok = false
	if str(opts["json"]) != "":
		var f := FileAccess.open(str(opts["json"]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"mode": opts["mode"], "renderer": RenderingServer.get_current_rendering_method(), "results": results}, "  "))
	print("== city bench %s %s" % [opts["mode"], "OK" if ok else "FAILED"])
	tree.quit(0 if ok else 1)


func _spawn(measure: bool) -> void:
	bench = (load(BENCH) as PackedScene).instantiate() as Node3D
	tree.root.add_child(bench)
	if not bench.has_method("build"):
		print("FAIL: the city bench scene did not load (script errors above)")
		ok = false
		tree.quit(1)
		return
	bench.call("build", measure)
	for i in 3:
		await tree.physics_frame
		await tree.process_frame


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return tree.root.get_viewport().get_texture().get_image()


# ------------------------------------------------------------------ gate
func _gate() -> void:
	await _spawn(true)
	bench.call("flat_environment")
	var vp := tree.root.get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED
	var sun: DirectionalLight3D = bench.get("sun")
	sun.visible = true
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.look_at_from_position(Vector3.ZERO, Vector3(-1.0, -0.55, -1.0), Vector3.UP)   # the camera-side tower shades the avenue
	var sil: Silhouettes = bench.get("sil")
	sil.tint_override = {"player": Color(0, 1, 1, 1), "zombie": Color(1, 0.5, 0, 1)}
	var cut: CityCut = bench.get("cut")
	var cases := [["canyon", 16.0, &"default"], ["canyon", 24.0, &"default"], ["canyon", 38.0, &"default"],
		["canyon", 44.0, &"city"], ["crossing", 24.0, &"default"], ["crossing", 38.0, &"default"],
		["crossing", 44.0, &"city"], ["rooftop", 24.0, &"rooftop"], ["rooftop", 38.0, &"rooftop"], ["rooftop", 50.0, &"rooftop"],
		["inside", 24.0, &"default"], ["inside", 38.0, &"default"],
		["north", 24.0, &"default"], ["north", 38.0, &"default"], ["north", 44.0, &"city"]]
	print("  view      dist profile   player vis/read   zombies vis/read   (no cut: player / zombies)   cam inside")
	for c in cases:
		var view: String = c[0]
		var dist: float = c[1]
		var prof: StringName = c[2]
		bench.call("set_view", view, dist, prof)
		# reference: no occluders
		bench.call("set_occluders_visible", false)
		sil.enabled = false
		sil.poll()
		await _frames(4)
		var ref := _count(await _capture())
		var cam_ref: Vector3 = (bench.get("rig") as CameraRig).camera.global_position
		# no cut (what the doc 09 prototype calls "std")
		bench.call("set_occluders_visible", true)
		cut.enabled = false
		cut.update(0.0)
		await _frames(4)
		var nocut := _count(await _capture())
		# the corte urbano + silhouettes
		cut.enabled = true
		sil.enabled = true
		sil.poll()
		bench.call("set_view", view, dist, prof)
		await _frames(4)
		var img := await _capture()
		var got := _count(img)
		# the comparison is only meaningful with the camera where it was for the reference frame
		var drift := (bench.get("rig") as CameraRig).camera.global_position.distance_to(cam_ref)
		if drift > 0.001:
			ok = false
			print("FAIL: %s %.0f m: the camera moved %.4f m between the reference and the measured frame" % [view, dist, drift])
		var pr := maxf(1.0, float(ref["player"]))
		var zr := maxf(1.0, float(ref["zombie"]))
		var r := {
			"view": view, "dist": dist, "profile": String(prof),
			"ref_player_px": ref["player"], "ref_zombie_px": ref["zombie"],
			"player_visible": snappedf(float(got["player"]) / pr, 0.001),
			"player_readable": snappedf(float(got["player"] + got["player_sil"]) / pr, 0.001),
			"zombies_visible": snappedf(float(got["zombie"]) / zr, 0.001),
			"zombies_readable": snappedf(float(got["zombie"] + got["zombie_sil"]) / zr, 0.001),
			"nocut_player_visible": snappedf(float(nocut["player"]) / pr, 0.001),
			"nocut_zombies_visible": snappedf(float(nocut["zombie"]) / zr, 0.001),
			"camera_inside": _camera_inside(),
		}
		results.append(r)
		# player: >= 99 % (or at most PIXEL_SLACK edge pixels lost to aliasing) from 24 m up, every view and profile;
		# zombies: >= 95 % readable at 24–38 m in the street views (doc 09 W0 acceptance), when enough of them are
		# on screen. From a roof or an upper floor the zombies at the foot of the player's own building are hidden
		# by its facade below the player (never cut, and not perceived: no line of sight), so those rows only report.
		var gated := dist >= 24.0
		var lost := int(ref["player"]) - int(got["player"])
		var pass_p := float(r["player_visible"]) >= 0.99 or lost <= PIXEL_SLACK or not gated
		var street := view == "canyon" or view == "crossing" or view == "north"
		var pass_z := float(r["zombies_readable"]) >= 0.95 or not gated or not street or dist > 38.0 or float(ref["zombie"]) < 200.0
		r["zombies_gated"] = gated and street and dist <= 38.0 and float(ref["zombie"]) >= 200.0
		if not pass_p or not pass_z:
			ok = false
			img.save_png("/tmp/ventisca_city_gate_%s_%d.png" % [view, int(dist)])
		print("  %-9s %4.0f %-9s %5.1f %% / %5.1f %%    %5.1f %% / %5.1f %%     (%5.1f %% / %5.1f %%)            %s   %s" % [view, dist, prof,
			100.0 * float(r["player_visible"]), 100.0 * float(r["player_readable"]), 100.0 * float(r["zombies_visible"]),
			100.0 * float(r["zombies_readable"]), 100.0 * float(r["nocut_player_visible"]), 100.0 * float(r["nocut_zombies_visible"]),
			str(r["camera_inside"]), "ok" if pass_p and pass_z else "FAIL"])
	await _shadow_check()
	await _beyond_check()


## Name of the building that contains the camera ("" = none): the failure mode the cut exists for.
func _camera_inside() -> String:
	var cam := (bench.get("rig") as CameraRig).camera.global_position
	for b in CityCut.buildings():
		var cb := b as CityBuilding
		if cb.contains(cam):
			return String(cb.root.name)
	return ""


## The cut never runs in the shadow pass: around the player's feet (in the camera-side tower's shadow) the street
## must be as dark with the cut as when the buildings only cast shadows.
func _shadow_check() -> void:
	bench.call("set_view", "canyon", 24.0, &"default")
	var cam := (bench.get("rig") as CameraRig).camera
	var player: Node3D = bench.get("player")
	var cut: CityCut = bench.get("cut")
	var region := Rect2i()
	var centre := cam.unproject_position(player.global_position) * Vector2(float(W) / 1280.0, float(H) / 720.0)
	region = Rect2i(int(centre.x) - 80, int(centre.y) - 20, 160, 60)
	# (a) buildings cast only (pieces hidden, ShadowProxy kept)
	_buildings_pieces(false)
	cut.enabled = true
	await _frames(4)
	var a := _luma(await _capture(), region)
	# (b) the cut on
	_buildings_pieces(true)
	await _frames(4)
	var b := _luma(await _capture(), region)
	# (d) no buildings at all: the street in full sun (proves the region is in shadow)
	for n in bench.get("buildings"):
		(n as Node3D).visible = false
	await _frames(4)
	var d := _luma(await _capture(), region)
	for n in bench.get("buildings"):
		(n as Node3D).visible = true
	var ratio := b / maxf(a, 1e-4)
	var sun_gain := d / maxf(a, 1e-4)
	var pass_s := absf(ratio - 1.0) <= 0.05
	if not pass_s:
		ok = false
	results.append({"check": "shadow", "luma_shadow_only": snappedf(a, 0.001), "luma_cut": snappedf(b, 0.001),
		"luma_no_buildings": snappedf(d, 0.001), "ratio": snappedf(ratio, 0.001)})
	print("  shadow under the cut tower: luma %.3f (cut) vs %.3f (shadow casters only) -> ratio %.3f; full sun %.3f (x%.2f)   %s%s" % [b, a, ratio, d, sun_gain,
		"ok" if pass_s else "FAIL", "" if sun_gain > 1.1 else " (warning: the region is not clearly in shadow)"])


func _buildings_pieces(v: bool) -> void:
	for n in bench.get("buildings"):
		for c in (n as Node3D).get_children():
			if c is Node3D and CityBuilding.canonical(String(c.name)) != CityBuilding.PROXY and not String(c.name).begins_with("Col"):
				(c as Node3D).visible = v


## Nothing on the far side of the player is cut: the pure-GDScript mirror of the shader agrees with the frame.
func _beyond_check() -> void:
	bench.call("set_view", "canyon", 24.0, &"default")
	var cut: CityCut = bench.get("cut")
	var far_face := Vector3(-8.0, 12.0, 24.0)       # MidRise facade across the avenue, 12 m up
	var near_face := Vector3(8.0, 12.0, 24.0)       # TowerCam facade between the camera and the player
	var above := Vector3(8.0, 2.0, 24.0)            # below the cut (ground floor of the tower)
	var f_far := CityCut.fade_at(far_face, cut.state["camera"], cut.state, CityCut.Kind.STRUCT, 0.0, 3.3, 3.0)
	var f_near := CityCut.fade_at(near_face, cut.state["camera"], cut.state, CityCut.Kind.STRUCT, 0.0, 4.3, 3.0)
	var f_low := CityCut.fade_at(above, cut.state["camera"], cut.state, CityCut.Kind.STRUCT, 0.0, 4.3, 3.0)
	var pass_b := f_far < 0.01 and f_near > 0.97 and f_low < 0.01
	if not pass_b:
		ok = false
	results.append({"check": "beyond", "fade_far_facade": f_far, "fade_near_facade": f_near, "fade_ground_floor": f_low})
	print("  fade: far facade %.2f, camera-side facade %.2f, camera-side ground floor %.2f   %s" % [f_far, f_near, f_low, "ok" if pass_b else "FAIL"])


## Pixel counts by key colour at full resolution.
func _count(img: Image) -> Dictionary:
	var small := img.duplicate() as Image
	small.convert(Image.FORMAT_RGB8)
	if small.get_width() != W or small.get_height() != H:
		small.resize(W, H, Image.INTERPOLATE_NEAREST)
	var data := small.get_data()
	var res := {"player": 0, "zombie": 0, "player_sil": 0, "zombie_sil": 0}
	for i in range(0, data.size(), 3):
		var r := data[i]
		var g := data[i + 1]
		var b := data[i + 2]
		if r > 200 and g < 60 and b < 60:
			res["zombie"] += 1
		elif g > 200 and r < 60 and b < 60:
			res["player"] += 1
		elif g > 200 and b > 200 and r < 60:
			res["player_sil"] += 1
		elif r > 200 and g > 100 and g < 160 and b < 60:
			res["zombie_sil"] += 1
	return res


func _luma(img: Image, region: Rect2i) -> float:
	var small := img.duplicate() as Image
	small.convert(Image.FORMAT_RGB8)
	small.resize(W, H, Image.INTERPOLATE_NEAREST)
	var sum := 0.0
	var n := 0
	for y in range(maxi(region.position.y, 0), mini(region.end.y, H)):
		for x in range(maxi(region.position.x, 0), mini(region.end.x, W)):
			var c := small.get_pixel(x, y)
			# skip the key colours (characters, silhouettes)
			if (c.g > 0.78 and c.r < 0.24) or (c.r > 0.78 and c.b < 0.24):
				continue
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return sum / maxf(1.0, float(n))


# ------------------------------------------------------------------ perf
func _perf() -> void:
	await _spawn(false)
	var budgets := _budgets()
	var cut: CityCut = bench.get("cut")
	var renderer := "compat" if Quality.is_compat_renderer() else "forward"
	var frames := int(opts["frames"])
	var vp_rid := tree.root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	var rounds := maxi(1, int(opts.get("rounds", 1)))
	var variants := ["on", "eval", "off", "g1"]
	var rows := []
	var summary := []
	for hour in [11.0, 22.5]:
		bench.call("set_hour", hour)
		bench.call("set_view", "canyon", 24.0, &"city")
		await _frames(8)
		# on = the real cut; eval = every term evaluated, nothing removed (same pixels as off); off = globals off
		# (early out, struct material still cull_disabled); g1 = the plain world_vcol material on the buildings.
		# Interleaved over `rounds` rounds so a slow patch of a shared machine hits every variant alike.
		var p50 := {}
		for v in variants:
			p50[v] = []
		for r in rounds:
			for variant in variants:
				cut.enabled = variant == "on" or variant == "eval"
				cut.eval_only = variant == "eval"
				bench.call("set_g1_materials", variant == "g1")
				await _frames(6)
				var m := await _measure(frames, vp_rid)
				m["hour"] = hour
				m["cut"] = variant
				m["round"] = r
				m["lamp_lights"] = (bench.get("lights") as CityLights).real_lights_on()
				(p50[variant] as Array).append(float(m["frame_ms_p50"]))
				rows.append(m)
				results.append(m)
				print("  %s %5.1f h cut %-4s  draw calls %4d  primitives %7d  objects %4d  frame ms p50 %7.1f  render cpu %6.2f gpu %6.2f  lamp lights %d" % [
					renderer, hour, variant, int(m["draw_calls"]), int(m["primitives"]), int(m["objects"]), float(m["frame_ms_p50"]),
					float(m["render_cpu_ms"]), float(m["render_gpu_ms"]), int(m["lamp_lights"])])
		var med := {}
		for v in variants:
			var arr: Array = p50[v]
			arr.sort()
			med[v] = float(arr[arr.size() / 2])
		summary.append({"hour": hour, "median_ms": med})
	cut.enabled = true
	cut.eval_only = false
	bench.call("set_g1_materials", false)
	# budgets: draw calls / primitives (blocking), cut cost (informative)
	var b: Dictionary = budgets.get(renderer, {})
	for m in rows:
		if str(m["cut"]) != "on" or int(m["round"]) != 0:
			continue
		for key in [["draw_calls", "draw_calls_max"], ["primitives", "primitives_max"]]:
			if b.has(key[1]):
				var lim := float(b[key[1]])
				var v := float(m[key[0]])
				if v > lim:
					ok = false
					print("FAIL: %s %.0f > budget %.0f (%s, %.1f h)" % [key[0], v, lim, renderer, float(m["hour"])])
				else:
					print("  ok   %s %.0f <= %.0f (%.1f h)" % [key[0], v, lim, float(m["hour"])])
	for sm in summary:
		var med: Dictionary = sm["median_ms"]
		var base := maxf(float(med["g1"]), 0.001)
		var alu := float(med["eval"]) / base - 1.0
		var off := float(med["off"]) / base - 1.0
		var content := float(med["on"]) / base - 1.0
		print("  info cut at %.1f h vs the G1 material (median of %d): struct material, cut off %+.1f %%, evaluating the cut %+.1f %% (doc 09 budget %.0f %%), cut on with the street revealed %+.1f %% (informative: software rasteriser)" % [
			float(sm["hour"]), rounds, off * 100.0, alu * 100.0, float(b.get("cut_cost_pct_info", 10.0)), content * 100.0])
		results.append({"hour": sm["hour"], "rounds": rounds, "median_ms": med, "struct_off_pct": snappedf(off * 100.0, 0.1),
			"cut_shader_cost_pct": snappedf(alu * 100.0, 0.1), "cut_on_cost_pct": snappedf(content * 100.0, 0.1)})


func _measure(frames: int, vp_rid: RID) -> Dictionary:
	var ms: Array[float] = []
	var dc := 0.0
	var prims := 0.0
	var objs := 0.0
	var cpu := 0.0
	var gpu := 0.0
	var last := Time.get_ticks_usec()
	for i in frames:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		ms.append(float(now - last) / 1000.0)
		last = now
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	ms.sort()
	var n := float(frames)
	return {"draw_calls": int(dc / n), "primitives": int(prims / n), "objects": int(objs / n),
		"frame_ms_p50": snappedf(ms[ms.size() / 2], 0.1), "render_cpu_ms": snappedf(cpu / n, 0.01), "render_gpu_ms": snappedf(gpu / n, 0.01)}


func _budgets() -> Dictionary:
	var path := str(opts["budgets"])
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


# ------------------------------------------------------------------ screenshots
func _shots(preset: String, out: String) -> void:
	await _spawn(false)
	var rig: CameraRig = bench.get("rig")
	match preset:
		"city_day":
			bench.call("set_hour", 11.0)
			bench.call("set_view", "canyon", 24.0, &"city")
		"city_night":
			bench.call("set_hour", 22.5)
			bench.call("set_view", "canyon", 24.0, &"city")
		"city_cut":
			bench.call("set_hour", 15.5)
			bench.call("set_view", "canyon", 38.0, &"default")     # the camera hugs the 30-floor tower: its plan shows
		"city_inside":
			bench.call("set_hour", 16.0)
			bench.call("set_view", "inside", 30.0, &"default")     # own building: 3rd floor plan, roof shadow-only
		"city_rooftop":
			bench.call("set_hour", 17.2)
			bench.call("set_view", "rooftop", 30.0, &"rooftop")
		"city_hlod":
			bench.call("set_hour", 17.5)
			bench.call("set_view", "canyon", 24.0, &"city")
			var cam := Camera3D.new()
			cam.fov = 40.0
			cam.far = 1500.0
			bench.add_child(cam)
			cam.global_position = Vector3(260.0, 140.0, 300.0)
			cam.look_at(Vector3(0, 20, 20), Vector3.UP)
			cam.current = true
			(bench.get("cut") as CityCut).enabled = false
			var dn: DayNight = bench.get("day_night")
			dn.fog_density_scale = 0.2   # a mirador clears the fog (doc 09 §3.7)
		"profile_compare":
			await _profile_compare(out)
			return
		_:
			print("FAIL: unknown preset %s" % preset)
			ok = false
			return
	rig.snap_profile()
	await _frames(40)
	var img := await _capture()
	var err := img.save_png(out)
	print("screenshot %s -> %s (%s)" % [preset, out, "ok" if err == OK else "error %d" % err])
	if err != OK:
		ok = false


## Default vs city camera profile at the default zoom (24 m) and at each profile's max zoom (38 / 44 m), day,
## in one 2 × 2 sheet (and the four frames next to it).
func _profile_compare(out: String) -> void:
	bench.call("set_hour", 16.0)
	var sheet := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	var cells := [["canyon", 24.0, &"default"], ["canyon", 24.0, &"city"], ["canyon", 38.0, &"default"], ["canyon", 44.0, &"city"]]
	for i in cells.size():
		var c: Array = cells[i]
		bench.call("set_view", c[0], c[1], c[2])
		await _frames(30)
		var img := await _capture()
		img.convert(Image.FORMAT_RGB8)
		var single := out.get_basename() + "_%s_%d.png" % [String(c[2]), int(c[1])]
		img.save_png(single)
		img.resize(640, 360, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, 640, 360), Vector2i((i % 2) * 640, (i / 2) * 360))
		print("screenshot profile %s d=%d -> %s" % [c[2], int(c[1]), single])
	var err := sheet.save_png(out)
	print("screenshot profile_compare -> %s (%s)" % [out, "ok" if err == OK else "error %d" % err])
