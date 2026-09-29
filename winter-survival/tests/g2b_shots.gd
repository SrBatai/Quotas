extends RefCounted
## G2b screenshot presets (loaded by tests/screenshot_steps.gd for presets g2b_*): the atmosphere of every hour.
##   g2b_sheet        contact sheet: 8 hours × 3 weathers (clear / overcast / blizzard) of the clearing, 24 tiles in
##                    one process, written to --out (and the tiles next to it: <out>_tiles/); the sheet preset saves
##                    and quits by itself
##   g2b_sheet_city   the same sheet on the Gran Vía in front of the superblock LT-01 (C0)
##   g2b_dawn         the clearing at 7:10, clear: morning mist in the valley, long cold light
##   g2b_blizzard     the clearing at 15:00 in a blizzard: whiteout, snow snakes, the pines bent
##   g2b_city_dusk    Altavega at 18:54, clear: the low sun scattering in the street haze between the towers
##   g2b_city_night   the Gran Vía at 22:30: beacons on the jam, smouldering wrecks, cables, the generator block lit
##   g2b_night_fire   the clearing at 22:30: a campfire melting the snow, chimney smoke, the stove's glow
##   RENDER=forward tests/run_screenshots.sh docs/screenshots/g2b g2b_sheet g2b_dawn …   (compat: the same presets)
## Flags: --weather=clear|overcast|blizzard and --hour=h override a hero preset; --nolut disables the grade.
## Camera yaw 45°: screen right = (+x, −z), toward the camera = (+x, +z).

const HOURS := [5.2, 7.2, 9.5, 12.5, 16.0, 18.6, 19.8, 22.5]
const WEATHERS := ["clear", "overcast", "blizzard"]
const TILE := Vector2i(480, 270)
const CITY_SPOT := Vector3(2667.0, 0.0, -392.0)
const CITY_NIGHT_SPOT := Vector3(2700.0, 0.0, -388.0)
const WIND_YAW := 0.9

var tree: SceneTree
var world: World
var player: Player
var flags: Array[String] = []


func _flag(name: String, default: String) -> String:
	for f in flags:
		if f.begins_with(name + "="):
			return f.substr(name.length() + 1)
	return default


func setup(p_tree: SceneTree, preset: String, game: Node, p_world: World, p_player: Player, inv: InventoryComponent, out_path: String, p_flags: Array[String]) -> void:
	tree = p_tree
	world = p_world
	player = p_player
	flags = p_flags
	world.get_node("WolfSpawner").enabled = false
	world.get_node("DeerSpawner").enabled = false
	if Director.instance != null:
		Director.instance.enabled = false
	if PopulationManager.instance != null:
		PopulationManager.instance.enabled = false
	if ZombieSystem.instance != null:
		ZombieSystem.instance.clear_all()
	var ui := game.get_node_or_null("UI") as CanvasLayer
	if ui != null:
		ui.visible = false
	var city := preset.contains("city")
	var atmo := Atmosphere.instance
	if atmo != null and flags.has("nolut"):
		atmo.lut_enabled = false
	# day 3: the cloud clock runs (day 1 stays clear by design); the presets force their own weather anyway
	var hour := 12.0
	var weather := "clear"
	match preset:
		"g2b_dawn":
			hour = 7.2
		"g2b_blizzard":
			hour = 15.0
			weather = "blizzard"
		"g2b_city_dusk":
			hour = 18.9
		"g2b_city_night", "g2b_night_fire":
			hour = 22.5
	hour = float(_flag("hour", str(hour)))
	weather = _flag("weather", weather)
	WorldState.instance.set_time(3, hour)
	if city:
		await _to_city(CITY_NIGHT_SPOT if preset == "g2b_city_night" else CITY_SPOT, 38.0 if preset != "g2b_city_night" else 34.0)
		if preset == "g2b_city_night" and flags.has("near_beacon"):
			await _near_beacon()   # optional: the city layout moves under C1, the Gran Vía spot stays on the street
	else:
		await _to_clearing(preset)
	if preset == "g2b_night_fire":
		world.cabin.stove.burner.add_fuel(600.0)
		inv.add(&"madera", 6)
		var p := player.global_position + Vector3(-2.4, 0, 2.2)
		p.y = world.get_height(p.x, p.z)
		world.spawn_placed("campfire", p, 0.0)
	if preset.begins_with("g2b_sheet"):
		await _sheet(out_path, city)
		return
	await set_conditions(hour, weather)
	# thaw rings grow over ~40 s of burning: show a fire that has been going for a while
	if atmo != null:
		atmo._clock += 120.0
		atmo._update_heat()
	print("g2b shot %s: %.1f h, %s, overcast %.2f, blizzard %.2f, vol %s (%.4f), LUT %s, beacons %d, smoke %d, cables %d" % [preset, hour, weather,
		atmo.overcast if atmo != null else -1.0, (world.get_node("DayNight") as DayNight).blizzard_blend,
		atmo.volumetric_on if atmo != null else false, atmo.volumetric_density if atmo != null else 0.0,
		_lut_str(atmo), atmo.life.beacons.count() if atmo != null else 0, _smoke_count(atmo), atmo.life.cables.count() if atmo != null else 0])
	print("g2b life %s" % _near_life(atmo))


## Weather and hour now, all transitions skipped (blizzard blend, snow emitters refilled, LUT blended).
func set_conditions(hour: float, weather: String) -> void:
	WorldState.instance.set_time(3, hour)
	var dn: DayNight = world.get_node("DayNight")
	var w: Weather = world.get_node("Weather")
	var atmo := Atmosphere.instance
	if weather == "blizzard":
		w.force_blizzard(600.0)
		dn.blizzard_blend = 1.0
	else:
		w.cancel()
		dn.blizzard_blend = 0.0
	# one wind for every shot (force_blizzard rolls a random direction): blowing toward screen left-down
	WorldState.instance.set_weather(&"blizzard" if weather == "blizzard" else &"clear", WIND_YAW)
	if atmo != null:
		atmo.overcast_override = 1.0 if weather == "overcast" else (0.0 if weather == "clear" else 1.0)
	WorldState.instance.running = false
	dn.apply(hour)
	var sf := world.get_node_or_null("Snowfall") as Snowfall
	if sf != null:
		sf.set_blizzard(weather == "blizzard", WorldState.instance.wind_yaw)
		if weather == "blizzard":
			sf.heavy_snow.restart()
	for i in 3:
		await tree.process_frame
	var drift := world.get_node_or_null("SnowDrift") as SnowDrift
	if drift != null:
		drift._apply_wind()
		drift.restart()
	if atmo != null:
		atmo._update_snowfall()
		atmo.flush_lut()


func _to_clearing(preset: String) -> void:
	var rig := CameraRig.active()
	var spawn := world.get_spawn_point()
	var pos := spawn + Vector3(3.0, 0.0, 5.0)
	if preset == "g2b_dawn" or preset.begins_with("g2b_sheet"):
		pos = spawn + Vector3(4.0, 0.0, 6.0)
	pos.y = world.get_height(pos.x, pos.z) + 0.05
	player.global_position = pos
	player.set("net_position", pos)
	player.set("input_enabled", false)
	player.aim_yaw = deg_to_rad(-135.0)
	for i in 20:
		await tree.physics_frame
	if rig != null:
		rig.snap_to_player()
		rig.set_dist(30.0)
		rig.camera.position = Vector3(0, 0, rig.dist)


func _to_city(spot: Vector3, zoom: float) -> void:
	world.streamer.ensure_loaded(spot, 2)
	var pos := Vector3(spot.x, world.get_height(spot.x, spot.z) + 0.05, spot.z)
	player.position = pos
	player.set("net_position", pos)
	player.velocity = Vector3.ZERO
	player.set("input_enabled", false)
	player.aim_yaw = deg_to_rad(-135.0)
	for i in 30:
		await tree.physics_frame
	world.streamer.ensure_loaded(pos, 2)
	var waited := 0
	while not world.streamer.is_idle() and waited < 600:
		await tree.process_frame
		waited += 1
	var rig := CameraRig.active()
	if rig != null:
		rig.snap_to_player()
		rig.snap_profile()
		rig.dist = clampf(zoom, rig.profile.dist_min, rig.profile.dist_max)
		rig.camera.position = Vector3(0, 0, rig.dist)
	# AmbientLife polls the streamed chunks twice a second
	for i in 40:
		await tree.process_frame


## Night hero: stand ~9 m camera-side of the nearest rotating beacon (a police car of the jam) so it is in frame.
func _near_beacon() -> void:
	var atmo := Atmosphere.instance
	if atmo == null:
		return
	var best := Vector3.INF
	for b in atmo.life.beacons.beacons:
		if int(b["mode"]) != BeaconLights.Mode.ROTATE:
			continue
		var p: Vector3 = b["pos"]
		if best == Vector3.INF or p.distance_to(CITY_NIGHT_SPOT) < best.distance_to(CITY_NIGHT_SPOT):
			best = p
	if best == Vector3.INF or best.distance_to(CITY_NIGHT_SPOT) > 150.0:
		return
	# on open street: the first offset around the car that is inside no city building and near the car's ground level
	for off in [Vector3(6.5, 0, 6.5), Vector3(8.0, 0, 0), Vector3(-8.0, 0, 0), Vector3(0, 0, 8.0), Vector3(0, 0, -8.0), Vector3(-6.5, 0, 6.5)]:
		var p: Vector3 = best + off
		p.y = world.get_height(p.x, p.z)
		var free := absf(p.y - (best.y - 1.5)) < 1.5
		for cb in CityCut.buildings():
			if (cb as CityBuilding).contains(p + Vector3(0, 1.0, 0)) or (cb as CityBuilding).contains(p + Vector3(0, 3.0, 0)):
				free = false
		if free:
			await _to_city(p, 30.0)
			return


## 8 hours × 3 weathers in one process: rows = weathers, columns = hours.
func _sheet(out_path: String, city: bool) -> void:
	var sheet := Image.create_empty(TILE.x * HOURS.size(), TILE.y * WEATHERS.size(), false, Image.FORMAT_RGB8)
	var tiles_dir := out_path.get_basename() + "_tiles"
	DirAccess.make_dir_recursive_absolute(tiles_dir)
	var settle := int(_flag("settle", "10"))
	var rig := CameraRig.active()
	for wi in WEATHERS.size():
		for hi in HOURS.size():
			var hour: float = HOURS[hi]
			await set_conditions(hour, WEATHERS[wi])
			if rig != null:
				rig.snap_to_player()
			for i in settle:
				await tree.process_frame
			await RenderingServer.frame_post_draw
			var img := tree.root.get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.save_png("%s/%s_%02d%02d.png" % [tiles_dir, WEATHERS[wi], int(hour), int(round(fmod(hour, 1.0) * 60.0))])
			img.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i(hi * TILE.x, wi * TILE.y))
			var atmo := Atmosphere.instance
			print("g2b sheet %s %5.2f h: overcast %.2f blizzard %.2f vol %s LUT %s" % [WEATHERS[wi], hour, atmo.overcast if atmo != null else -1.0,
				(world.get_node("DayNight") as DayNight).blizzard_blend, atmo.volumetric_on if atmo != null else false, _lut_str(atmo)])
	var err := sheet.save_png(out_path)
	print("screenshot %s -> %s (%s)" % ["g2b_sheet_city" if city else "g2b_sheet", out_path, "ok" if err == OK else "error %d" % err])
	tree.quit(0)
	await tree.process_frame


## What of the render-side life is near the player (debug line of the city presets).
func _near_life(atmo: Atmosphere) -> String:
	if atmo == null:
		return "-"
	var p := player.global_position
	var nb := 0
	for b in atmo.life.beacons.beacons:
		if (b["pos"] as Vector3).distance_to(p) < 40.0:
			nb += 1
	var ns := 0
	for k in atmo.life.smoke:
		for c in atmo.life.smoke[k]:
			if is_instance_valid(c) and (c as Node3D).global_position.distance_to(p) < 40.0:
				ns += 1
	return "within 40 m: %d beacons, %d smoke columns, real spots %d" % [nb, ns, atmo.life.beacons.real_lights_on()]


func _lut_str(atmo: Atmosphere) -> String:
	if atmo == null or atmo.lut == null:
		return "-"
	var parts: Array[String] = []
	var w := atmo.lut.shown()
	for i in w.size():
		if w[i] > 0.01:
			parts.append("%s %.2f" % [LutGrade.NAMES[i], w[i]])
	return ", ".join(parts)


func _smoke_count(atmo: Atmosphere) -> int:
	if atmo == null:
		return 0
	var n := 0
	for k in atmo.life.smoke:
		n += (atmo.life.smoke[k] as Array).size()
	return n
