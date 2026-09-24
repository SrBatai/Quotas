extends RefCounted
## Screenshot preset body (loaded at runtime by tests/screenshot.gd).

var tree: SceneTree
var flags: Array[String] = []  # debug flags: noshadow, noambient

var preset: String = "day"
var out_path: String = "/tmp/ventisca_shot.png"


func run(p_tree: SceneTree, p_preset: String, p_out: String) -> void:
	tree = p_tree
	preset = p_preset
	out_path = p_out
	await tree.process_frame
	if preset == "menu":
		tree.change_scene_to_file("res://scenes/main/main_menu.tscn")
	else:
		tree.change_scene_to_file("res://scenes/main/game.tscn")
	var waited := 0
	var ready := false
	Events.world_ready.connect(func() -> void: ready = true)
	while not ready and waited < 900:
		await tree.process_frame
		waited += 1
	await tree.process_frame
	await tree.process_frame
	var game := tree.current_scene
	if preset != "menu":
		var player: Player = game.get_node("Player")
		var world: World = game.get_node("World")
		Events.notify.emit("", 0.1)
		match preset:
			"day":
				GameState.set_time(1, 11.0)
				Inventory.add(&"hacha", 1)
				Inventory.add(&"madera", 7)
				Inventory.add(&"piedra", 6)
			"night":
				GameState.set_time(1, 22.5)
				Inventory.add(&"madera", 6)
				Inventory.add(&"piedra", 6)
				Inventory.add(&"lata_sopa", 1)
				Inventory.add(&"antorcha", 1)
				var cf := preload("res://scenes/world/campfire.tscn").instantiate()
				world.get_node("Actors").add_child(cf)
				var p := player.global_position + Vector3(-2.2, 0, 2.0)
				p.y = world.get_height(p.x, p.z)
				cf.global_position = p
				world.get_node("WolfSpawner").enabled = false
			"blizzard":
				GameState.set_time(1, 15.0)
				Inventory.add(&"hacha", 1)
				Inventory.add(&"madera", 4)
				var weather: Weather = world.get_node("Weather")
				weather.force_blizzard(60.0)
				world.get_node("DayNight").blizzard_blend = 1.0
			"interior":
				GameState.set_time(1, 21.0)
				Inventory.add(&"hacha", 1)
				Inventory.add(&"madera", 6)
				Inventory.add(&"piedra", 6)
				player.global_position = world.cabin.global_position + Vector3(-1.3, 0.6, 0.5)
				player.get_node("Visual").rotation.y = -PI * 0.5
				world.get_node("WolfSpawner").enabled = false
				var storage_panel: StoragePanel = game.get_node("UI/StoragePanel")
				storage_panel.open(world.cabin.get_node("Cabinet").get_node("Storage"))
		if flags.has("noshadow"):
			(world.get_node("Sun") as DirectionalLight3D).shadow_enabled = false
		if flags.has("noambient"):
			(world.get_node("Env") as WorldEnvironment).environment.ambient_light_energy = 0.0
		var sun := world.get_node("Sun") as DirectionalLight3D
		print("sun dir=%s energy=%.2f visible=%s shadow=%s color=%s" % [-sun.global_transform.basis.z, sun.light_energy, sun.visible, sun.shadow_enabled, sun.light_color])
		var env := (world.get_node("Env") as WorldEnvironment).environment
		print("ambient=%s energy=%.2f fog=%.3f" % [env.ambient_light_color, env.ambient_light_energy, env.fog_density])
		GameState.is_running = false  # freeze the clock for a stable shot
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
