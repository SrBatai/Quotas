extends RefCounted
## Body of tests/g2b_checks.gd (G2b «Atmósfera», headless). See the runner for the scope.

const MIN_CHECKS := 60

var tree: SceneTree
var root: Node3D
var _checks := 0
var _failed := 0


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		_failed += 1
		print("FAIL: ", msg)


func run(p_tree: SceneTree) -> void:
	tree = p_tree
	await tree.process_frame
	print("== VENTISCA G2b checks (atmosphere: LUTs, fog layers, wind, thaw, life)")
	root = Node3D.new()
	root.name = "G2bChecks"
	tree.root.add_child(root)
	_files_and_materials()
	_lut_files()
	_lut_blend()
	_lut_weights()
	_overcast()
	await _day_night_hooks()
	await _thaw()
	_wind()
	await _effects()
	await _life()
	if _checks < MIN_CHECKS:
		_failed += 1
		print("FAIL: only %d of %d checks ran (a script error above cut a section short)" % [_checks, MIN_CHECKS])
	print("== g2b checks: %d checks, %d failed" % [_checks, _failed])
	tree.quit(0 if _failed == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


# ------------------------------------------------------------------ files, globals, shaders, materials
func _files_and_materials() -> void:
	var missing := []
	for n in ["thaw_a", "thaw_b", "thaw_info", "snow_wind", "city_lights"]:
		if not ProjectSettings.has_setting("shader_globals/" + n):
			missing.append(n)
	check(missing.is_empty(), "project.godot declares the thaw globals (thaw_a / thaw_b mat4, thaw_info) (missing %s)" % [missing])
	var fam := {
		"res://assets/materials/world_vcol_foliage.tres": ["#define WV_WIND_TREE", "WV_CUT"],
		"res://assets/materials/world_vcol_cloth.tres": ["#define WV_WIND_CLOTH", ""],
		"res://assets/materials/world_vcol_cable.tres": ["#define WV_WIND_CABLE", ""],
		"res://assets/materials/beacon_halo.tres": ["blend_add", "TIME"],
		"res://assets/materials/flock_crow.tres": ["INSTANCE_CUSTOM", "TIME"],
		"res://assets/materials/ember_glow.tres": ["blend_add", ""],
	}
	for path in fam:
		var m := load(path) as ShaderMaterial
		var code := m.shader.code if m != null and m.shader != null else ""
		var want: String = fam[path][0]
		var not_want: String = fam[path][1]
		check(m != null and code.contains(want) and (not_want == "" or not code.contains(not_want)),
			"%s: %s%s" % [path.get_file(), want, "" if not_want == "" else ", no %s" % not_want])
	var common := load("res://assets/shaders/world_vcol_common.gdshaderinc") as ShaderInclude
	var wind := load("res://assets/shaders/wind_include.gdshaderinc") as ShaderInclude
	check(common != null and common.code.contains("wind_model_offset(VERTEX, MODEL_MATRIX, TIME)") and wind != null and wind.code.contains("snow_wind"),
		"world_vcol family: per-vertex wind hook (WV_WIND_*) from the snow_wind global")
	var world_vcol := load("res://assets/materials/world_vcol.tres") as ShaderMaterial
	check(world_vcol != null and not world_vcol.shader.code.contains("WV_WIND"), "world_vcol (characters, props) does not sway")
	var snow := load("res://assets/shaders/snow_include.gdshaderinc") as ShaderInclude
	var terrain := load("res://assets/materials/terrain.tres") as ShaderMaterial
	check(snow != null and snow.code.contains("thaw_at(wp)") and terrain != null and terrain.shader.code.contains("thaw_at(v_world_pos)")
		and terrain.shader.code.contains("wet_sheen"), "visible thaw: snow v2 melts off and the terrain goes wet / bare near heat")
	var iu := RegEx.create_from_string("(?m)^\\s*instance uniform")
	check(iu.search(wind.code) == null and iu.search(snow.code) == null, "no instance uniforms in the G2b includes (Compatibility caps them)")


# ------------------------------------------------------------------ LUTs
func _lut_files() -> void:
	var g := LutGrade.new()
	check(LutGrade.NAMES.size() == 8 and g.available(), "8 LUTs: %s" % [LutGrade.NAMES])
	var ok := true
	var bad := []
	for id in LutGrade.NAMES.size():
		var s := g.slices_of(id)
		if s.size() != 32 or s[0].get_width() != 32 or s[0].get_height() != 32 or absf(s[5].get_pixel(3, 4).a - 128.0 / 255.0) > 0.003:
			ok = false
			bad.append(LutGrade.NAMES[id])
	check(ok, "every LUT is a 32³ strip (1024 × 32) with the half alpha of the CPU blend (%s)" % [bad])
	var meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/luts/luts.json"))
	var listed := meta is Dictionary and (meta["luts"] as Dictionary).size() == 9
	check(listed, "assets/luts/luts.json lists the 8 LUTs + identity with their parameters and hashes (tools/make_luts.py)")
	# identity: texel = its input (Godot samples the LUT at the tonemapped colour)
	var ident: Array[Image] = []
	var strip := load("res://assets/luts/identity.png") as Image
	for z in 32:
		ident.append(strip.get_region(Rect2i(z * 32, 0, 32, 32)))
	var err := 0.0
	for c in [Color(0.1, 0.5, 0.9), Color(0.73, 0.21, 0.4), Color(0.5, 0.5, 0.5), Color(0.02, 0.97, 0.3)]:
		var o := LutGrade.sample(ident, c)
		err = maxf(err, maxf(absf(o.r - c.r), maxf(absf(o.g - c.g), absf(o.b - c.b))))
	# a 32³ LUT sampled at the raw colour (texel i at (i + 0.5) / 32) with texel i = input i / 31: exact at 0, ½ and 1,
	# within 1/64 (4/255) near the ends — inherent to the tonemapper's lookup, not to the files
	check(err <= 4.5 / 255.0, "identity LUT maps a colour to itself as the tonemapper samples it (max error %.1f/255)" % (err * 255.0))
	# the grades do what they say
	var grey := Color(0.55, 0.55, 0.57)
	var warm := Color(1.0, 0.62, 0.3)
	var dia := LutGrade.sample(g.slices_of(0), grey)
	var bliz := LutGrade.sample(g.slices_of(2), warm)
	var night := LutGrade.sample(g.slices_of(4), grey)
	var night_warm := LutGrade.sample(g.slices_of(4), warm)
	check(absf(dia.r - grey.r) < 0.06 and absf(dia.b - grey.b) < 0.06, "dia_claro stays close to the approved G1 look (%s)" % dia)
	check(bliz.s < warm.s * 0.8, "ventisca desaturates (s %.2f -> %.2f)" % [warm.s, bliz.s])
	check(night.b > night.r and night_warm.r > night_warm.b + 0.2, "noche: blue mids, warm lights keep their colour (%s / %s)" % [night, night_warm])


func _lut_blend() -> void:
	var g := LutGrade.new()
	g.preload_all()
	var w := PackedFloat32Array([0.5, 0.0, 0.0, 0.3, 0.2, 0.0, 0.0, 0.0])
	g.set_target(w)
	var work: Array[float] = []
	var frames := 0
	var total := 0.0
	while g.is_busy() and frames < 400:
		var ew := SchedProbe.exec_wait_ns()
		var t0 := Time.get_ticks_usec()
		g.step()
		var wall := float(Time.get_ticks_usec() - t0)
		var ew2 := SchedProbe.exec_wait_ns()
		# work time = wall − run-queue wait (another process had the core: not our cost; SchedProbe, W1)
		var us := maxf(wall - float(ew2[1] - ew[1]) / 1000.0, 0.0)
		work.append(us)
		total += us
		frames += 1
	var over := 0
	for us in work:
		over += 1 if us > 100.0 else 0
	work.sort()
	var med := work[work.size() / 2]
	var p95 := work[int(work.size() * 0.95)]
	print("  info LUT blend of 3 LUTs: %d frames, work per frame median %.0f µs, p95 %.0f µs, max %.0f µs, total %.2f ms" % [frames, med, p95, work[-1], total / 1000.0])
	check(not g.is_busy() and g.updates_done == 1 and g.slices_done == 32, "a 3-LUT blend completes in %d frames (32 slices, one upload)" % frames)
	# gated like the other timing gates of a shared VM: the median, and at most 10 % of frames over (the stray ones
	# are SMT / frequency noise of other processes that the run-queue wait does not subtract)
	check(med <= 100.0 and float(over) <= 0.1 * float(work.size()), "LUT blend ≤ 0.1 ms of CPU per frame (median %.0f µs, %d of %d frames over 0.1 ms, p95 %.0f µs)" % [med, over, work.size(), p95])
	var ref := [g.slices_of(0), g.slices_of(3), g.slices_of(4)]
	var err := 0.0
	for c in [Color(0.1, 0.5, 0.9), Color(0.73, 0.21, 0.4), Color(0.5, 0.5, 0.5), Color(0.9, 0.9, 0.95), Color(0.05, 0.05, 0.1)]:
		var want := LutGrade.sample(ref[0], c) * 0.5 + LutGrade.sample(ref[1], c) * 0.3 + LutGrade.sample(ref[2], c) * 0.2
		var got := g.lookup(c)
		err = maxf(err, maxf(absf(want.r - got.r), maxf(absf(want.g - got.g), absf(want.b - got.b))))
	check(err <= 2.0 / 255.0, "the blended LUT = Σ wᵢ·LUTᵢ (max error %.2f/255)" % (err * 255.0))
	# at rest: nothing runs
	var s0 := g.slices_done
	var u0 := g.updates_done
	var rest_us := 0
	for i in 120:
		g.step()
		rest_us += g.last_step_usec
	check(g.slices_done == s0 and g.updates_done == u0 and rest_us == 0, "at rest the grade costs 0 (120 frames: 0 slices, %d µs)" % rest_us)
	# a change below EPS does not start an update; above it does
	var w2 := w.duplicate()
	w2[0] -= 0.003
	w2[4] += 0.003
	g.set_target(w2)
	g.step()
	check(not g.is_busy() and g.slices_done == s0, "a weight change under 1/128 does not re-blend")
	# a single LUT is swapped in whole (no blend work)
	g.set_target(PackedFloat32Array([0, 0, 1.0, 0, 0, 0, 0, 0]))
	var changed := g.step()
	check(changed and not g.is_busy() and g.slices_done == s0 and absf(g.lookup(Color(0.5, 0.5, 0.5)).r - LutGrade.sample(g.slices_of(2), Color(0.5, 0.5, 0.5)).r) < 0.002,
		"a pure grade (ventisca 1.0) is its own texture: swapped in one frame, no blend")
	# more than MAX_SOURCES: the smallest are dropped and the rest renormalised
	g.set_target(PackedFloat32Array([0.4, 0.3, 0.2, 0.1, 0.0, 0.0, 0.0, 0.0]))
	var t := g.target()
	check(t[3] == 0.0 and absf(t[0] + t[1] + t[2] - 1.0) < 1e-5, "at most %d LUTs per blend (the smallest weight dropped, renormalised)" % LutGrade.MAX_SOURCES)


func _lut_weights() -> void:
	var noon := Atmosphere.lut_weights_for(DayNight.sun_elevation(12.5), 0.0, 0.0, 0.0, 0.0, 1.0, 0.0)
	check(noon[0] > 0.99, "12:30 clear: dia_claro (%s)" % noon)
	var e := DayNight.sun_elevation(18.6)
	var dusk := Atmosphere.lut_weights_for(e, _night(e), 0.0, 0.0, 0.0, 1.0, 0.0)
	check(dusk[3] > 0.6, "18:36: atardecer leads (%.2f)" % dusk[3])
	var e2 := DayNight.sun_elevation(23.0)
	var night := Atmosphere.lut_weights_for(e2, _night(e2), 0.0, 0.0, 0.0, 1.0, 0.0)
	check(night[4] > 0.99, "23:00 in the valley: noche")
	var city := Atmosphere.lut_weights_for(e2, _night(e2), 0.0, 0.0, 1.0, 1.0, 0.0)
	var dark := Atmosphere.lut_weights_for(e2, _night(e2), 0.0, 0.0, 1.0, 0.0, 0.0)
	check(city[5] > 0.99 and dark[6] > 0.99, "23:00 in the city: noche_ciudad with power, apagon in a blackout")
	var over := Atmosphere.lut_weights_for(DayNight.sun_elevation(12.5), 0.0, 1.0, 0.0, 0.0, 1.0, 0.0)
	check(over[1] > 0.99, "12:30 overcast: nublado")
	var bz := Atmosphere.lut_weights_for(DayNight.sun_elevation(15.0), 0.0, 0.0, 1.0, 0.0, 1.0, 0.0)
	var bzn := Atmosphere.lut_weights_for(e2, _night(e2), 0.0, 1.0, 0.0, 1.0, 0.0)
	check(bz[2] > 0.99 and bzn[2] > 0.5 and bzn[4] > 0.3, "blizzard: ventisca (at night shared with noche: %.2f / %.2f)" % [bzn[2], bzn[4]])
	var fire := Atmosphere.lut_weights_for(e2, _night(e2), 0.0, 0.0, 0.0, 1.0, 1.0)
	var total := 0.0
	for x in fire:
		total += x
	check(absf(fire[7] - 0.5) < 1e-4 and absf(total - 1.0) < 1e-4, "by the fire: calor takes half the grade, weights sum to 1")


static func _night(elev: float) -> float:
	return 1.0 - clampf((elev + 4.0) / 10.0, 0.0, 1.0)


# ------------------------------------------------------------------ overcast (presentation only)
func _overcast() -> void:
	var a := Atmosphere.overcast_at(1337, 80.5)
	check(a == Atmosphere.overcast_at(1337, 80.5), "overcast is deterministic (seed + absolute hour: every client the same)")
	var first := 0.0
	for h in range(0, 30):
		first = maxf(first, Atmosphere.overcast_at(1337, float(h)))
	check(first == 0.0, "the first day stays clear")
	var over := 0
	var n := 0
	var max_step := 0.0
	var prev := Atmosphere.overcast_at(1337, 30.0)
	var differ := 0
	var h := 30.0
	while h < 30.0 + 24.0 * 30.0:
		var o := Atmosphere.overcast_at(1337, h)
		if o > 0.5:
			over += 1
		n += 1
		max_step = maxf(max_step, absf(o - prev))
		prev = o
		if absf(o - Atmosphere.overcast_at(4242, h)) > 0.2:
			differ += 1
		h += 0.1
	var share := float(over) / float(n)
	print("  info overcast over 30 days (seed 1337): %.0f %% of the time, largest change in 6 game minutes %.3f" % [share * 100.0, max_step])
	check(share > 0.12 and share < 0.5, "overcast about a third of the time (%.0f %%)" % (share * 100.0))
	check(max_step < 0.08, "the cloud cover changes smoothly (max %.3f per 0.1 h)" % max_step)
	check(differ > n / 10, "another world seed has its own sky")


# ------------------------------------------------------------------ DayNight hooks
func _day_night_hooks() -> void:
	var host := Node3D.new()
	root.add_child(host)
	for nm in ["Sun", "Moon"]:
		var l := DirectionalLight3D.new()
		l.name = nm
		host.add_child(l)
	var env := WorldEnvironment.new()
	env.name = "Env"
	host.add_child(env)
	var dn := DayNight.new()
	host.add_child(dn)
	dn.set_process(false)
	check(dn.atmosphere == null, "headless: DayNight creates no Atmosphere (servers and headless clients unchanged)")
	var atmo := Atmosphere.new()
	dn.atmosphere = atmo
	dn.add_child(atmo)
	atmo.set_process(false)
	var prev_preset := Quality.preset
	Quality.set_preset(&"alto", false)
	var e := env.environment
	atmo.overcast_override = 0.0
	dn.apply(12.0)
	var sun_clear := dn.sun.light_energy
	var fog_clear := e.fog_density
	check(not atmo.volumetric_on and not e.volumetric_fog_enabled, "alto, 12:00 clear: no volumetric fog")
	check(is_equal_approx(dn.snow_wind.z, 0.3), "clear: the prevailing drift (wind 0.3)")
	atmo.overcast_override = 1.0
	dn.apply(12.0)
	check(dn.sun.light_energy < sun_clear * 0.4 and e.fog_density > fog_clear * 1.5, "overcast: flat light (sun %.2f -> %.2f), denser fog (%.4f -> %.4f)" % [sun_clear, dn.sun.light_energy, fog_clear, e.fog_density])
	check(dn.snow_wind.z >= 0.6 and dn.snow_wind.w > 0.5, "overcast skies blow harder (wind %.2f, gusts %.2f): snow snakes without a blizzard" % [dn.snow_wind.z, dn.snow_wind.w])
	atmo.overcast_override = 0.0
	dn.apply(7.3)
	check(e.fog_height_density > 0.012, "7:18 clear: dawn mist in the valley (height fog %.4f)" % e.fog_height_density)
	dn.apply(18.9)
	check(e.fog_sun_scatter > 0.05, "18:54: sun scatter warms the fog toward the low sun (%.2f)" % e.fog_sun_scatter)
	dn.apply(23.0)
	check(atmo.volumetric_on and e.volumetric_fog_enabled and e.volumetric_fog_density < 0.01, "alto, 23:00: thin volumetric fog (lamps and fires get halos, %.4f)" % e.volumetric_fog_density)
	dn.blizzard_blend = 1.0
	atmo.overcast_override = -1.0
	dn.apply(15.0)
	check(atmo.volumetric_on and absf(e.volumetric_fog_density - DayNight.VOLUMETRIC_DENSITY) < 1e-4, "alto, blizzard: volumetric fog at the G1 density")
	check(atmo.overcast > 0.99, "a blizzard comes under its own cloud deck (overcast %.2f)" % atmo.overcast)
	check(not dn.sun.shadow_enabled and dn.sun.shadow_opacity < 0.05, "whiteout: the sun's shadow fades out and its passes stop")
	dn.blizzard_blend = 0.5
	dn.apply(15.0)
	check(dn.sun.shadow_enabled and dn.sun.shadow_opacity > 0.99, "half a blizzard: shadows as before")
	dn.blizzard_blend = 0.0
	atmo.overcast_override = 0.0
	Quality.set_preset(&"medio", false)
	dn.apply(23.0)
	check(not atmo.volumetric_on and not e.volumetric_fog_enabled and atmo.compat_fog_boost > 0.0, "medio (and compat), 23:00: no volumetrics, the depth comes back as denser exponential fog (+%.4f)" % atmo.compat_fog_boost)
	dn.blizzard_blend = 1.0
	dn.apply(15.0)
	check(not e.volumetric_fog_enabled, "medio, blizzard: still no volumetric fog")
	dn.blizzard_blend = 0.0
	# FogVolumes follow the volumetric switch
	atmo.fog_patches.set_state(false, 1.0, 0.0, 1.0)
	var vis := 0
	for v in atmo.fog_patches.volumes:
		vis += 1 if v.visible else 0
	check(vis == 0 and not atmo.fog_patches.active, "local FogVolumes only exist while volumetric fog is on")
	# the city / mirador flag (fog colour override) turns the city grade on
	dn.fog_color_override = Color(0.1, 0.1, 0.2, 1.0)
	dn.apply(23.0)
	check(atmo.city_factor > 0.99, "a mirador / the menu skyline (fog colour override) reads as the city for the grade")
	dn.fog_color_override = Color(0, 0, 0, 0)
	Quality.set_preset(prev_preset, false)
	host.queue_free()
	await _frames(1)


# ------------------------------------------------------------------ thaw
func _thaw() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var dn := DayNight.new()
	host.add_child(dn)
	dn.set_process(false)
	var atmo := Atmosphere.new()
	dn.add_child(atmo)
	atmo.set_process(false)
	var fire := Node3D.new()
	fire.add_to_group("heat_source")
	host.add_child(fire)
	fire.global_position = Vector3(3, 0, 2)
	atmo._update_heat()
	check(atmo.thaw_sources.size() == 1 and atmo.thaw_sources[0].w < 0.5, "a new fire starts a small melt (%.2f m)" % (atmo.thaw_sources[0].w if not atmo.thaw_sources.is_empty() else -1.0))
	atmo._clock += Atmosphere.THAW_GROW
	atmo._update_heat()
	check(atmo.thaw_sources.size() == 1 and absf(atmo.thaw_sources[0].w - 2.6) < 0.05, "after %.0f s the melted ring reaches the fire's radius (%.2f m)" % [Atmosphere.THAW_GROW, atmo.thaw_sources[0].w])
	fire.remove_from_group("heat_source")
	atmo._clock += 1.0
	atmo._update_heat()
	atmo._clock += Atmosphere.THAW_DRY * 0.5
	atmo._update_heat()
	check(atmo.thaw_sources.size() == 1 and atmo.thaw_sources[0].w < 1.5, "a fire that went out leaves a drying wet ring (%.2f m)" % (atmo.thaw_sources[0].w if not atmo.thaw_sources.is_empty() else -1.0))
	atmo._clock += Atmosphere.THAW_DRY
	atmo._update_heat()
	check(atmo.thaw_sources.is_empty(), "…that is gone after %.0f s" % Atmosphere.THAW_DRY)
	for i in 11:
		var f := Node3D.new()
		f.add_to_group("thaw_source")
		host.add_child(f)
		f.global_position = Vector3(float(i) * 4.0, 0, 0)
	atmo._update_heat()
	check(atmo.thaw_sources.size() == Atmosphere.THAW_MAX and atmo.thaw_sources[0].x < atmo.thaw_sources[7].x, "at most 8 heat sources, nearest first (%d)" % atmo.thaw_sources.size())
	host.queue_free()
	Atmosphere.write_thaw_globals([])
	await _frames(1)


# ------------------------------------------------------------------ wind materials
func _wind() -> void:
	var pine := Assets.instancing_mesh("pine_a")
	var rock := Assets.instancing_mesh("rock_a")
	var sway := false
	for i in pine.get_surface_count():
		var m := pine.surface_get_material(i)
		sway = sway or (m != null and m.resource_name.begins_with("world_vcol_foliage"))
	var still := true
	for i in rock.get_surface_count():
		var m := rock.surface_get_material(i)
		still = still and not (m != null and m.resource_name.begins_with("world_vcol_foliage"))
	check(sway and still, "scatter pines sway (world_vcol_foliage), rocks do not")
	var model := Assets.spawn_model("pine_a")
	WindSway.apply_to_model(model, "pine_a")
	var ovr := 0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).get_surface_override_material(i)
			if m != null and m.resource_name.begins_with("world_vcol_foliage"):
				ovr += 1
	check(ovr > 0, "a materialized tree sways like its MultiMesh instance did (%d surfaces)" % ovr)
	model.free()
	var c30 := WindSway.material("cable", 30.0)
	var c12 := WindSway.material("cable", 12.0)
	check(c30 != c12 and is_equal_approx(float(c12.get_shader_parameter("wind_height")), 12.0) and c12 == WindSway.material("cable", 12.0),
		"one cable material per span, shared")


# ------------------------------------------------------------------ effects
func _effects() -> void:
	check(FxSprites.has_sprites(), "Kenney Particle Pack atlases present (assets/textures/fx, manifest + licence)")
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://assets/textures/fx/manifest.json"))
	check(man is Dictionary and str(man["pack"]["license"]) == "CC0-1.0" and (man["files"] as Array).size() >= 9
		and FileAccess.file_exists("res://assets/textures/fx/LICENSE-kenney-particle-pack.txt"), "sprites: CC0, provenance (mirror commit + SHA-256) and the licence text")
	var sm := FxSprites.smoke_material()
	var fm := FxSprites.flame_material()
	check(sm.particles_anim_h_frames == 2 and sm.particles_anim_v_frames == 2 and sm.billboard_mode == BaseMaterial3D.BILLBOARD_PARTICLES
		and sm.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED and fm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "smoke lit 2 × 2 flipbook, flames additive")
	DayNight.current_wind = Vector4(1, 0, 0.3, 0)
	var calm := FxSprites.wind_gravity(0.2, 1.0)
	DayNight.current_wind = Vector4(1, 0, 1.0, 0)
	var storm := FxSprites.wind_gravity(0.2, 1.0)
	DayNight.current_wind = Vector4(1, 0, 0.3, 0)
	check(storm.x > calm.x * 3.0 and storm.y < calm.y, "smoke drifts downwind: a thread in calm air (%.2f), laid flat in a blizzard (%.2f)" % [calm.x, storm.x])
	var smoke := SmokeEffect.new()
	root.add_child(smoke)
	var fire := FireEffect.new()
	root.add_child(fire)
	await _frames(1)
	check((smoke.draw_pass_1 as QuadMesh).material == sm and (fire.flames.draw_pass_1 as QuadMesh).material == fm, "chimney smoke and fires use the sprites")
	var col := SmokeColumn.new()
	root.add_child(col)
	await _frames(1)
	check(col.is_in_group("thaw_source") and col.plume != null and col.glow != null, "a smouldering source: plume + embers + a melted ring (thaw_source, not a gameplay heat source)")
	check(not col.is_in_group("heat_source"), "…and it warms nobody (render only)")
	var bl := BeaconLights.new()
	root.add_child(bl)
	bl.put_set(1, [[Vector3(0, 1.5, 0), 0.0, Color.RED, BeaconLights.Mode.ROTATE, 0.2], [Vector3(4, 1.2, 0), 0.0, Color.ORANGE, BeaconLights.Mode.BLINK, 0.7]])
	bl.put_set(2, [[Vector3(8, 4.0, 0), 0.0, Color.ORANGE, BeaconLights.Mode.AMBER, 0.1]])
	check(bl.count() == 3 and bl.halos.multimesh.instance_count == 3 and bl.pools.multimesh.instance_count == 3 and bl.halos.multimesh.use_custom_data,
		"beacons: bulbs and ground light in two MultiMeshes (2 draw calls for any number)")
	var cst := BeaconLights.custom_of(Color.RED, BeaconLights.Mode.ROTATE, 1.2)
	check(int(floor(cst.a)) == BeaconLights.Mode.ROTATE and absf(fposmod(cst.a, 1.0) - 0.2) < 1e-3 and cst.r == 1.0, "mode + phase packed in INSTANCE_CUSTOM.a")
	bl.remove_set(1)
	check(bl.count() == 1, "a set leaves with its owner (chunk unload)")
	var fl := Flock.new()
	fl.birds = 12
	root.add_child(fl)
	check(fl.multimesh.instance_count == 12 and fl.multimesh.use_custom_data and fl.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		and fl.custom_aabb.size.x > fl.radius * 2.0, "a flock: one MultiMesh, per-bird orbit in the shader, shadows, an AABB that covers the orbit")
	var mesh := Flock.bird_mesh()
	check(mesh.get_faces().size() / 3 <= 60, "a crow is ≤ 60 triangles (%d)" % (mesh.get_faces().size() / 3))
	var hc := HangingCables.new()
	root.add_child(hc)
	hc.put_set(0, [[Vector3(0, 7, 0), Vector3(0, 7, 30)], [Vector3(10, 7, 0), Vector3(10, 7, 30)], [Vector3(20, 7, 0), Vector3(42, 7, 0)]])
	check(hc.count() == 3 and hc.get_child_count() == 2, "cables: one MultiMesh per span (30 m ×2, 22 m ×1)")
	for n in [smoke, fire, col, bl, fl, hc]:
		(n as Node).queue_free()
	await _frames(1)


# ------------------------------------------------------------------ AmbientLife from a city chunk plan
func _life() -> void:
	var life := AmbientLife.new()
	root.add_child(life)
	await _frames(1)
	var rows := func(ps: Array) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		for p in ps:
			out.append_array(ChunkJob.instance_row({"x": p.x, "y": 0.0, "z": p.z, "yaw": 0.3, "s": 1.0}))
		return out
	var cops: Array = []
	var bars: Array = []
	var cars: Array = []
	for i in 20:
		cops.append(Vector3(2600.0 + i * 7.0, 0, -390.0))
		bars.append(Vector3(2600.0 + i * 5.0, 0, -420.0))
		cars.append(Vector3(2600.0 + i * 9.0, 0, -360.0))
	var plan := {"group_order": ["police|clean", "barrier_striped|", "sedan|burnt"], "groups": {
		"police|clean": {"model": "police", "variant": "clean", "rows": rows.call(cops)},
		"barrier_striped|": {"model": "barrier_striped", "variant": "", "rows": rows.call(bars)},
		"sedan|burnt": {"model": "sedan", "variant": "burnt", "rows": rows.call(cars)},
	}}
	life._populate(77, plan, null)
	var n := life.beacons.count()
	check(n >= 20 and n <= 60, "C0 plan: rotating beacons on some of 20 police cars, flashers on most of 20 barriers (%d beacons)" % n)
	var smokes: Array = life.smoke.get(77, [])
	check(smokes.size() >= 1 and smokes.size() <= 4, "burnt wrecks smoulder (%d smoke columns, capped at 4 a chunk)" % smokes.size())
	var again := AmbientLife.new()
	root.add_child(again)
	await _frames(1)
	again._populate(77, plan, null)
	check(again.beacons.count() == n, "deterministic: the same plan lights the same beacons on every client")
	life._release(77)
	check(life.beacons.count() == 0 and not life.smoke.has(77), "the chunk unloads: its beacons and smoke go with it")
	life.queue_free()
	again.queue_free()
	await _frames(2)
