extends RefCounted
## Body of tests/citycut_probe.gd (loaded at runtime, after the autoloads exist).

const W := 1280
const H := 720
const PIXEL_SLACK := 6
const KEY_PLAYER := Color(0, 1, 0)
const KEY_ZOMBIE := Color(1, 0, 0)
const ZOOMS := [24.0, 38.0]
## The 5 fixed points of the superblock LT-01 (camera yaw 45°: the camera is to the +x +z of the player).
##   gran_via     Gran Vía north sidewalk: the block beyond the player, the jam between the camera and the player
##   west_street  the setback strip along the NW podium's west face: the podium and tower T23 on the camera side
##   back_street  the setback strip along the north faces of the block: podiums and tower T25 (130 m) on the camera side
##   plaza        the inner crossing between the four podiums: towers around, the camera inside the tallest's
##   mirador      the provisional mirador on the SW podium roof (rooftop profile), tower T21 beside it
const POINTS := {
	"gran_via": Vector2(2654.0, -401.5),
	"west_street": Vector2(2625.3, -466.0),
	"back_street": Vector2(2692.0, -484.2),
	"plaza": Vector2(2680.0, -446.0),
	"mirador": Vector2(2633.0, -414.0),
}
## Zombie stand-ins around each point (dx, dz), dropped when they would stand in a building, a car or a prop.
const ZOMBIE_OFFSETS := [Vector2(3.0, -4.0), Vector2(-4.5, 2.5), Vector2(5.5, 3.5), Vector2(-2.5, -6.5), Vector2(8.0, -2.0),
	Vector2(-7.0, -3.0), Vector2(1.5, 7.0), Vector2(-9.0, 5.0), Vector2(10.0, 6.0), Vector2(0.0, -10.0)]

var tree: SceneTree
var opts: Dictionary
var ok: bool = true
var results: Array = []
var world: World
var player: Player
var rig: CameraRig
var sil: Silhouettes
var cut: CityCut
var key_player: MeshInstance3D
var zombies: Array[Node3D] = []
var _mats: Dictionary = {}
var points: Dictionary = POINTS
var below_99: int = 0


func run(p_tree: SceneTree, p_opts: Dictionary) -> void:
	tree = p_tree
	opts = p_opts
	await tree.process_frame
	if not Quality.is_compat_renderer():
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
	while (not ready[0] or GameFlow.local_player() == null) and waited < 1800:
		await tree.process_frame
		waited += 1
	player = GameFlow.local_player()
	world = tree.current_scene.get_node_or_null("World") as World
	if player == null or world == null:
		print("FAIL: no local player / world")
		tree.quit(1)
		return
	# C1 (--points=c1): 10 seeded points on the sidewalks of the four districts instead of the 5 of LT-01
	if str(opts.get("points", "c0")) == "c1":
		points = c1_points(int(opts.get("seed", "1337")))
	print("== citycut probe altavega_%s (%s, %s, preset %s): %d points" % [str(opts.get("points", "c0")), RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), Quality.preset, points.size()])
	_freeze()
	sil = world.get_node_or_null("Silhouettes") as Silhouettes
	cut = world.get_node_or_null("CityCut") as CityCut
	rig = CameraRig.active()
	if sil == null or cut == null or rig == null:
		print("FAIL: the W0 city render nodes (CityCut / Silhouettes / CameraRig) are missing")
		tree.quit(1)
		return
	sil.tint_override = {"player": Color(0, 1, 1, 1), "zombie": Color(1, 0.5, 0, 1)}
	key_player = _capsule(KEY_PLAYER)
	player.add_child(key_player)
	sil.extra.append({"root": key_player, "kind": "player", "variant": 0})
	var visual = player.get("view")
	if visual != null:
		(visual as Node3D).visible = false
	tree.root.get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	var ui := tree.current_scene.get_node_or_null("UI") as CanvasLayer
	if ui != null:
		ui.visible = false
	print("  point        dist profile   player vis/read   zombies vis/read  n   (no cut: player / zombies)")
	var tot_ref := 0
	var tot_read := 0
	for pname in points:
		for dist in ZOOMS:
			await _view(str(pname), float(dist))
			var r: Dictionary = results[results.size() - 1]
			tot_ref += int(r["ref_player_px"]) + int(r["ref_zombie_px"])
			tot_read += int(r["read_player_px"]) + int(r["read_zombie_px"])
	var overall := float(tot_read) / maxf(1.0, float(tot_ref))
	var pass_o := overall >= 0.95
	ok = ok and pass_o
	print("  overall readable (player + zombies, %d views): %.1f %%   %s" % [results.size(), overall * 100.0, "ok" if pass_o else "FAIL (< 95 %)"])
	if below_99 > 0:
		print("  info %d views with the player under 99 %% visible (C1: reported, the gate is the overall readability)" % below_99)
	results.append({"overall_readable": snappedf(overall, 0.0001)})
	if str(opts["json"]) != "":
		var f := FileAccess.open(str(opts["json"]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(), "results": results}, "  "))
	print("== citycut probe %s" % ("OK" if ok else "FAILED"))
	tree.quit(0 if ok else 1)


## Fixed conditions: day 1 11:00, no clock, no weather or falling snow, nobody else, flat look for key colours.
func _freeze() -> void:
	WorldState.instance.set_time(1, 11.0)
	WorldState.instance.running = false
	for n in ["WolfSpawner", "DeerSpawner"]:
		var s := world.get_node_or_null(n)
		if s != null:
			s.set("enabled", false)
	if Director.instance != null:
		Director.instance.enabled = false
	if PopulationManager.instance != null:
		PopulationManager.instance.enabled = false
	if ZombieSystem.instance != null:
		ZombieSystem.instance.clear_all()
	for n in ["Snowfall", "SnowDrift"]:
		var p := world.get_node_or_null(n)
		if p != null:
			p.set_process(false)
			if p is GPUParticles3D:
				(p as GPUParticles3D).emitting = false
			if p is Node3D:
				(p as Node3D).visible = false
	var dn := world.get_node("DayNight") as DayNight
	dn.blizzard_blend = 0.0
	dn.apply(11.0)
	dn.set_process(false)
	world.env_override = true
	var e := (world.get_node("Env") as WorldEnvironment).environment
	e.fog_enabled = false
	e.glow_enabled = false
	e.ssao_enabled = false
	e.volumetric_fog_enabled = false
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	e.adjustment_enabled = false
	player.set_physics_process(false)
	if player.net != null:
		player.net.set_physics_process(false)
	player.set("input_enabled", false)


func _view(pname: String, dist: float) -> void:
	var pt: Vector2 = points[pname]
	var y := world.get_height(pt.x, pt.y)
	var roof := _roof_at(pt)
	if not is_nan(roof):
		y = roof
	var pos := Vector3(pt.x, y + 0.02, pt.y)
	world.streamer.ensure_loaded(pos, 2)
	var waited := 0
	while not world.streamer.is_idle() and waited < 900:
		await tree.process_frame
		waited += 1
	player.position = pos
	player.velocity = Vector3.ZERO
	player.set("move_dir", Vector3.ZERO)
	_place_zombies(pos, not is_nan(roof), pt)
	var prof := CameraZone.pick(tree, pos)
	rig.profile_override = prof
	rig.snap_profile()
	rig.dist = clampf(dist, rig.profile.dist_min, rig.profile.dist_max)
	rig.camera.position = Vector3(0, 0, rig.dist)
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, rig.pivot.rotation.y)
	rig.global_position = pos + fwd * Balance.CAMERA_FORWARD_OFFSET
	rig._process(0.0)
	rig.snap_profile()
	# reference: no city (buildings, bridge, cars, props), no silhouettes
	_city_visible(false)
	sil.enabled = false
	sil.poll()
	cut.update(1.0)
	await _frames(5)
	var ref := _count(await _capture())
	var cam_ref := rig.camera.global_position
	# no cut (informative: what the doc 09 prototype calls "std")
	_city_visible(true)
	cut.enabled = false
	cut.update(0.0)
	await _frames(5)
	var nocut := _count(await _capture())
	# the corte urbano + silhouettes
	cut.enabled = true
	sil.enabled = true
	sil.poll()
	cut.update(1.0)
	await _frames(5)
	var img := await _capture()
	var got := _count(img)
	var drift := rig.camera.global_position.distance_to(cam_ref)
	if drift > 0.001:
		ok = false
		print("FAIL: %s %.0f m: the camera moved %.4f m between the reference and the measured frame" % [pname, dist, drift])
	if str(opts["shots"]) != "":
		DirAccess.make_dir_recursive_absolute(str(opts["shots"]))
		img.save_png("%s/citycut_%s_%d.png" % [opts["shots"], pname, int(dist)])
	var pr := maxf(1.0, float(ref["player"]))
	var zr := maxf(1.0, float(ref["zombie"]))
	var lost := int(ref["player"]) - int(got["player"])
	var r := {"point": pname, "dist": dist, "profile": String(rig.profile.id), "zombies": zombies.size(),
		"ref_player_px": ref["player"], "ref_zombie_px": ref["zombie"],
		"read_player_px": mini(int(got["player"]) + int(got["player_sil"]), int(ref["player"])),
		"read_zombie_px": mini(int(got["zombie"]) + int(got["zombie_sil"]), int(ref["zombie"])),
		"player_visible": snappedf(float(got["player"]) / pr, 0.001), "player_readable": snappedf(float(got["player"] + got["player_sil"]) / pr, 0.001),
		"zombies_visible": snappedf(float(got["zombie"]) / zr, 0.001), "zombies_readable": snappedf(float(got["zombie"] + got["zombie_sil"]) / zr, 0.001),
		"nocut_player_visible": snappedf(float(nocut["player"]) / pr, 0.001), "nocut_zombies_visible": snappedf(float(nocut["zombie"]) / zr, 0.001),
		"camera_inside": cut.camera_building.root.name if cut.camera_building != null else ""}
	results.append(r)
	var pass_p := float(r["player_visible"]) >= 0.99 or lost <= PIXEL_SLACK
	# C1 (--points=c1): the PLAN C1 gate is the overall readability (≥ 95 %) over the 10 seeded points; a view under
	# the C0 per-view rule is reported ("below 99 %"), not failed
	var c1 := str(opts.get("points", "c0")) == "c1"
	if not pass_p and c1:
		below_99 += 1
	if not pass_p and not c1:
		ok = false
		img.save_png("/tmp/ventisca_citycut_%s_%d.png" % [pname, int(dist)])
	print("  %-12s %4.0f %-9s %5.1f %% / %5.1f %%    %5.1f %% / %5.1f %%   %d   (%5.1f %% / %5.1f %%)  %s  %s" % [pname, dist, r["profile"],
		100.0 * float(r["player_visible"]), 100.0 * float(r["player_readable"]), 100.0 * float(r["zombies_visible"]), 100.0 * float(r["zombies_readable"]),
		zombies.size(), 100.0 * float(r["nocut_player_visible"]), 100.0 * float(r["nocut_zombies_visible"]), r["camera_inside"], "ok" if pass_p else ("below 99 %" if c1 else "FAIL")])


## C1 (PLAN C1 «citycut_probe 10 puntos aleatorios ≥ 95 %»): 10 points drawn with `seed_v` on the sidewalks of the
## four districts (casco viejo 3, ensanche 3, barriada 2, Las Torres 2), each with a building within 12 m (where the
## corte urbano matters) and none within 0.8 m.
static func c1_points(seed_v: int) -> Dictionary:
	var quota := {"casco_viejo": 3, "ensanche": 3, "barriada": 2, "las_torres": 2}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var out := {}
	for d in CityLots.districts():
		var dname := str(d["district"])
		var walks: Array = []
		for sg in CityLots.segments_in(CityLots.rect_of(d["rect"])):
			var mid: Vector2 = ((sg[0] as Vector2) + (sg[1] as Vector2)) * 0.5
			if int(sg[3]) == 1 and (sg[0] as Vector2).distance_to(sg[1]) > 6.0 and CityLots.district_at(mid.x, mid.y) == dname:
				walks.append(sg)
		var n := 0
		var guard := 0
		while n < int(quota.get(dname, 0)) and guard < 500 and not walks.is_empty():
			guard += 1
			var sg: Array = walks[rng.randi_range(0, walks.size() - 1)]
			var p: Vector2 = (sg[0] as Vector2).lerp(sg[1] as Vector2, rng.randf_range(0.2, 0.8))
			if CityLots.district_at(p.x, p.y) != dname or CityLots.occupied(p.x, p.y, 0.8) or not CityLots.occupied(p.x, p.y, 12.0):
				continue
			# not behind a bench / a parked car / a lamp of the street dressing (the probe measures the cut)
			var clear := true
			for e in CityLots.items_near(seed_v, Rect2(p - Vector2(4, 4), Vector2(8, 8))):
				if e.has("model"):
					var sz := CityLots.model_size(str(e["model"]))
					if (e["pos"] as Vector2).distance_to(p) < maxf(sz.x, sz.z) * 0.5 + 1.2:
						clear = false
						break
			if not clear:
				continue
			n += 1
			out["%s_%d" % [dname, n]] = p.snapped(Vector2(0.1, 0.1))
	return out


## Roof height under a point on a podium (the mirador), NAN on the street.
func _roof_at(pt: Vector2) -> float:
	for p in CityLots.podiums():
		var c := CityLots.v2(p["pos"])
		var s := CityLots.v2(p["size"]) * 0.5
		if absf(pt.x - c.x) < s.x - 0.5 and absf(pt.y - c.y) < s.y - 0.5:
			return CityLots.podium_base(world.hf, int(p["id"])) + CityLots.podium_roof(p)
	return NAN


func _place_zombies(pos: Vector3, on_roof: bool, pt: Vector2) -> void:
	for z in zombies:
		sil.extra = sil.extra.filter(func(e: Dictionary) -> bool: return e.get("root") != z.get_child(0))
		z.queue_free()
	zombies.clear()
	var near := CityLots.items_near(world.hf.world_seed, Rect2(pt - Vector2(16, 16), Vector2(32, 32)))
	for o in ZOMBIE_OFFSETS:
		var q: Vector2 = pt + o
		if not on_roof and CityLots.occupied(q.x, q.y, 1.0):
			continue
		if on_roof and is_nan(_roof_at(q)):
			continue
		var clear := true
		for e in near:
			var k := int(e["k"])
			if k == CityLots.Kind.PODIUM or k == CityLots.Kind.BRIDGE or k == CityLots.Kind.BUILDING or k == CityLots.Kind.HERO:
				continue   # C1 lots and hero towers: their footprints (CityLots.occupied above)
			if k == CityLots.Kind.TOWER:
				var fam: Dictionary = CityLots.families()[str(e["family"])]
				if (e["pos"] as Vector2).distance_to(q) < CityLots.cm(fam["base"][0]) * 0.75 + 1.0:
					clear = false
				continue
			var sz := CityLots.model_size(str(e["model"]))
			if (e["pos"] as Vector2).distance_to(q) < maxf(sz.x, sz.z) * 0.5 + 0.9:
				clear = false
		if not clear:
			continue
		var z := Node3D.new()
		z.name = "KeyZombie%d" % zombies.size()
		tree.current_scene.add_child(z)
		z.global_position = Vector3(q.x, (pos.y if on_roof else world.get_height(q.x, q.y)) + 0.02, q.y)
		var cap := _capsule(KEY_ZOMBIE)
		z.add_child(cap)
		sil.extra.append({"root": cap, "kind": "zombie"})
		zombies.append(z)


func _city_visible(v: bool) -> void:
	for k in world.streamer.chunks:
		var c: WorldChunk = world.streamer.chunks[k]
		if c.city != null:
			c.city.visible = v


func _capsule(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.8
	mi.mesh = cap
	mi.position = Vector3(0, 0.9, 0)
	var key := col.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		m.disable_fog = true
		_mats[key] = m
	mi.material_override = _mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return tree.root.get_viewport().get_texture().get_image()


## Pixel counts by key colour at 1280 × 720 (the city bench's classifier).
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
