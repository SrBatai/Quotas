extends RefCounted
## M6b screenshot presets (loaded by tests/screenshot_steps.gd for presets m6b_*): La Herrería and the three hand-made
## POIs in the game world (SettlementSpawner builds them with the streamed chunks).
##   m6b_village_day    11:00, the survivor on the Calle Mayor near the bar / shop (the village core)
##   m6b_village_night  22:30, the same place: street lamps (light pools + halos; real lights in Forward+)
##   m6b_sawmill        11:30, the sawmill yard: the saw line, log piles, the shed
##   m6b_gas_station    10:30, the Gasolinera Norte forecourt: canopy, pumps, wrecks, the price sign
##   m6b_farm           12:00, the Granja del Molino yard: the red barn, the silos, the round bales
##   m6b_house_inside   16:00, inside an enterable village house (storey 0): roof / upper storey hidden shadow-
##                      preserving by the CutawayManager, the front door open
##   RENDER=forward tests/run_screenshots.sh docs/screenshots/m6b m6b_village_day m6b_village_night m6b_sawmill \
##       m6b_gas_station m6b_farm m6b_house_inside

const HOURS := {"m6b_village_day": 11.0, "m6b_village_night": 22.5, "m6b_sawmill": 11.5, "m6b_gas_station": 10.5, "m6b_farm": 12.0,
	"m6b_house_inside": 16.0}
const ZOOMS := {"m6b_village_day": 32.0, "m6b_village_night": 28.0, "m6b_sawmill": 32.0, "m6b_gas_station": 30.0, "m6b_farm": 34.0,
	"m6b_house_inside": 24.0}

var tree: SceneTree


func setup(p_tree: SceneTree, preset: String, _game: Node, world: World, player: Player, inv: InventoryComponent) -> void:
	tree = p_tree
	WorldState.instance.set_time(1, float(HOURS.get(preset, 11.0)))
	world.get_node("WolfSpawner").enabled = false
	world.get_node("DeerSpawner").enabled = false
	if Director.instance != null:
		Director.instance.enabled = false
	if PopulationManager.instance != null:
		PopulationManager.instance.enabled = false
	if ZombieSystem.instance != null:
		ZombieSystem.instance.clear_all()
	var seed_v := world.seed_value
	var village := Settlements.site(seed_v, "la_herreria")
	var main: PackedVector2Array = ((village["streets"] as Array)[0] as Dictionary)["points"]
	var pos2 := Vector2.ZERO
	var house: Dictionary = {}
	match preset:
		"m6b_village_day", "m6b_village_night":
			# the bar (or the shop): the survivor on the street in front of it
			for b: Dictionary in village["buildings"]:
				if str(b["use"]) == "bar":
					pos2 = (b["p"] as Vector2) + (b["t"] as Vector2) * 4.0
			if pos2 == Vector2.ZERO:
				pos2 = SettlementGen.point_at(main, 70.0)[0]
		"m6b_sawmill":
			pos2 = Vector2(-625.0, -779.0)          # between the saw line, the log piles and the shed
		"m6b_gas_station":
			pos2 = Vector2(619.0, -388.0)
		"m6b_farm":
			pos2 = Vector2(-97.0, -902.0)           # south-east of the barn: the barn, the silos and the round bales
		"m6b_house_inside":
			for b: Dictionary in village["buildings"]:
				if str(b["use"]) == "house" and bool(b["enterable"]) and str(b["template"]).begins_with("house_small"):
					house = b
					break
			pos2 = house.get("pos", SettlementGen.point_at(main, 60.0)[0])
	var pos := Vector3(pos2.x, 0.0, pos2.y)
	world.streamer.ensure_loaded(pos, 2)
	pos.y = world.get_height(pos.x, pos.z) + (0.35 if preset == "m6b_house_inside" else 0.05)
	_place(player, pos)
	# the site chunks are built over a few frames once loaded
	var sp := SettlementSpawner.instance
	for i in 900:
		var all_done := true
		for k in WorldConst.ring_keys(WorldConst.chunk_of(pos.x), WorldConst.chunk_of(pos.z), 1):
			if sp != null and not Settlements.items_in_chunk(seed_v, k).is_empty():
				var sc: SettlementChunk = sp.live.get(k)
				if sc == null or not is_instance_valid(sc) or not sc.done:
					all_done = false
		if all_done and i > 30:
			break
		await tree.process_frame
	_place(player, pos)
	inv.add(&"hacha", 1)
	if preset == "m6b_village_night":
		inv.add(&"antorcha", 1)
	if preset == "m6b_house_inside" and not house.is_empty() and sp != null:
		var b := sp.building("la_herreria", int(house["index"]))
		if b != null:
			for d in b.doors:
				if d.exterior:
					d.server_interact(player, &"open", 0)
					break
	for i in 30:
		await tree.physics_frame
	var rig := CameraRig.active()
	if rig != null:
		rig.snap_to_player()
		rig.snap_profile()
		var z := float(ZOOMS.get(preset, 30.0))
		rig.dist = z
		rig.camera.position = Vector3(0, 0, z)
	for i in 30:
		await tree.process_frame
	var mgr := CutawayManager.instance
	if mgr != null:
		mgr.update()
	print("m6b shot %s: player %s, %d site chunks live, %d buildings, inside %s, lamps %d (real %d)" % [preset,
		player.global_position.snapped(Vector3(0.1, 0.1, 0.1)), sp.live.size() if sp != null else 0, sp.all_buildings().size() if sp != null else 0,
		mgr.inside if mgr != null else false, sp.lights.lamps.size() if sp != null and sp.lights != null else 0,
		sp.lights.real_lights_on() if sp != null and sp.lights != null else 0])


func _place(player: Player, pos: Vector3) -> void:
	player.position = pos
	player.net_position = pos
	player.velocity = Vector3.ZERO
	player.set("input_enabled", false)
