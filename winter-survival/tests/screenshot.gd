extends SceneTree
## Screenshot presets (xvfb + Compatibility). Args after "++": --preset=day|night|blizzard|interior|menu --out=path.png

var preset: String = "day"
var out_path: String = "/tmp/ventisca_shot.png"


var events: Node
var game_state: Node
var inventory: Node
var quest_manager: Node


func _initialize() -> void:
	events = root.get_node("Events")
	game_state = root.get_node("GameState")
	inventory = root.get_node("Inventory")
	quest_manager = root.get_node("QuestManager")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--preset="):
			preset = a.substr(9)
		elif a.begins_with("--out="):
			out_path = a.substr(6)
	Engine.max_fps = 60
	_run()


func _run() -> void:
	await process_frame
	if preset == "menu":
		change_scene_to_file("res://scenes/main/main_menu.tscn")
	else:
		change_scene_to_file("res://scenes/main/game.tscn")
	var waited := 0
	var ready := false
	events.world_ready.connect(func() -> void: ready = true)
	while not ready and waited < 900:
		await process_frame
		waited += 1
	await process_frame
	await process_frame
	var game := current_scene
	if preset != "menu":
		var player: Player = game.get_node("Player")
		var world: World = game.get_node("World")
		events.notify.emit("", 0.1)
		match preset:
			"day":
				game_state.set_time(1, 11.0)
				inventory.add(&"hacha", 1)
				inventory.add(&"madera", 7)
				inventory.add(&"piedra", 6)
			"night":
				game_state.set_time(1, 22.5)
				inventory.add(&"madera", 6)
				inventory.add(&"piedra", 6)
				inventory.add(&"lata_sopa", 1)
				inventory.add(&"antorcha", 1)
				var cf := preload("res://scenes/world/campfire.tscn").instantiate()
				world.get_node("Actors").add_child(cf)
				var p := player.global_position + Vector3(-2.2, 0, 2.0)
				p.y = world.get_height(p.x, p.z)
				cf.global_position = p
				world.get_node("WolfSpawner").enabled = false
			"blizzard":
				game_state.set_time(1, 15.0)
				inventory.add(&"hacha", 1)
				inventory.add(&"madera", 4)
				var weather: Weather = world.get_node("Weather")
				weather.force_blizzard(60.0)
				world.get_node("DayNight").blizzard_blend = 1.0
			"interior":
				game_state.set_time(1, 21.0)
				inventory.add(&"hacha", 1)
				inventory.add(&"madera", 6)
				inventory.add(&"piedra", 6)
				player.global_position = world.cabin.global_position + Vector3(0.6, 0.6, -0.4)
				player.get_node("Visual").rotation.y = PI * 0.5
				world.get_node("WolfSpawner").enabled = false
				var storage_panel: StoragePanel = game.get_node("UI/StoragePanel")
				storage_panel.open(world.cabin.get_node("Cabinet").get_node("Storage"))
		game_state.is_running = false  # freeze the clock for a stable shot
		var rig := CameraRig.active()
		if rig != null:
			rig.snap_to_player()
	# let particles / shadows settle
	for i in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	print("screenshot %s -> %s (%s)" % [preset, out_path, "ok" if err == OK else "error %d" % err])
	quit(0)
