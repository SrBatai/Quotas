extends RefCounted
## M6a street bench body (loaded by tests/street_bench_run.gd). Modes:
##   gate   `citycut_probe` on the test street (PLAN v3 M6a acceptance): flat key colours, per view × zoom, pixels of
##          the local player and the zombies with the street (the corte urbano + the CutawayManager on) against a
##          reference frame without it; blocking: player >= 99 % visible (or <= 6 edge pixels lost) from 24 m in
##          every view (street, backyard, gap between houses, inside storeys 0 / 1 / 2, a south-row house), zombies
##          >= 95 % readable (visible or silhouette) at 24–38 m in the street views. Then the INTERIOR SHADOW check:
##          a cut house (and the cabin_small POI) — the floor around the player's feet must be as dark with the cut as
##          with only the shadow casters (±5 %), and clearly darker than without them (the roof shadow is kept).
##   shots  bench presets street_day, street_night, house_inside.

const BENCH := "res://tests/street_bench/street_bench.tscn"
const W := 1280
const H := 720
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
		Quality.set_preset(&"alto", false)
	print("== street bench %s (%s, %s, preset %s)" % [opts["mode"], RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name(), Quality.preset])
	match str(opts["mode"]):
		"gate":
			await _gate()
		"shots":
			await _shots(str(opts["preset"]), str(opts["out"]))
		_:
			print("FAIL: unknown mode %s" % opts["mode"])
			ok = false
	if str(opts["json"]) != "":
		var f := FileAccess.open(str(opts["json"]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"mode": opts["mode"], "renderer": RenderingServer.get_current_rendering_method(), "results": results}, "  "))
	print("== street bench %s %s" % [opts["mode"], "OK" if ok else "FAILED"])
	tree.quit(0 if ok else 1)


func _spawn(measure: bool) -> void:
	bench = (load(BENCH) as PackedScene).instantiate() as Node3D
	tree.root.add_child(bench)
	if not bench.has_method("build"):
		print("FAIL: the street bench scene did not load (script errors above)")
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
	tree.root.get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	var sun: DirectionalLight3D = bench.get("sun")
	sun.visible = true
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.45, -1.0, -0.35), Vector3.UP)
	var sil: Silhouettes = bench.get("sil")
	sil.tint_override = {"player": Color(0, 1, 1, 1), "zombie": Color(1, 0.5, 0, 1)}
	var cut: CityCut = bench.get("cut")
	var cases := [["street", 24.0], ["street", 38.0], ["backyard", 24.0], ["backyard", 38.0], ["gap", 24.0], ["gap", 38.0],
		["inside0", 24.0], ["inside0", 38.0], ["inside1", 24.0], ["inside1", 38.0], ["apartment2", 24.0],
		["apartment2", 38.0], ["south_inside", 24.0], ["south_inside", 38.0], ["street", 16.0]]
	print("  view          dist   player vis/read   zombies vis/read   (no cut: player / zombies)   inside")
	var worst_p := 2.0
	var worst_z := 2.0
	for c in cases:
		var view: String = c[0]
		var dist: float = c[1]
		bench.call("set_view", view, dist, &"default")
		bench.call("set_occluders_visible", false)
		sil.enabled = false
		sil.poll()
		await _frames(4)
		var ref := _count(await _capture())
		var cam_ref: Vector3 = (bench.get("rig") as CameraRig).camera.global_position
		bench.call("set_occluders_visible", true)
		cut.enabled = false
		cut.update(0.0)
		await _frames(4)
		var nocut := _count(await _capture())
		cut.enabled = true
		sil.enabled = true
		sil.poll()
		bench.call("set_view", view, dist, &"default")
		await _frames(4)
		var img := await _capture()
		var got := _count(img)
		var drift := (bench.get("rig") as CameraRig).camera.global_position.distance_to(cam_ref)
		if drift > 0.001:
			ok = false
			print("FAIL: %s %.0f m: the camera moved %.4f m between the reference and the measured frame" % [view, dist, drift])
		var pr := maxf(1.0, float(ref["player"]))
		var zr := maxf(1.0, float(ref["zombie"]))
		var mgr: CutawayManager = bench.get("mgr")
		var r := {
			"view": view, "dist": dist, "ref_player_px": ref["player"], "ref_zombie_px": ref["zombie"],
			"player_visible": snappedf(float(got["player"]) / pr, 0.001),
			"player_readable": snappedf(float(got["player"] + got["player_sil"]) / pr, 0.001),
			"zombies_visible": snappedf(float(got["zombie"]) / zr, 0.001),
			"zombies_readable": snappedf(float(got["zombie"] + got["zombie_sil"]) / zr, 0.001),
			"nocut_player_visible": snappedf(float(nocut["player"]) / pr, 0.001),
			"nocut_zombies_visible": snappedf(float(nocut["zombie"]) / zr, 0.001),
			"inside": "%s/%d" % [mgr.inside_cutaway.model_root().get_parent().template_id if mgr.inside and mgr.inside_cutaway.model_root().get_parent() is KitBuilding else "-", mgr.inside_floor],
		}
		results.append(r)
		var gated := dist >= 24.0
		var lost := int(ref["player"]) - int(got["player"])
		var pass_p := float(r["player_visible"]) >= 0.99 or lost <= PIXEL_SLACK or not gated
		var street_view := view == "street" or view == "backyard" or view == "gap"
		var zg := gated and street_view and dist <= 38.0 and float(ref["zombie"]) >= 200.0
		var pass_z := float(r["zombies_readable"]) >= 0.95 or not zg
		r["zombies_gated"] = zg
		if gated:
			worst_p = minf(worst_p, float(r["player_visible"]))
		if zg:
			worst_z = minf(worst_z, float(r["zombies_readable"]))
		if not pass_p or not pass_z:
			ok = false
			img.save_png("/tmp/ventisca_street_gate_%s_%d.png" % [view, int(dist)])
		print("  %-12s %4.0f   %5.1f %% / %5.1f %%    %5.1f %% / %5.1f %%     (%5.1f %% / %5.1f %%)            %-22s %s" % [view, dist,
			100.0 * float(r["player_visible"]), 100.0 * float(r["player_readable"]), 100.0 * float(r["zombies_visible"]),
			100.0 * float(r["zombies_readable"]), 100.0 * float(r["nocut_player_visible"]), 100.0 * float(r["nocut_zombies_visible"]),
			str(r["inside"]), "ok" if pass_p and pass_z else "FAIL"])
	print("  citycut_probe (street): player >= %.1f %% (gate 99 %%), zombies readable >= %.1f %% (gate 95 %%)" % [100.0 * worst_p, 100.0 * worst_z])
	results.append({"check": "citycut_probe", "player_min": worst_p, "zombies_min": worst_z})
	await _interior_shadow_kit()
	await _interior_shadow_cabin()


## Kit house (ShadowProxy = the only caster): the floor around the player's feet, storey 0 of the north 2-storey
## house. (a) the house reduced to its storey-0 floor + interior with the proxy casting; (b) the real cut; (d) the
## proxy hidden too (the room in full sun: proves the region is shaded by the roof).
func _interior_shadow_kit() -> void:
	var b: KitBuilding = bench.call("building", "house_two_story_A", "wood_blue")
	bench.call("set_view", "inside0", 24.0, &"default")
	await _frames(4)
	var region := _feet_region()
	var b_luma := _luma(await _capture(), region)
	var saved := _hide_all_but(b.model, ["Floor0", "Interior0", "ShadowProxy"])
	await _frames(4)
	var a_luma := _luma(await _capture(), region)
	var proxy := b.model.get_node("ShadowProxy") as Node3D
	proxy.visible = false
	await _frames(4)
	var d_luma := _luma(await _capture(), region)
	proxy.visible = true
	_restore(saved)
	_report_shadow("kit house (2 storeys, storey 0)", a_luma, b_luma, d_luma)


## cabin_small (M3 POI, no proxy: its roof and walls cast) through the CutawayManager: (a) roof + walls cast only
## (SHADOWS_ONLY), (b) the real cut, (d) roof + walls gone (what PoiCutaway's `visible = false` did).
func _interior_shadow_cabin() -> void:
	bench.call("set_view", "cabin", 24.0, &"default")
	await _frames(4)
	var region := _feet_region()
	var b_luma := _luma(await _capture(), region)
	var model: Node3D = bench.get("cabin_model")
	var saved := {}
	for c in model.get_children():
		var n := String(c.name)
		if n == "Roof" or (n.begins_with("Walls") and not n.ends_with("_Stub")) or n.begins_with("Door_") or n.begins_with("Window_"):
			for gi in BuildingCutaway._geometries(c):
				saved[gi] = [gi.visible, gi.cast_shadow]
				gi.visible = true
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		elif n.ends_with("_Stub"):
			for gi in BuildingCutaway._geometries(c):
				saved[gi] = [gi.visible, gi.cast_shadow]
				gi.visible = false
	await _frames(4)
	var a_luma := _luma(await _capture(), region)
	for gi in saved:
		if (gi as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			(gi as GeometryInstance3D).visible = false
	await _frames(4)
	var d_luma := _luma(await _capture(), region)
	for gi in saved:
		(gi as GeometryInstance3D).visible = saved[gi][0]
		(gi as GeometryInstance3D).cast_shadow = saved[gi][1]
	_report_shadow("cabin_small POI (CutawayManager, was PoiCutaway)", a_luma, b_luma, d_luma)


func _report_shadow(what: String, a: float, b: float, d: float) -> void:
	var ratio := b / maxf(a, 1e-4)
	var gain := d / maxf(a, 1e-4)
	var pass_s := absf(ratio - 1.0) <= 0.05 and gain > 1.1
	if not pass_s:
		ok = false
	results.append({"check": "interior_shadow", "what": what, "luma_casters_only": snappedf(a, 0.001), "luma_cut": snappedf(b, 0.001),
		"luma_no_roof": snappedf(d, 0.001), "ratio": snappedf(ratio, 0.001), "sun_gain": snappedf(gain, 0.01)})
	print("  interior shadow, %s: luma %.3f (cut) vs %.3f (casters only) -> ratio %.3f (±5 %%); without the roof %.3f (x%.2f)   %s" % [
		what, b, a, ratio, d, gain, "ok" if pass_s else "FAIL"])


## The floor around the player's feet on screen (the player's key pixels are skipped by _luma).
func _feet_region() -> Rect2i:
	var cam := (bench.get("rig") as CameraRig).camera
	var player: Node3D = bench.get("player")
	var c := cam.unproject_position(player.global_position + Vector3(0, 0.02, 0)) * Vector2(float(W) / 1280.0, float(H) / 720.0)
	return Rect2i(int(c.x) - 70, int(c.y) - 30, 140, 60)


func _hide_all_but(model: Node3D, keep: Array) -> Dictionary:
	var saved := {}
	for c in model.get_children():
		if not (c is Node3D) or String(c.name) in keep or String(c.name).begins_with("Col") or c is StaticBody3D:
			continue
		saved[c] = (c as Node3D).visible
		(c as Node3D).visible = false
	return saved


func _restore(saved: Dictionary) -> void:
	for n in saved:
		(n as Node3D).visible = saved[n]


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
			if (c.g > 0.78 and c.r < 0.24) or (c.r > 0.78 and c.b < 0.24):
				continue
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return sum / maxf(1.0, float(n))


# ------------------------------------------------------------------ screenshots (bench versions)
func _shots(preset: String, out: String) -> void:
	await _spawn(false)
	var rig: CameraRig = bench.get("rig")
	match preset:
		"street_day":
			bench.call("set_hour", 11.0)
			bench.call("set_view", "street", 30.0, &"default")
		"street_night":
			bench.call("set_hour", 22.5)
			bench.call("set_view", "street", 30.0, &"default")
		"house_inside":
			bench.call("set_hour", 16.0)
			bench.call("set_view", "inside1", 26.0, &"default")
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
