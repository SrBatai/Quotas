extends RefCounted
## Screenshot preset body (loaded at runtime by tests/screenshot.gd). Presets day/dusk/night/blizzard/interior/menu run
## the offline local server; `multi` joins a running dedicated server (--host=ip --port=n) to prove remote players render.
## M3 `overview`: a camera 230 m up over the Lago de las Ánimas north shore (several streamed chunks, the flat ice,
## the lake-north track and the Embarcadero road bed), streaming focused there with ring 4 (9 × 9 chunks).

var tree: SceneTree
var flags: Array[String] = []  # debug flags: noshadow, noambient, placeholders, host=ip, port=n, zoom=m, walk=walk|run, quality=alto|medio|compat

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
	# lavapipe is a CPU device, which Quality.detect() maps to `compat`: Forward+ shots use `alto` unless told otherwise
	var quality := _flag_value("quality", "" if Quality.is_compat_renderer() else "alto")
	if quality != "":
		Quality.set_preset(StringName(quality), false)
	var ready := false
	Events.world_ready.connect(func() -> void:
		ready = true
		# under a software renderer a frame can take seconds of game clock: stop the blizzard roll before the
		# clock reaches 14:00 (the preset below sets the time it wants)
		var w := tree.current_scene.get_node_or_null("World/Weather") as Weather
		if w != null and Net.is_server:
			w.scheduler_enabled = false
			w.cancel())
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
			(world.get_node("Weather") as Weather).cancel()
			(world.get_node("DayNight") as DayNight).blizzard_blend = 0.0
		var inv: InventoryComponent = player.state.inventory
		match preset:
			"day":
				WorldState.instance.set_time(1, 11.0)
				inv.add(&"hacha", 1)
				inv.add(&"madera", 7)
				inv.add(&"piedra", 6)
			"dusk":
				WorldState.instance.set_time(1, 19.0)
				world.cabin.stove.burner.add_fuel(600.0)
				inv.add(&"hacha", 1)
				inv.add(&"madera", 6)
				inv.add(&"piedra", 6)
				world.get_node("WolfSpawner").enabled = false
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
			"items":
				# rendered item icons: a varied hotbar + the FUEGO craft panel open (like the reference shot)
				WorldState.instance.set_time(1, 17.5)
				world.cabin.stove.burner.add_fuel(600.0)
				inv.add(&"hacha", 1)
				inv.add(&"madera", 6)
				inv.add(&"piedra", 6)
				inv.add(&"lata_judias", 2)
				inv.add(&"carne_asada", 1)
				inv.add(&"bayas", 5)
				inv.add(&"piel", 1)
				inv.add(&"antorcha", 1)
				world.get_node("WolfSpawner").enabled = false
				await tree.process_frame
				var game_node := tree.current_scene
				if game_node.get("craft_panel") != null:
					(game_node.get("craft_panel") as CraftPanel).open(&"fuego")
			"overview":
				WorldState.instance.set_time(1, 11.0)
				world.get_node("WolfSpawner").enabled = false
				var target := Vector3(-590.0, -4.0, 230.0)
				var cam_pos := Vector3(-360.0, 230.0, -70.0)
				world.env_override = true
				Chat.instance.send("/tp -470 60")
				await tree.process_frame
				world.streamer.focus_override = target
				world.streamer.ring_prefetch = 4
				world.streamer.flush_all()
				var dn: DayNight = world.get_node("DayNight")
				dn.fog_density_scale = 0.12
				dn.fog_height_offset = -60.0
				var sun := world.get_node("Sun") as DirectionalLight3D
				sun.directional_shadow_max_distance = 700.0
				var cam := Camera3D.new()
				cam.name = "OverviewCamera"
				cam.fov = 48.0
				cam.far = 1400.0
				world.add_child(cam)
				cam.global_position = cam_pos
				cam.look_at(target, Vector3.UP)
				cam.current = true
				print("overview: %d chunks loaded around %s" % [world.streamer.loaded_keys().size(), target])
			"multi":
				# a networked client: wait for the other players to spawn and settle (interpolation)
				await tree.create_timer(float(_flag_value("wait", "4.0"))).timeout
				var others := 0
				var outfits := []
				for c in world.get_node("Players").get_children():
					if c != player:
						others += 1
						outfits.append(c.get("outfit"))
				Chat.instance.send("/give hacha 1")
				print("multi: local peer %d (outfit %d) sees %d remote players (outfits %s); net role=%s rtt=%.0f" % [Net.local_peer_id(), player.outfit, others, outfits, Net.role, float(Net.stats["rtt"])])
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
		print("ambient=%s energy=%.2f fog=%.3f exposure=%.2f tonemap=%d glow=%s ssao=%s vol=%s preset=%s trail=%s" % [env.ambient_light_color, env.ambient_light_energy, env.fog_density, env.tonemap_exposure, env.tonemap_mode, env.glow_enabled, env.ssao_enabled, env.volumetric_fog_enabled, Quality.preset, world.footprints.backend if world.footprints != null else "-"])
		if Net.is_server:
			WorldState.instance.running = false  # freeze the clock for a stable shot
		var rig := CameraRig.active()
		if rig != null and preset != "overview":
			rig.snap_to_player()
			if _flag_value("zoom", "") != "":
				rig.set_dist(float(_flag_value("zoom", "27")))   # closeup of the survivor (M2 skeletal checks)
		if _flag_value("walk", "") != "" and player.input != null:
			# mid-stride pose: walk (or run) along +X while the shot settles
			player.input.scripted_move = Vector2(1, 0)
			player.input.scripted_run = _flag_value("walk", "walk") == "run"
	# let particles / shadows settle
	for i in 90:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := tree.root.get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	print("screenshot %s -> %s (%s)" % [preset, out_path, "ok" if err == OK else "error %d" % err])
	tree.quit(0)
