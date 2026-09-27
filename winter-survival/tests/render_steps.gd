extends RefCounted
## Body of tests/render_checks.gd (W0 + G2a, headless). See the runner for the scope.

const BENCH_SCRIPT := "res://tests/city_bench/city_bench.gd"
const MIN_CHECKS := 78

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
	print("== VENTISCA render checks (W0 corte urbano + G2a)")
	root = Node3D.new()
	root.name = "RenderChecks"
	tree.root.add_child(root)
	_globals_and_materials()
	_quality()
	await _cut_maths()
	await _building_contract()
	await _poi_cutaway()
	await _camera_profiles()
	_day_night()
	_city_lights()
	_silhouettes()
	await _cursor_ray()
	await _cut_cost()
	# a script error aborts a section silently (its remaining checks never run): require them all
	if _checks < MIN_CHECKS:
		_failed += 1
		print("FAIL: only %d of %d checks ran (a script error above cut a section short)" % [_checks, MIN_CHECKS])
	print("== render checks: %d checks, %d failed" % [_checks, _failed])
	tree.quit(0 if _failed == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


# ------------------------------------------------------------------ globals, materials, shaders
func _globals_and_materials() -> void:
	var names: Array = CityCut.GLOBALS.duplicate()
	names.append_array(["snow_amount", "snow_wind", "city_lights", "city_power_map", "city_power_rect"])
	var missing := []
	for n in names:
		if not ProjectSettings.has_setting("shader_globals/" + str(n)):
			missing.append(n)
	check(missing.is_empty(), "project.godot declares the %d shader globals of the city cut / snow v2 / city lights (missing %s)" % [names.size(), missing])
	var family := {
		"res://assets/materials/world_vcol.tres": ["", "WV_CUT"],
		"res://assets/materials/world_vcol_struct.tres": ["#define WV_CUT_STRUCT", ""],
		"res://assets/materials/world_vcol_struct_4m.tres": ["#define WV_CUT_STRUCT", ""],
		"res://assets/materials/world_vcol_capsule.tres": ["#define WV_CUT_CAPSULE", ""],
		"res://assets/materials/window_city.tres": ["city_cut.gdshaderinc", ""],
		"res://assets/materials/light_pool.tres": ["blend_add", ""],
	}
	for path in family:
		var m := load(path) as ShaderMaterial
		var want: String = family[path][0]
		var not_want: String = family[path][1]
		var code := m.shader.code if m != null and m.shader != null else ""
		check(m != null and (want == "" or code.contains(want)) and (not_want == "" or not code.contains(not_want)),
			"%s uses the right family member (%s)" % [path.get_file(), want if want != "" else "no cut, no discard"])
	var base := load("res://assets/shaders/world_vcol_common.gdshaderinc") as ShaderInclude
	check(base != null and base.code.contains("apply_snow_v2") and base.code.contains("city_cut_struct_discard"),
		"world_vcol family body: snow v2 + corte urbano hooks")
	var inc := load("res://assets/shaders/city_cut.gdshaderinc") as ShaderInclude
	var re := RegEx.create_from_string("(?m)^\\s*instance uniform")
	var no_iu := inc != null and re.search(inc.code) == null and re.search(base.code) == null
	check(no_iu, "the cut and the world_vcol family declare no instance uniforms (Compatibility caps them at 256 instances)")
	var sil := load("res://assets/shaders/silhouette.gdshader") as Shader
	check(sil != null and sil.code.contains("depth_test_inverted") and not sil.code.contains("hint_depth_texture") and not sil.code.contains("stencil_mode"),
		"silhouette: depth_test_inverted, no depth texture / stencil (runs on Compatibility and the Web)")
	var s4 := CityBuilding.struct_material(4.3, 3.0)
	var s3 := CityBuilding.struct_material(3.3, 3.0)
	var s5 := CityBuilding.struct_material(3.8, 3.2)
	check(s4.resource_name == "world_vcol_struct_4m" and s3.resource_name == "world_vcol_struct" and s5 == CityBuilding.struct_material(3.8, 3.2)
		and is_equal_approx(float(s5.get_shader_parameter("floor_h")), 3.2), "one shared struct material per floor grid (3 m / 4 m .tres, others duplicated once)")


func _quality() -> void:
	var keys := ["city_cut", "silhouettes", "lamp_lights", "visibility_fade", "hlod_begin"]
	var ok := true
	for p in Quality.PRESETS:
		for k in keys:
			ok = ok and (Quality.PRESETS[p] as Dictionary).has(k)
	check(ok, "Quality presets carry the city keys %s" % [keys])
	check(int(Quality.PRESETS[&"compat"]["lamp_lights"]) == 0 and not bool(Quality.PRESETS[&"compat"]["visibility_fade"])
		and int(Quality.WEB_OVERRIDES["lamp_lights"]) == 0, "compat / Web: no real lamp lights, no dithered range fades")


# ------------------------------------------------------------------ the cut (GDScript mirror of the shader)
func _cut_maths() -> void:
	var cut := CityCut.new()
	root.add_child(cut)
	var idle_player := Node3D.new()
	root.add_child(idle_player)
	var idle_cam := Camera3D.new()
	root.add_child(idle_cam)
	cut.player_override = idle_player
	cut.camera_override = idle_cam
	cut.update(0.016)
	check(not bool(cut.state.get("on", true)), "no city building registered (the forest): CityCut writes nothing, the cut is off")
	idle_player.queue_free()
	idle_cam.queue_free()
	# a city building far away: from now on the cut runs
	var far := _make_building("FarAway", 4, true)
	root.add_child(far)
	far.position = Vector3(2000, 0, 2000)
	CityBuilding.attach(far)
	var player := Node3D.new()
	root.add_child(player)
	player.global_position = Vector3(0, 0, 24)
	var cam := Camera3D.new()
	root.add_child(cam)
	_place_camera(cam, player.global_position, 24.0)
	cut.player_override = player
	cut.camera_override = cam
	cut.enabled = true
	cut.update(1.0)
	var s := cut.state
	var c: Vector3 = s["camera"]
	check(bool(s["on"]) and (s["ws_cut_view"] as Vector4).w >= 16.0 and is_equal_approx((s["ws_cut_floor"] as Vector4).w, CityCut.STUB),
		"CityCut writes the globals from the camera + local player (zone R %.1f m, stub %.1f m)" % [(s["ws_cut_view"] as Vector4).w, (s["ws_cut_floor"] as Vector4).w])
	var between := player.global_position.lerp(Vector3(c.x, 0, c.z), 0.5) + Vector3(0, 9.0, 0)
	check(CityCut.fade_at(between, c, s) >= 0.97, "structure between the camera and the player, above the cut: removed")
	check(CityCut.fade_at(Vector3(between.x, 2.0, between.z), c, s) < 0.01, "the same column below the next slab (ground floor): kept")
	var beyond := player.global_position + Vector3(-8, 10, -8)
	check(CityCut.fade_at(beyond, c, s) < 0.01, "a facade beyond the player (away from the camera): kept")
	check(CityCut.fade_at(Vector3(c.x, 3.9, c.z), c, s, CityCut.Kind.STRUCT, 0.0, 3.3, 3.0) >= 0.97 and CityCut.fade_at(Vector3(c.x, 3.5, c.z), c, s, CityCut.Kind.STRUCT, 0.0, 3.3, 3.0) < 0.01,
		"the cut sits 0.4 m over the first slab above the player's floor (3.3 m grid: 3.7 m)")
	check(CityCut.fade_at(Vector3(c.x, 4.9, c.z), c, s, CityCut.Kind.STRUCT, 0.0, 4.3, 3.0) >= 0.97 and CityCut.fade_at(Vector3(c.x, 4.5, c.z), c, s, CityCut.Kind.STRUCT, 0.0, 4.3, 3.0) < 0.01,
		"per building grid from its material: a 4 m commercial ground floor is cut at 4.7 m")
	var on_seg := c.lerp(player.global_position + Vector3(0, 1.2, 0), 0.5)
	check(CityCut.fade_at(on_seg, c, s, CityCut.Kind.CAPSULE) < 0.01, "props capsule off outside the city profile")
	cut.props_capsule = true
	cut.update(0.0)
	check(CityCut.fade_at(on_seg, c, cut.state, CityCut.Kind.CAPSULE) >= 0.97, "props capsule on (city profile): a lamp on the camera-chest line is removed")
	check(CityCut.fade_at(player.global_position + Vector3(0, 1.0, 0), c, cut.state, CityCut.Kind.CAPSULE) < 0.01, "the capsule stops short of the player")
	# floor change: blended over 0.25 s, never a jump
	player.global_position = Vector3(0, 3.3, 24)
	cut.update(0.05)
	var fl: Vector4 = cut.state["ws_cut_floor"]
	check(fl.z < 1.0 and is_equal_approx(fl.y, 3.3), "floor change blends (from %.1f to %.1f, t %.2f)" % [fl.x, fl.y, fl.z])
	cut.update(0.3)
	check(is_equal_approx((cut.state["ws_cut_floor"] as Vector4).z, 1.0), "the blend ends after 0.25 s")
	player.global_position = Vector3(0, 0, 24)
	cut.update(1.0)
	cut.update(1.0)
	# off: the globals switch the cut off
	cut.enabled = false
	cut.update(0.0)
	check(not bool(cut.state["on"]) and CityCut.fade_at(between, c, cut.state) == 0.0, "disabled: nothing is cut")
	cut.enabled = true
	cut.props_capsule = false
	cut.update(1.0)
	await _frames(1)


## The game camera for a player position: yaw 45, pitch -48, pivot 3 m ahead, `dist` metres back.
func _place_camera(cam: Camera3D, feet: Vector3, dist: float) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(45.0)) * Basis(Vector3.RIGHT, deg_to_rad(-48.0))
	var pivot := feet + Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(45.0)) * 3.0
	cam.global_transform = Transform3D(basis, pivot + basis.z * dist)


# ------------------------------------------------------------------ the city building contract
func _make_building(bname: String, floors: int, with_proxy: bool) -> Node3D:
	var bench: Node3D = (load(BENCH_SCRIPT) as GDScript).new()
	var b: Node3D = bench.call("make_building", bname, 20.0, 16.0, floors, "glass", false, false)
	bench.free()
	if not with_proxy:
		var p := b.get_node("ShadowProxy")
		b.remove_child(p)
		p.free()
	return b


func _building_contract() -> void:
	var tower := _make_building("CheckTower", 14, true)
	check(CityBuilding.validate(tower).is_empty(), "bench tower conforms to the city building contract (%s)" % [CityBuilding.validate(tower)])
	var bad := Node3D.new()
	var piece := MeshInstance3D.new()
	piece.name = "Shaft_0"
	piece.mesh = BoxMesh.new()
	piece.position = Vector3(0, 3.0, 0)
	bad.add_child(piece)
	var probs := CityBuilding.validate(bad)
	check(probs.size() >= 3, "validate() flags a broken building (no Base, y offset, no floor_from): %s" % [probs])
	bad.free()
	# the provisional A1 names (Tower_Base / Tower_Shaft_<n> / Tower_Top / Tower_Shadow) are accepted as aliases
	var a1 := _make_building("A1Tower", 10, true)
	for pair in [["Base", "Tower_Base"], ["Shaft_0", "Tower_Shaft_0"], ["Shaft_1", "Tower_Shaft_1"], ["Roof", "Tower_Top"], ["ShadowProxy", "Tower_Shadow"]]:
		var n := a1.get_node_or_null(str(pair[0]))
		if n != null:
			n.name = str(pair[1])
	root.add_child(a1)
	a1.position = Vector3(220, 0, 100)
	var ab := CityBuilding.attach(a1)
	var a1_proxy := a1.get_node("Tower_Shadow") as GeometryInstance3D
	check(CityBuilding.validate(a1).is_empty() and ab.has_proxy and a1_proxy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		and (a1.get_node("Tower_Base") as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"A1 aliases Tower_Base / Tower_Shaft_<n> / Tower_Top / Tower_Shadow work like the contract names (%s)" % [CityBuilding.validate(a1)])
	ab.set_player_floor(1)
	check(not (a1.get_node("Tower_Top") as GeometryInstance3D).visible, "alias Tower_Top hides as the roof")
	ab.set_player_floor(-1)
	a1.queue_free()
	root.add_child(tower)
	tower.position = Vector3(100, 0, 100)
	var cb := CityBuilding.attach(tower)
	check(tower.is_in_group(CityBuilding.GROUP) and CityCut.buildings().has(cb), "attach(): group city_building + registered with CityCut")
	var base := tower.get_node("Base") as MeshInstance3D
	var shaft := tower.get_node("Shaft_0") as MeshInstance3D
	var roof := tower.get_node("Roof") as MeshInstance3D
	var proxy := tower.get_node("ShadowProxy") as MeshInstance3D
	var sm := base.get_surface_override_material(0) as ShaderMaterial
	var wm := base.get_surface_override_material(1) as ShaderMaterial
	check(sm != null and sm.resource_name == "world_vcol_struct" and wm != null and wm.resource_name == "window_city",
		"structure -> world_vcol_struct, facade glass -> window_city (shared, surface overrides)")
	check(proxy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and base.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and roof.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the ShadowProxy is the only shadow caster (SHADOWS_ONLY), pieces OFF")
	check(base.visibility_range_end >= 150.0 and shaft.visibility_range_end > 0.0 and proxy.visibility_range_end == 0.0,
		"visibility ranges: Base %.0f m, Shaft %.0f m, proxy unlimited" % [base.visibility_range_end, shaft.visibility_range_end])
	check(cb.floor_index(0.3) == 0 and cb.floor_index(3.3) == 1 and cb.floor_index(6.3) == 2 and is_equal_approx(cb.floor_level(2), 6.3),
		"floor grid: floor_index / floor_level agree with the shader's slabs")
	check(cb.contains(Vector3(100, 7.0, 100)) and not cb.contains(Vector3(100, cb.roof_level + 0.1, 100)) and not cb.contains(Vector3(130, 3, 100)),
		"contains(): inside the volume, not on the roof, not outside")
	# own building: roof + upper floor groups hidden shadow-preserving
	cb.set_player_floor(2)
	var hidden_above := true
	for c in tower.get_children():
		if String(c.name).begins_with("Shaft_") and int(c.get_meta("floor_from")) > 2:
			hidden_above = hidden_above and not (c as GeometryInstance3D).visible
	check(not roof.visible and hidden_above and base.visible and proxy.visible and proxy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
		"player on floor 2: roof and floor groups above hidden, Base kept, the proxy keeps casting")
	cb.set_player_floor(-1)
	check(roof.visible and shaft.visible and roof.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "player out: everything restored")
	var nop := _make_building("NoProxy", 6, false)
	root.add_child(nop)
	nop.position = Vector3(160, 0, 100)
	var nb := CityBuilding.attach(nop)
	var nroof := nop.get_node("Roof") as MeshInstance3D
	nb.set_player_floor(1)
	check(nroof.visible and nroof.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
		"without a proxy the hidden roof goes SHADOWS_ONLY (never visible = false on a caster: the room stays dark)")
	nb.set_player_floor(-1)
	check(nroof.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "and casts normally again once the player leaves")
	# CityCut picks the own building and hands the shader its box
	var cut := CityCut.instance
	var pl: Node3D = cut.player_override
	pl.global_position = Vector3(100, cb.floor_level(2), 100)
	_place_camera(cut.camera_override, pl.global_position, 24.0)
	cut.update(1.0)
	var own: Vector4 = cut.state["ws_cut_own"]
	var ext: Vector4 = cut.state["ws_cut_own_ext"]
	check(cut.own == cb and cut.own_floor == 2 and is_equal_approx(own.x, 100.0) and is_equal_approx(own.z, 10.0)
		and is_equal_approx(ext.z, cb.floor_level(2) + 0.6) and ext.w < cb.floor_level(3), "CityCut: own building box, 0.6 m stub, everything above the ceiling slab")
	var c: Vector3 = cut.state["camera"]
	check(CityCut.fade_at(Vector3(100, cb.floor_level(4), 104), c, cut.state) >= 0.97, "own building: an upper floor far from the camera is removed too")
	var away := (pl.global_position - Vector3(c.x, pl.global_position.y, c.z)).normalized()
	check(CityCut.fade_at(pl.global_position + away * 6.0 + Vector3(0, 1.5, 0), c, cut.state) < 0.01, "own building: the far wall of the player's floor is kept")
	check(CityCut.fade_at(pl.global_position - away * 6.0 + Vector3(0, 1.5, 0), c, cut.state) >= 0.97, "own building: the camera-side wall of the player's floor drops to the stub")
	check(CityCut.fade_at(pl.global_position - away * 6.0 + Vector3(0, 0.4, 0), c, cut.state) < 0.01, "own building: the 0.6 m stub stays")
	check(not roof.visible, "own building roof hidden through CityCut")
	pl.global_position = Vector3(0, 0, 24)
	_place_camera(cut.camera_override, pl.global_position, 24.0)
	cut.update(1.0)
	check(cut.own == null and roof.visible, "leaving the building restores it")
	# HLOD hook
	var hl := CityHlod.build_for(root)
	check(hl != null and hl.visibility_range_begin > 0.0 and base.visibility_parent != NodePath("") and proxy.visibility_parent == NodePath(""),
		"CityHlod: one merged mesh per chunk, pieces hide behind it at %.0f m (proxy keeps casting)" % [hl.visibility_range_begin if hl != null else 0.0])
	if hl != null:
		check(hl.mesh.get_surface_count() == 1, "HLOD is one surface (one draw call)")
		CityHlod.remove_from(root)
		check(base.visibility_parent == NodePath("") and root.get_node_or_null("CityHLOD") == null, "CityHlod.remove_from() unhooks the pieces (chunk unload)")
	await _frames(1)


# ------------------------------------------------------------------ legacy POI cutaway (M3 behaviour unchanged)
func _poi_cutaway() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	for spec in [["lookout_tower", Vector3(0, 9.5, 0), 1, "Walls1"], ["cabin_small", Vector3(0, 0.5, 0), 0, "Walls0"]]:
		var host := Node3D.new()
		host.position = Vector3(-200, 0, -200)
		root.add_child(host)
		var model := Assets.spawn_model(str(spec[0]))
		host.add_child(model)
		cam.global_position = host.global_position + Vector3(10, 20, 10)
		cam.look_at(host.global_position, Vector3.UP)
		cam.current = true
		var cutaway := PoiCutaway.attach(host, model)
		if cutaway == null:
			check(false, "%s has cut groups" % spec[0])
			continue
		check(cutaway.hide_mode == BuildingCutaway.HideMode.VISIBLE, "%s: legacy visible mode" % spec[0])
		var pl := Node3D.new()
		root.add_child(pl)
		cutaway.player_override = pl
		pl.global_position = host.global_position + (spec[1] as Vector3)
		cutaway._t = 0.0
		cutaway._process(0.0)
		var roof := model.get_node_or_null("Roof") as Node3D
		var g: String = spec[3]
		var s_wall := model.get_node_or_null(g + "_S") as Node3D
		var s_stub := model.get_node_or_null(g + "_S_Stub") as Node3D
		var n_wall := model.get_node_or_null(g + "_N") as Node3D
		check(cutaway.active_floor == int(spec[2]) and roof != null and not roof.visible, "%s: inside floor %d the roof is hidden (visible = false)" % [spec[0], spec[2]])
		check(s_wall != null and not s_wall.visible and s_stub != null and s_stub.visible and n_wall != null and n_wall.visible and cutaway.is_group_cut(g + "_S"),
			"%s: the camera-facing S wall becomes its stub, the N wall stays" % spec[0])
		pl.global_position = host.global_position + Vector3(12, 0, 12)
		cutaway._t = 0.0
		cutaway._process(0.0)
		check(cutaway.active_floor == -1 and roof.visible and s_wall.visible and not s_stub.visible, "%s: outside everything is back, stubs hidden" % spec[0])
		host.queue_free()
		pl.queue_free()
	cam.queue_free()
	await _frames(1)


# ------------------------------------------------------------------ camera profiles
func _camera_profiles() -> void:
	var holder := Node3D.new()
	holder.set_script(load("res://tests/city_bench/bench_player.gd"))
	root.add_child(holder)
	holder.global_position = Vector3(500, 0, 500)
	var rig := (load("res://tests/city_bench/bench_rig.tscn") as PackedScene).instantiate() as CameraRig
	holder.add_child(rig)
	await _frames(1)
	rig._process(0.3)
	check(rig.profile.id == &"default" and is_equal_approx(rig.pitch_deg, Balance.CAMERA_PITCH_DEG) and is_equal_approx(rig.camera.far, Balance.CAMERA_FAR),
		"outside every zone: the G1 camera (-48°, far 70)")
	var zone := CameraZone.new()
	zone.size = Vector3(60, 200, 60)
	root.add_child(zone)
	zone.global_position = Vector3(500, 0, 500)
	for i in 12:
		rig._process(0.25)
	check(rig.profile.id == &"city" and rig.pitch_deg > -44.0 and rig.pitch_deg < -42.5 and rig.camera.far > 90.0,
		"city zone: pitch blends to %.1f°, far %.0f m" % [rig.pitch_deg, rig.camera.far])
	var mid := CameraProfile.preset(&"default")
	rig.set_profile(&"default")
	rig._process(0.1)
	check(rig.pitch_deg < -43.0 and rig.pitch_deg > mid.pitch_deg, "the switch back is blended, not a jump (%.1f° after 0.1 s)" % rig.pitch_deg)
	rig.set_profile(&"city")
	rig.set_dist(60.0)
	check(is_equal_approx(rig.dist, 44.0), "city: zoom out to 44 m allowed")
	holder.global_position = Vector3(900, 0, 900)
	rig._zone_t = 0.0
	rig._process(0.25)
	check(rig.profile.id == &"default" and rig.dist <= Balance.CAMERA_DIST_MAX, "leaving the district clamps the zoom back to %.0f m" % rig.dist)
	holder.global_position = Vector3(500, 12.0, 500)
	rig._zone_t = 0.0
	rig._process(0.25)
	check(rig.profile.id == &"rooftop", "on a roof (12 m over the district) the rooftop profile applies")
	holder.queue_free()
	zone.queue_free()
	await _frames(1)


# ------------------------------------------------------------------ DayNight: snow wind, city night
func _day_night() -> void:
	var host := Node3D.new()
	root.add_child(host)
	for n in ["Sun", "Moon"]:
		var l := DirectionalLight3D.new()
		l.name = n
		host.add_child(l)
	var env := WorldEnvironment.new()
	env.name = "Env"
	host.add_child(env)
	var dn := DayNight.new()
	host.add_child(dn)
	dn.set_process(false)
	dn.apply(22.5)
	check(dn.city_night > 0.99 and CityLights.night() > 0.99, "22:30: city night 1 (windows by cell and lamp pools on)")
	dn.apply(11.0)
	check(dn.city_night < 0.01, "11:00: city night 0")
	check(is_equal_approx(dn.snow_wind.z, 0.3) and absf(Vector2(dn.snow_wind.x, dn.snow_wind.y).length() - 1.0) < 0.01, "snow_wind: unit direction, light prevailing drift in clear weather")
	dn.blizzard_blend = 1.0
	dn.apply(11.0)
	check(is_equal_approx(dn.snow_wind.z, 1.0) and dn.snow_amount > 0.5 and dn.city_night > 0.3, "blizzard: full wind, snow accumulates, dark enough for some windows")
	host.queue_free()


func _city_lights() -> void:
	CityLights.create_power_map(-100.0, -100.0, 200.0, 200.0, 8.0, 0.0)
	CityLights.paint_power(10.0, 10.0, 30.0, 30.0, 1.0)
	check(CityLights.power_at(Vector3(20, 0, 20)) > 0.99 and CityLights.power_at(Vector3(-50, 0, -50)) < 0.01, "power map: generator block powered, blacked-out sector off")
	CityLights.set_grid_power(0.5)
	check(is_equal_approx(CityLights.power_at(Vector3(500, 0, 500)), 0.5), "outside the map the grid power applies")
	var cl := CityLights.new()
	root.add_child(cl)
	for i in 5:
		cl.add_lamp(Vector3(12 + i * 4, 6, 20), 0.0, 1.0 if i != 2 else -1.0)
	cl.build()
	check(cl.pools.multimesh.instance_count == 5 and cl.halos.multimesh.instance_count == 5 and cl.pools.multimesh.use_custom_data,
		"lamps: pools and halos in two MultiMeshes (2 draw calls for any number of lamps)")
	check(cl.lamp_custom(2).a < 0.0 and cl.lamp_custom(0).a > 0.99, "a flickering lamp is flagged by a negative intensity, a powered one at 1")
	cl.queue_free()
	CityLights.clear_power_map()
	CityLights.set_grid_power(1.0)


func _silhouettes() -> void:
	var a := Silhouettes.player_material(1)
	check(a == Silhouettes.player_material(5) and a != Silhouettes.player_material(0) and Silhouettes.is_silhouette(Silhouettes.zombie_material()),
		"one silhouette material per jacket colour + one for zombies")
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	var ice := StandardMaterial3D.new()
	mi.material_overlay = ice
	Silhouettes._set_overlay(mi, a)
	check(mi.material_overlay == ice, "another overlay (frozen ice) is not replaced")
	mi.material_overlay = null
	Silhouettes._set_overlay(mi, a)
	Silhouettes._set_overlay(mi, null)
	check(mi.material_overlay == null, "silhouette set and cleared")
	mi.queue_free()


# ------------------------------------------------------------------ cursor through a cut building
func _cursor_ray() -> void:
	var cut := CityCut.instance
	var pl: Node3D = cut.player_override
	pl.global_position = Vector3(0, 0, 24)
	var cam := cut.camera_override
	cut.update(1.0)
	var c := cam.global_position
	# a building box between the camera and the player, and a crate behind it at the player's feet
	var bld := Node3D.new()
	bld.name = "RayBuilding"
	root.add_child(bld)
	var mid := Vector3(pl.global_position.x, 0, pl.global_position.z).lerp(Vector3(c.x, 0, c.z), 0.45)
	bld.global_position = mid
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 30, 4)
	cs.shape = box
	cs.position = Vector3(0, 15, 0)
	body.add_child(cs)
	bld.add_child(body)
	var mesh := MeshInstance3D.new()
	mesh.name = "Base"
	var bm := BoxMesh.new()
	bm.size = Vector3(4, 30, 4)
	mesh.mesh = bm
	mesh.position = Vector3.ZERO
	bld.add_child(mesh)
	bld.set_meta("floor_h", 3.0)
	bld.set_meta("ground_h", 3.3)
	var bb := CityBuilding.attach(bld)
	var crate := StaticBody3D.new()
	var ccs := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(1, 1, 1)
	ccs.shape = cbox
	crate.add_child(ccs)
	root.add_child(crate)
	crate.global_position = pl.global_position + Vector3(0, 0.5, 0)
	for i in 3:
		await tree.physics_frame
	var q := PhysicsRayQueryParameters3D.create(c, crate.global_position + (crate.global_position - c).normalized() * 3.0)
	var space := root.get_world_3d().direct_space_state
	var plain := space.intersect_ray(q)
	var through := CityCut.ray_through_cut(space, PhysicsRayQueryParameters3D.create(c, q.to))
	check(not plain.is_empty() and plain.collider == body, "the plain cursor ray hits the building in front")
	check(not through.is_empty() and through.collider == crate, "ray_through_cut reaches the crate behind the cut part of the building")
	bb.queue_free()
	bld.queue_free()
	crate.queue_free()
	await _frames(1)


# ------------------------------------------------------------------ CPU cost of CityCut with a city block loaded
func _cut_cost() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(20, 30, 20)
	for i in 300:
		var b := Node3D.new()
		var base := MeshInstance3D.new()
		base.name = "Base"
		base.mesh = mesh
		b.add_child(base)
		holder.add_child(b)
		b.position = Vector3(-600.0 + float(i % 20) * 32.0, 0.0, -600.0 + float(i / 20) * 32.0)
		CityBuilding.attach(b)
	var cut := CityCut.instance
	cut.player_override.global_position = Vector3(-440.0, 0.0, -440.0)
	_place_camera(cut.camera_override, cut.player_override.global_position, 24.0)
	cut.update(0.016)
	var t0 := Time.get_ticks_usec()
	for i in 200:
		cut.update(0.016)
	var per := float(Time.get_ticks_usec() - t0) / 200.0 / 1000.0
	print("  info CityCut.update with %d buildings registered: %.3f ms/frame" % [CityCut.buildings().size(), per])
	check(per < 0.2, "CityCut.update stays cheap with 300 buildings (%.3f ms/frame; doc 09 target 0.05 ms on a desktop CPU)" % per)
	holder.queue_free()
	await _frames(2)

