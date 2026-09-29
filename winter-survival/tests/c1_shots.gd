extends RefCounted
## C1 screenshot presets (loaded by tests/screenshot_steps.gd): Altavega's núcleo urbano in the game scene.
##   c1_bridge       10:30, arrival: the survivor on the Puente de Hierro, Las Torres ahead (gameplay camera, 40 m)
##   c1_casco        11:30, a street of the casco viejo (city profile)
##   c1_ensanche     12:00, a chaflán crossing of the ensanche
##   c1_barriada     13:00, between the slabs of the barriada de San Lázaro
##   c1_torres       11:00, Las Torres: the Gran Vía at Torre Albo
##   c1_rooftop      15:00, on the roof of the Edificio Meridiano (rooftop profile, dynamic far): the street below
##   c1_night        21:30, night skyline: a review camera low over the east end of the Puente de Hierro looking at
##                   Las Torres (street lamps of the Gran Vía and the bridge, generator windows, silhouettes beyond)
##   c1_tower_floor  11:00, inside the Edificio Meridiano, a furnished floor (the cut shows the offices)
##   c1_control      10:00, the Control del Puerto at the entrance of the city
##   c1_aerial       14:00, a review camera high over the river: casco, bridge, Las Torres, ensanche
##   RENDER=forward tests/run_screenshots.sh docs/screenshots/c1 c1_bridge c1_casco c1_ensanche …
## Camera yaw 45°: screen right = (+x, −z), toward the camera = (+x, +z).

const SPOTS := {
	"c1_bridge": [Vector3(2468.0, 0.0, -391.0), 10.5, 40.0],
	"c1_casco": [Vector3(2002.6, 0.0, -512.8), 11.5, 34.0],
	"c1_ensanche": [Vector3(3003.0, 0.0, -511.0), 12.0, 38.0],
	"c1_barriada": [Vector3(2065.0, 0.0, 342.5), 13.0, 40.0],
	"c1_torres": [Vector3(2690.0, 0.0, -370.0), 11.0, 42.0],
	"c1_rooftop": [Vector3(2812.0, 0.0, -446.0), 15.0, 46.0],
	"c1_night": [Vector3(2600.0, 0.0, -384.0), 21.5, 40.0],
	"c1_tower_floor": [Vector3(2812.0, 0.0, -446.0), 11.0, 30.0],
	"c1_control": [Vector3(1542.0, 0.0, -384.0), 10.0, 40.0],
	"c1_aerial": [Vector3(2520.0, 0.0, -420.0), 14.0, 40.0],
}

var tree: SceneTree


func setup(p_tree: SceneTree, preset: String, game: Node, world: World, player: Player, _inv: InventoryComponent) -> void:
	tree = p_tree
	var spec: Array = SPOTS.get(preset, SPOTS["c1_ensanche"])
	var pos: Vector3 = spec[0]
	WorldState.instance.set_time(1, float(spec[1]))
	world.get_node("WolfSpawner").enabled = false
	world.get_node("DeerSpawner").enabled = false
	if Director.instance != null:
		Director.instance.enabled = false
	if PopulationManager.instance != null:
		PopulationManager.instance.enabled = false
	if ZombieSystem.instance != null:
		ZombieSystem.instance.clear_all()
	world.streamer.ensure_loaded(pos, 2)
	var hero: HeroTower = null
	var mir: Mirador = null
	match preset:
		"c1_rooftop", "c1_tower_floor":
			for i in 60:
				await tree.process_frame
				hero = _hero(world, 902)
				if hero != null:
					break
			if hero != null:
				hero.finish_now()
				if preset == "c1_rooftop":
					pos = hero.landing_point(hero.floors, 4.0)
				elif preset == "c1_tower_floor":
					pos = hero.landing_point(3, 4.5)
	if hero == null:
		pos.y = world.get_height(pos.x, pos.z) + 0.05
		var deck := CityLots.bridge_deck(world.hf, pos.x, pos.z)
		if not is_nan(deck):
			pos.y = deck + 0.05
	player.position = pos
	player.net_position = pos
	player.velocity = Vector3.ZERO
	player.set("input_enabled", false)
	player.aim_yaw = deg_to_rad(-135.0)
	for i in 30:
		await tree.physics_frame
	if player.global_position.y < pos.y - 3.0:
		# no collider under the spot yet (or a footprint): hold the player where it was put
		player.set_physics_process(false)
		player.position = pos
		player.net_position = pos
	world.streamer.ensure_loaded(pos, 2)
	var rig := CameraRig.active()
	if rig != null:
		rig.snap_to_player()
		rig.snap_profile()
		rig.dist = clampf(float(spec[2]), rig.profile.dist_min, rig.profile.dist_max)
		rig.camera.position = Vector3(0, 0, rig.dist)
	for i in 40:
		await tree.process_frame
	var ui := game.get_node_or_null("UI") as CanvasLayer
	if preset == "c1_aerial" or preset == "c1_night":
		# a review camera (not the gameplay one): [position, look-at, streaming focus]
		var night := preset == "c1_night"
		var cam_at := Vector3(2470.0, 30.0, -318.0) if night else Vector3(2330.0, 150.0, -150.0)
		var look := Vector3(2730.0, 62.0, -436.0) if night else Vector3(2600.0, 10.0, -520.0)
		if ui != null:
			ui.visible = false
		world.env_override = true
		var dn: DayNight = world.get_node("DayNight")
		dn.fog_density_scale = 0.3 if night else 0.12
		(world.get_node("Sun") as DirectionalLight3D).directional_shadow_max_distance = 600.0
		world.streamer.focus_override = Vector3(2640.0, 0.0, -400.0) if night else Vector3(2500.0, 0.0, -430.0)
		world.streamer.ring_prefetch = 4 if night else 5
		world.streamer.flush_all()
		if CityWorld.instance != null:
			CityWorld.instance.set_skyline(true)
		if night and CityLights.instance != null:
			# the real lamp lights go to the lamps of the Gran Vía in front of the camera
			var focus := Node3D.new()
			world.add_child(focus)
			focus.global_position = Vector3(2600.0, 0.0, -390.0)
			CityLights.instance.focus_override = focus
		var cam := Camera3D.new()
		cam.name = "AerialCamera"
		cam.fov = 55.0 if not night else 60.0
		cam.far = 2500.0
		world.add_child(cam)
		cam.global_position = cam_at
		cam.look_at(look, Vector3.UP)
		cam.current = true
	if mir != null:
		if ui != null:
			ui.visible = false
		mir.duration = 1.0e6
		mir.activate(player)
		for i in 6:
			await tree.process_frame
	for i in 20:
		await tree.process_frame
	print("c1 shot %s: player %s, chunks %d, city buildings %d, profile %s far %.0f, hero %s, mirador %s" % [preset, player.global_position.snapped(Vector3(0.1, 0.1, 0.1)),
		world.streamer.loaded_keys().size(), CityCut.buildings().size(), rig.profile.id if rig != null else &"-", rig.camera.far if rig != null else 0.0,
		hero.name if hero != null else "-", mir != null and mir.active])


func _hero(world: World, id: int) -> HeroTower:
	for n in world.get_tree().get_nodes_in_group("hero_tower"):
		if (n as HeroTower).hero_id == id:
			return n as HeroTower
	return null
