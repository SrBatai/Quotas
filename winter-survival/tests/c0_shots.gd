extends RefCounted
## C0 screenshot presets (loaded by tests/screenshot_steps.gd): the first block of Altavega in its place.
##   altavega_c0_day    11:00, the survivor on the Gran Vía sidewalk at the SW podium, the jam behind (44 m zoom)
##   altavega_c0_night  22:30, in front of the generator lot: its windows and lamps lit, the rest in blackout
##   mirador            16:55, the provisional mirador on the SW podium roof held (−7°, far 1 500 m, silhouettes)
##   altavega_c0_aerial 15:30, a high camera south-east of the block: the superblock, the jam, the bridge (review)
##   RENDER=forward tests/run_screenshots.sh docs/screenshots/c0 altavega_c0_day altavega_c0_night mirador menu_skyline
## Camera yaw 45°: screen right = (+x, −z), toward the camera = (+x, +z).

const SPOT := Vector3(2667.0, 0.0, -390.0)   # Gran Vía, between the jam's two northern lanes, the SW podium beyond
const ZOOM := 32.0
## Day: the north sidewalk at the SW podium's corner (the mirador terrace, tower T21 and the jam in frame, city profile
## zoomed out); night: in front of the generator lot (SE podium + the 40-floor T22, its windows and street lamps lit).
const DAY_SPOT := Vector3(2662.0, 0.0, -400.0)
const NIGHT_SPOT := Vector3(2744.0, 0.0, -399.0)

var tree: SceneTree


func setup(p_tree: SceneTree, preset: String, game: Node, world: World, player: Player, _inv: InventoryComponent) -> void:
	tree = p_tree
	var hour := 11.0
	match preset:
		"altavega_c0_night":
			hour = 22.5
		"mirador":
			hour = 16.9
		"altavega_c0_aerial":
			hour = 15.5
	WorldState.instance.set_time(1, hour)
	world.get_node("WolfSpawner").enabled = false
	world.get_node("DeerSpawner").enabled = false
	if Director.instance != null:
		Director.instance.enabled = false
	if PopulationManager.instance != null:
		PopulationManager.instance.enabled = false
	if ZombieSystem.instance != null:
		ZombieSystem.instance.clear_all()
	var pos := SPOT
	var zoom := ZOOM
	match preset:
		"altavega_c0_day":
			pos = DAY_SPOT
			zoom = 44.0
		"altavega_c0_night":
			pos = NIGHT_SPOT
			zoom = 38.0
	var mir: Mirador = null
	if preset == "mirador" and CityWorld.instance != null and not CityWorld.instance.miradores.is_empty():
		mir = CityWorld.instance.miradores[0]
	world.streamer.ensure_loaded(pos, 2)
	if mir != null:
		pos = mir.global_position + Vector3(0.6, 0.05, 0.4)
	else:
		pos.y = world.get_height(pos.x, pos.z) + 0.05
	player.position = pos
	player.net_position = pos
	player.velocity = Vector3.ZERO
	player.set("input_enabled", false)
	player.aim_yaw = deg_to_rad(-135.0)
	for i in 30:
		await tree.physics_frame
	world.streamer.ensure_loaded(pos, 2)
	var rig := CameraRig.active()
	if rig != null:
		rig.snap_to_player()
		rig.snap_profile()
		if mir == null:
			rig.dist = clampf(zoom, rig.profile.dist_min, rig.profile.dist_max)
			rig.camera.position = Vector3(0, 0, rig.dist)
	for i in 30:
		await tree.process_frame
	var ui := game.get_node_or_null("UI") as CanvasLayer
	if preset == "altavega_c0_aerial":
		if ui != null:
			ui.visible = false
		world.env_override = true
		var dn: DayNight = world.get_node("DayNight")
		dn.fog_density_scale = 0.15
		(world.get_node("Sun") as DirectionalLight3D).directional_shadow_max_distance = 500.0
		world.streamer.focus_override = Vector3(2660.0, 0.0, -430.0)
		world.streamer.ring_prefetch = 4
		world.streamer.flush_all()
		var cam := Camera3D.new()
		cam.name = "AerialCamera"
		cam.fov = 50.0
		cam.far = 1500.0
		world.add_child(cam)
		cam.global_position = Vector3(2712.0, 62.0, -352.0)
		cam.look_at(Vector3(2655.0, 15.0, -430.0), Vector3.UP)
		cam.current = true
	if mir != null:
		if ui != null:
			ui.visible = false
		mir.duration = 1.0e6   # held for the whole capture (a software-rendered frame takes 0.1–0.5 s of game time)
		mir.activate(player)
		for i in 4:
			await tree.process_frame
	print("c0 shot %s: player %s, chunks %d, city buildings %d, profile %s, mirador %s" % [preset, player.global_position.snapped(Vector3(0.1, 0.1, 0.1)),
		world.streamer.loaded_keys().size(), CityCut.buildings().size(), rig.profile.id if rig != null else &"-", mir != null and mir.active])
