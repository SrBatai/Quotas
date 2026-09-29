extends SceneTree
# xvfb-run -a godot --rendering-driver opengl3 --path . -s render.gd -- <mode> <out_dir>
var OUT := "res://shots"
var mode := "sheet"

func env_setup(bg: Color):
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = bg
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#b9cbe3")
	e.ambient_light_energy = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = e
	get_root().add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 60, 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	get_root().add_child(sun)

func ground(pos: Vector3, size: Vector2):
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#d5e0ec")
	m.roughness = 1.0
	pm.material = m
	mi.mesh = pm
	mi.position = pos
	get_root().add_child(mi)

func find_first(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r = find_first(c, cls)
		if r:
			return r
	return null

func spawn(model: String, pos: Vector3, yaw_deg: float, anim: String, t: float, lib_path := "", axe := false) -> Node3D:
	var inst: Node3D = load(model).instantiate()
	inst.position = pos
	inst.rotation_degrees.y = yaw_deg
	get_root().add_child(inst)
	var ap: AnimationPlayer = find_first(inst, "AnimationPlayer")
	if lib_path != "":
		if ap == null:
			ap = AnimationPlayer.new()
			inst.add_child(ap)
			ap.root_node = NodePath("..")
		var lib = load(lib_path)
		if lib is PackedScene:
			var tmp = lib.instantiate()
			lib = find_first(tmp, "AnimationPlayer").get_animation_library("")
		if ap.has_animation_library(""):
			ap.remove_animation_library("")
		ap.add_animation_library("", lib)
	var sk: Skeleton3D = find_first(inst, "Skeleton3D")
	if axe:
		var ba := BoneAttachment3D.new()
		ba.bone_name = "RightHandSocket"
		sk.add_child(ba)
		var tool: Node3D = load("res://models/stone_axe.glb").instantiate()
		ba.add_child(tool)
	if ap and anim != "":
		ap.play(anim)
		ap.seek(t, true)
		ap.pause()
	return inst

func camera(pos: Vector3, look: Vector3, ortho_size := 0.0, fov := 35.0):
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.position = pos
	cam.look_at(look, Vector3.UP)
	if ortho_size > 0:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = ortho_size
	else:
		cam.fov = fov
	cam.current = true
	return cam

func snap(name: String):
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("saved ", OUT + "/" + name + ".png ", img.get_size())

func clear():
	for c in get_root().get_children():
		c.queue_free()
	await process_frame

func sheet(model: String, anims: Array, cols: int, tag: String, lib := "", axe := false, yaw_row := [90.0, 35.0]):
	# rows: for each anim two rows (side view yaw 90 -> faces +X, and 3/4 view)
	for anim in anims:
		await clear()
		env_setup(Color("#dfe7f0"))
		var length := 1.0
		var probe = spawn(model, Vector3(0, -50, 0), 0, "", 0, lib)
		var pap: AnimationPlayer = find_first(probe, "AnimationPlayer")
		length = pap.get_animation(anim).length
		for r in 2:
			var y := -r * 2.3
			ground(Vector3((cols - 1) * 0.75, y, 0), Vector2(cols * 1.5 + 2, 3))
			for c in cols:
				var t := length * c / cols
				spawn(model, Vector3(c * 1.5, y, 0), yaw_row[r], anim, t, lib, axe)
		get_root().size = Vector2i(1500, 640)
		camera(Vector3((cols - 1) * 0.75, 1.0 - 1.15, 12), Vector3((cols - 1) * 0.75, 1.0 - 1.15, 0), 4.9)
		await snap("%s_%s" % [tag, anim])

func prop(path: String, pos: Vector3, yaw := 0.0):
	var n: Node3D = load(path).instantiate()
	n.position = pos
	n.rotation_degrees.y = yaw
	get_root().add_child(n)

func game_view():
	await clear()
	env_setup(Color("#a9bfd8"))
	ground(Vector3.ZERO, Vector2(80, 80))
	var S := "res://models/survivor.glb"
	var ZR := "res://models/zombie_rt.glb"
	var LIB := "res://models/survivor_lib.glb"
	prop("res://models/cabin.glb", Vector3(-7, 0, -3), 180)
	prop("res://models/pickup_truck.glb", Vector3(5, 0, -1), 200)
	prop("res://models/pine_a.glb", Vector3(8, 0, -9))
	prop("res://models/pine_b.glb", Vector3(-1, 0, -12))
	prop("res://models/pine_a.glb", Vector3(11, 0, 4))
	spawn(S, Vector3(0, 0, 1.5), 30, "Idle", 0.5, "", true)
	spawn(S, Vector3(-2.2, 0, 3.0), 70, "Walk", 0.25, "", true)
	spawn(S, Vector3(2.4, 0, 2.5), -40, "Run", 0.2, "", true)
	spawn(S, Vector3(0.8, 0, -1.2), 185, "Attack", 0.42, "", true)
	for i in 5:
		spawn(ZR, Vector3(-3 + i * 1.7, 0, -4.5 - (i % 2) * 1.6), -15 + i * 8, "ZombieShamble", i * 0.3, LIB)
	get_root().size = Vector2i(1400, 860)
	# game camera: pitch -52, yaw 35, dist 22, fov 35 (ARCHITECTURE.md)
	var pitch := deg_to_rad(52.0)
	var yaw := deg_to_rad(35.0)
	var target := Vector3(0, 0.8, -1)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera(target + dir * 22.0, target, 0.0, 35.0)
	await snap("game_view_dist22")
	camera(target + dir * 14.0, target, 0.0, 35.0)
	await snap("game_view_dist14")
	await clear()
	env_setup(Color("#a9bfd8"))
	ground(Vector3.ZERO, Vector2(60, 60))
	spawn(S, Vector3(0, 0, 0), 20, "Attack", 0.30, "", true)
	spawn(S, Vector3(1.6, 0, 0.3), 20, "Attack", 0.42, "", true)
	spawn("res://models/zombie.glb", Vector3(-1.8, 0, 0.2), 10, "ZombieShamble", 0.4, S)
	spawn(ZR, Vector3(-3.4, 0, 0.6), 10, "ZombieShamble", 0.4, LIB)
	get_root().size = Vector2i(1200, 800)
	camera(Vector3(-0.8, 0.8, 0.2) + dir * 7.0, Vector3(-0.8, 0.8, 0.2), 0.0, 35.0)
	await snap("closeup_iso")

func _init():
	var args = OS.get_cmdline_user_args()
	mode = args[0] if args.size() > 0 else "sheet"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await process_frame
	if mode == "sheet":
		await sheet("res://models/survivor.glb", ["Idle", "Walk", "Run", "Attack", "ZombieShamble"], 6, "survivor", "", true)
	elif mode == "zombie":
		await sheet("res://models/zombie.glb", ["Walk", "ZombieShamble"], 6, "zombie_noretarget", "res://models/survivor.glb")
		if ResourceLoader.exists("res://models/zombie_rt.glb"):
			await sheet("res://models/zombie_rt.glb", ["Walk", "ZombieShamble", "Attack"], 6, "zombie_retarget", "res://models/survivor_lib.glb")
	elif mode == "survivor_rt":
		await sheet("res://models/survivor_rt.glb", ["Walk", "Attack"], 6, "survivor_rt", "", true)
	elif mode == "game":
		await game_view()
	quit()
