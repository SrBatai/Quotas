extends RefCounted
## H2 screenshot presets (called by tests/screenshot_steps.gd for presets named zone_*, rendered at 1920 × 1080):
##   zone_card          the first-visit title as in mockup v2_c, frame 2 (t = 1.8 s: tracking settled at .42 em, the
##                      hairline and the one line of facts): «LAS TORRES» · «Altavega · sin electricidad · −18 °C ·
##                      peligro …», staged over the clearing at night like the mockup (Altavega has no buildings until
##                      C1); the card is the one the ZoneTracker builds for the real Las Torres record
##   zone_card_t05      the same card at t = 0.5 s (letters still open, .78 → .42 em) — mockup frame 1
##   zone_card_t46      the same card at t = 4.6 s (fading over the world) — mockup frame 3
##   zone_sign_vehicle  a scripted fast mover (25 m/s = 90 km/h) southbound on the A‑14 north of Altavega: the
##                      ZoneTracker is fed its positions and confirms the Autovía A‑14 → the highway sign, top right
##                      («Altavega 2 km / SALIDA 1 · Gran Vía →», «A‑14 · sin electricidad · −8 °C»); the player
##                      stands where the mover is (no vehicles until M7)
## Run: RENDER=forward tests/run_screenshots.sh <dir> zone_card zone_sign_vehicle

var tree: SceneTree


func setup(p_tree: SceneTree, preset: String, game: Node, world: World, player: Player, inv: InventoryComponent) -> void:
	tree = p_tree
	var hud: Hud = game.get("hud")
	if hud == null:
		print("FAIL: no HUD")
		return
	UiSettings.get_instance().reset()
	world.get_node("WolfSpawner").enabled = false
	hud.router.feed = null
	if Director.instance != null:
		Director.instance.enabled = false
	if PopulationManager.instance != null:
		PopulationManager.instance.enabled = false
	await tree.create_timer(1.3).timeout
	var t0 := Time.get_ticks_msec()
	match preset:
		"zone_card", "zone_card_t05", "zone_card_t46":
			WorldState.instance.set_time(1, 22.5)
			world.cabin.stove.burner.add_fuel(600.0)
			inv.add(&"madera", 4)
			var p := player.global_position + Vector3(-2.2, 0, 2.0)
			p.y = world.get_height(p.x, p.z)
			world.spawn_placed("campfire", p, 0.0)
			await _settle(hud)
			var at := 1.8
			if preset == "zone_card_t05":
				at = 0.5
			elif preset == "zone_card_t46":
				at = 4.6
			var e := Locations.by_id("altavega_las_torres")
			hud.zones.forget_all()
			var info := hud.zones.info_for(e, true, "full")
			hud.zone_title.show_card(info, at)
			print("h2_shots: %s card «%s» · %s at t = %.1f s" % [preset, info["name"], " · ".join(info["facts"]), at])
		"zone_sign_vehicle":
			WorldState.instance.set_time(1, 11.0)
			inv.add(&"hacha", 1)
			var end := Vector3(4096.0, 0.0, -760.0)
			AdminCommands.teleport_player(player, end.x - 5.0, end.z)   # not the chat command: no chat line in the picture
			await tree.process_frame
			await _settle(hud)
			# the scripted fast mover: 25 m/s southbound on the A‑14 for 10 s, 0.25 s steps
			var zt := hud.zones
			zt.forget_all()
			var cards: Array = []
			zt.card_shown.connect(func(i: Dictionary) -> void: cards.append(i))
			var from := Vector3(4096.0, 0.0, -1010.0)
			for i in 41:
				zt.clock += 0.25
				zt.step(from.lerp(end, float(i) / 40.0), 0.25)
			var s: Dictionary = cards[-1] if not cards.is_empty() else {}
			if s.is_empty() or str(s.get("card", "")) != "sign":
				print("FAIL: no highway sign for the fast mover (%s)" % [s])
			else:
				hud.zone_title.t = -1.0
				hud.zone_title.visible = false
				hud.zone_sign.show_sign(s, 1.1)
				print("h2_shots: sign %s at %.0f km/h" % [s.get("sign", {}), zt.speed * 3.6])
			var h := world.get_height(end.x, end.z)
			player.global_position = Vector3(end.x - 5.0, h + 0.1, end.z)
	var rig := CameraRig.active()
	if rig != null:
		rig.snap_to_player()
	hud.world_layer._cursor_text = ""
	await tree.process_frame
	Engine.time_scale = 0.0
	hud.vis.settle()
	print("h2_shots: %s ready (%d ms, frame %d)" % [preset, Time.get_ticks_msec() - t0, Engine.get_process_frames()])


## Lets the opening transients go and puts the HUD at rest; the tracker stops (the preset drives it).
func _settle(hud: Hud) -> void:
	hud.zones.enabled = false
	for i in 10:
		await tree.process_frame
	hud.settle_to_rest()
	await tree.process_frame
	hud.settle_to_rest()
	hud.feed.lines.clear()
