extends RefCounted
## Screenshot preset body (loaded at runtime by tests/screenshot.gd). Presets day/night/blizzard/interior/menu run the
## offline local server; `multi` joins a running dedicated server (--host=ip --port=n) to prove remote players render.

var tree: SceneTree
var flags: Array[String] = []  # debug flags: noshadow, noambient, placeholders, host=ip, port=n

var preset: String = "day"
var out_path: String = "/tmp/ventisca_shot.png"


func _flag_value(prefix: String, default: String) -> String:
	for f in flags:
		if f.begins_with(prefix + "="):
			return f.substr(prefix.length() + 1)
	return default


func run(p_tree: SceneTree, p_preset: String, p_out: String) -> void:
	tree = p_tree
	preset = p_preset
	out_path = p_out
	await tree.process_frame
	if flags.has("placeholders"):
		Assets.force_placeholders = true
	var ready := false
	Events.world_ready.connect(func() -> void: ready = true)
	if preset == "menu":
		tree.change_scene_to_file("res://scenes/main/main_menu.tscn")
		await tree.process_frame
		await tree.process_frame
	elif preset == "multi":
		GameFlow.join(_flag_value("host", "127.0.0.1"), int(_flag_value("port", str(Net.DEFAULT_PORT))), _flag_value("password", ""))
	else:
		GameFlow.play_offline()
	var waited := 0
	while preset != "menu" and not ready and waited < 900:
		await tree.process_frame
		waited += 1
	waited = 0
	while preset != "menu" and GameFlow.local_player() == null and waited < 1800:
		await tree.process_frame
		waited += 1
	await tree.process_frame
	await tree.process_frame
	var game := tree.current_scene
	if preset != "menu":
		var player: Player = GameFlow.local_player()
		var world: World = game.get_node("World")
		if player == null:
			print("FAIL: no local player for preset %s" % preset)
			tree.quit(1)
			return
		Events.notify.emit("", 0.1)
		if Net.is_server:
			(world.get_node("Weather") as Weather).scheduler_enabled = false  # deterministic shots
		var inv: InventoryComponent = player.state.inventory
		match preset:
			"day":
				WorldState.instance.set_time(1, 11.0)
				inv.add(&"hacha", 1)
				inv.add(&"madera", 7)
				inv.add(&"piedra", 6)
			"night":
				WorldState.instance.set_time(1, 22.5)
				world.cabin.stove.burner.add_fuel(600.0)
				inv.add(&"madera", 6)
				inv.add(&"piedra", 6)
				inv.add(&"lata_sopa", 1)
				inv.add(&"antorcha", 1)
				var p := player.global_position + Vector3(-2.2, 0, 2.0)
				p.y = world.get_height(p.x, p.z)
				world.spawn_placed("campfire", p, 0.0)
				world.get_node("WolfSpawner").enabled = false
			"blizzard":
				WorldState.instance.set_time(1, 15.0)
				inv.add(&"hacha", 1)
				inv.add(&"madera", 4)
				var weather: Weather = world.get_node("Weather")
				weather.force_blizzard(60.0)
				world.get_node("DayNight").blizzard_blend = 1.0
			"interior":
				WorldState.instance.set_time(1, 21.0)
				world.cabin.stove.burner.add_fuel(600.0)
				inv.add(&"hacha", 1)
				inv.add(&"madera", 6)
				inv.add(&"piedra", 6)
				player.global_position = world.cabin.global_position + Vector3(-1.3, 0.6, 0.5)
				player.input.scripted_aim = player.global_position + Vector3(3, 1.2, 0)
				player.view.visual.rotation.y = PI * 0.5  # face +X (front = +Z yawed 90°)
				world.get_node("WolfSpawner").enabled = false
				await tree.process_frame
				NetWorld.instance.open_storage(player, world.cabin.get_node("Cabinet").get_node("Storage"))
			"multi":
				# a networked client: wait for the other players to spawn and settle (interpolation)
				await tree.create_timer(float(_flag_value("wait", "4.0"))).timeout
				var others := 0
				for c in world.get_node("Players").get_children():
					if c != player:
						others += 1
				print("multi: local peer %d sees %d remote players; net role=%s rtt=%.0f" % [Net.local_peer_id(), others, Net.role, float(Net.stats["rtt"])])
		if flags.has("noshadow"):
			(world.get_node("Sun") as DirectionalLight3D).shadow_enabled = false
		var dn: DayNight = world.get_node("DayNight")
		if flags.has("noambient"):
			dn.ambient_scale = 0.0
		if flags.has("halfsun"):
			dn.sun_scale = 0.5
		if flags.has("halfambient"):
			dn.ambient_scale = 0.5
		if flags.has("magenta"):
			var e := (world.get_node("Env") as WorldEnvironment).environment
			e.background_mode = Environment.BG_COLOR
			e.background_color = Color.MAGENTA
			e.fog_enabled = false
		if flags.has("nosun"):
			dn.sun_scale = 0.0
		var sun := world.get_node("Sun") as DirectionalLight3D
		print("sun dir=%s energy=%.2f visible=%s shadow=%s color=%s" % [-sun.global_transform.basis.z, sun.light_energy, sun.visible, sun.shadow_enabled, sun.light_color])
		var env := (world.get_node("Env") as WorldEnvironment).environment
		print("ambient=%s energy=%.2f fog=%.3f source=%d bg=%d" % [env.ambient_light_color, env.ambient_light_energy, env.fog_density, env.ambient_light_source, env.background_mode])
		if Net.is_server:
			WorldState.instance.running = false  # freeze the clock for a stable shot
		var rig := CameraRig.active()
		if rig != null:
			rig.snap_to_player()
	# let particles / shadows settle
	for i in 90:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := tree.root.get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	print("screenshot %s -> %s (%s)" % [preset, out_path, "ok" if err == OK else "error %d" % err])
	tree.quit(0)
