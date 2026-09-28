extends RefCounted
## Body of tests/pcss_probe.gd (loaded at runtime, after the autoloads exist).

const W := 1280
const H := 720
const HOUR := 11.0
const FAMILY := "tower_a"
const GROUPS := 5

var tree: SceneTree
var opts: Dictionary
var root: Node3D
var sun: DirectionalLight3D
var cam: Camera3D
var tower: Node3D
var ground: MeshInstance3D


func run(p_tree: SceneTree, p_opts: Dictionary) -> void:
	tree = p_tree
	opts = p_opts
	await tree.process_frame
	var forward := not Quality.is_compat_renderer()
	if forward:
		Quality.set_preset(&"alto", false)
	print("== pcss probe (%s, %s, preset %s, PCSS angle %.1f°)" % [RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name(), Quality.preset, float(Quality.settings()["pcss_angular"])])
	if not forward:
		print("  info Compatibility has no PCSS (light_angular_distance is ignored): nothing to measure")
		print("== pcss probe OK")
		tree.quit(0)
		return
	CityLots.load_default()
	tree.root.get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	_scene()
	var far := Vector3(float(opts["x"]), 0.0, float(opts["z"]))
	var a := await _render(Vector3.ZERO)
	var b := await _render(far)
	# sensitivity check: the same view without PCSS (a hard edge) must have a much smaller penumbra
	sun.light_angular_distance = 0.0
	var hard := await _render(Vector3.ZERO)
	sun.light_angular_distance = float(Quality.settings()["pcss_angular"])
	var m := compare(a, b)
	var hm := compare(a, hard)
	if str(opts["shots"]) != "":
		DirAccess.make_dir_recursive_absolute(str(opts["shots"]))
		a.save_png("%s/pcss_origin.png" % opts["shots"])
		b.save_png("%s/pcss_far.png" % opts["shots"])
	print("  levels: lit %.3f, umbra %.3f (contrast %.3f)" % [m["lit"], m["umbra"], m["lit"] - m["umbra"]])
	print("  penumbra pixels: origin %d, at (%.0f, %.0f) %d → width difference %.2f %%; mean |Δ luma| inside the penumbra %.2f %% of the contrast; whole-frame max |Δ| %.3f" % [
		int(m["pen_a"]), far.x, far.z, int(m["pen_b"]), float(m["width_diff"]) * 100.0, float(m["luma_diff"]) * 100.0, float(m["max_diff"])])
	print("  info sensitivity: without PCSS the penumbra has %d pixels (%.0f %% of the PCSS one)" % [int(hm["pen_b"]), 100.0 * float(hm["pen_b"]) / maxf(1.0, float(m["pen_a"]))])
	var diff := maxf(float(m["width_diff"]), float(m["luma_diff"]))
	var limit := float(opts["limit"])
	var sensitive := float(hm["pen_b"]) < 0.7 * float(m["pen_a"])
	var pass_p := diff <= limit and sensitive and int(m["pen_a"]) > 500
	print("  mean penumbra difference origin vs %.1f km: %.2f %% (limit %.0f %%)   %s" % [far.length() / 1000.0, diff * 100.0, limit * 100.0,
		"ok" if pass_p else ("FAIL (R23 mitigation needed)" if sensitive else "FAIL (the probe does not see a PCSS penumbra)")])
	if str(opts["json"]) != "":
		var f := FileAccess.open(str(opts["json"]), FileAccess.WRITE)
		f.store_string(JSON.stringify({"far": [far.x, far.z], "metrics": m, "hard": hm, "difference": diff, "pass": pass_p}, "  "))
	print("== pcss probe %s" % ("OK" if pass_p else "FAILED"))
	tree.quit(0 if pass_p else 1)


## The game's sun at 11:00 (DayNight's arc and yaw, `alto` shadows), a flat matte ground, the tower (only its
## ShadowProxy casts; its visible pieces are hidden so the frame is ground + shadow), a camera like the game's.
func _scene() -> void:
	root = Node3D.new()
	root.name = "PcssProbe"
	tree.root.add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.1, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.28, 0.35)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.fog_enabled = false
	env.environment = e
	root.add_child(env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	root.add_child(sun)
	Quality.apply_to_sun(sun)
	sun.directional_shadow_split_1 = 0.35
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 2.5
	sun.light_energy = 1.2
	var elev := DayNight.sun_elevation(HOUR)
	var t_day := (HOUR - DayNight.SUNRISE) / (DayNight.SUNSET - DayNight.SUNRISE)
	var yaw := lerpf(DayNight.SUN_YAW_MORNING, DayNight.SUN_YAW_NOON, clampf(t_day * 2.0, 0.0, 1.0))
	sun.rotation_degrees = Vector3(-elev, yaw, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.9, 0.9, 0.9)
	gm.roughness = 1.0
	gm.metallic_specular = 0.0
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	pm.material = gm
	ground = MeshInstance3D.new()
	ground.mesh = pm
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	tower = TowerAssembler.build({"id": 1, "family": FAMILY, "groups": GROUPS, "wid": 1})
	root.add_child(tower)
	CityBuilding.attach(tower)
	for c in tower.get_children():
		if c is GeometryInstance3D and String(c.name) != "ShadowProxy":
			(c as GeometryInstance3D).visible = false
	cam = Camera3D.new()
	cam.fov = Balance.CAMERA_FOV
	cam.near = 0.3
	cam.far = 200.0
	root.add_child(cam)
	cam.current = true


## Renders the setup translated to `origin` (tower, ground, camera together; the sun is directional). Image of frame 8.
func _render(origin: Vector3) -> Image:
	var d := -sun.global_transform.basis.z
	var dh := Vector3(d.x, 0, d.z).normalized()
	var perp := Vector3(-dh.z, 0, dh.x)
	var a := TowerAssembler.assembly(FAMILY, GROUPS)
	var half := 7.47
	# the shadow edge of the tower's side, 22 m down the shadow: blocker ≈ 25–60 m above the ground there
	var target := origin + dh * 22.0 + perp * half
	tower.global_position = origin
	ground.global_position = origin
	var off := Vector3(0, 0, Balance.CAMERA_DIST).rotated(Vector3.RIGHT, deg_to_rad(Balance.CAMERA_PITCH_DEG)).rotated(Vector3.UP, deg_to_rad(Balance.CAMERA_YAW_DEG))
	cam.global_position = target + off
	cam.look_at(target, Vector3.UP)
	for i in 8:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := tree.root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	if img.get_width() != W or img.get_height() != H:
		img.resize(W, H, Image.INTERPOLATE_NEAREST)
	return img


static func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Penumbra metrics between two frames of the same view (levels from the first).
static func compare(a: Image, b: Image) -> Dictionary:
	var la := PackedFloat32Array()
	var lb := PackedFloat32Array()
	la.resize(W * H)
	lb.resize(W * H)
	var da := a.get_data()
	var db := b.get_data()
	for i in W * H:
		la[i] = (0.2126 * float(da[i * 3]) + 0.7152 * float(da[i * 3 + 1]) + 0.0722 * float(da[i * 3 + 2])) / 255.0
		lb[i] = (0.2126 * float(db[i * 3]) + 0.7152 * float(db[i * 3 + 1]) + 0.0722 * float(db[i * 3 + 2])) / 255.0
	var sorted := la.duplicate()
	sorted.sort()
	var umbra := sorted[int(0.05 * float(sorted.size()))]
	var lit := sorted[int(0.95 * float(sorted.size()))]
	var dl := maxf(lit - umbra, 1e-4)
	var lo := umbra + 0.1 * dl
	var hi := lit - 0.1 * dl
	var pa := 0
	var pb := 0
	var sum_d := 0.0
	var n_d := 0
	var max_d := 0.0
	for i in W * H:
		var ina := la[i] > lo and la[i] < hi
		var inb := lb[i] > lo and lb[i] < hi
		if ina:
			pa += 1
		if inb:
			pb += 1
		if ina or inb:
			sum_d += absf(la[i] - lb[i]) / dl
			n_d += 1
		max_d = maxf(max_d, absf(la[i] - lb[i]))
	return {"lit": lit, "umbra": umbra, "pen_a": pa, "pen_b": pb, "width_diff": absf(float(pb - pa)) / maxf(1.0, float(pa)),
		"luma_diff": sum_d / maxf(1.0, float(n_d)), "max_diff": max_d}
