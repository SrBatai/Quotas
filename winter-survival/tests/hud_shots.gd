extends RefCounted
## HUD v2 «Susurro» screenshot presets (H1), called by tests/screenshot_steps.gd for presets named hud_*:
##   hud_idle      day, exploring, nothing happening: only the folded hotbar strip (compare mockup v2_a)
##   hud_action    a fight at dusk away from the cabin: health after a bite (ring + word), the damage arc toward
##                 the biter, the stamina arc, the unfolded hotbar with the bat's name, "objetivo actualizado" and
##                 the one edge marker toward the refuge (compare v2_b)
##   hud_zone      the cinematic zone title of the clearing at night, frame 2 (t = 1.8 s) (compare v2_c)
##   hud_blizzard  night blizzard: frost vignette (Calor 14), "te estás congelando", the hazard line and the
##                 amber accent on the nearest refuge (compare v2_d)
##   hud_info      Info held: missions on demand, time / temperature (compare v2_f)
##   hud_map       P1: the paper map with the fog of war after a walk (zoom 1 km); hud_journal: the journal
##   hud_downed_coop  (H3; also `downed_coop`) a teammate down 6 m away at dusk by the porch, walkers around: the ONE
##                 indicator in the accent — ground ring, the bleed-out ring with the skull, «Ana 38 s», «mantén ⓧ
##                 para reanimar · 6 m» — and nothing else but the strip (compare v2_e); hud_downed_coop_cue: the
##                 same 0.8 s after the down, with the sound caption «latido y estática de radio · Ana → 6 m»
## Run: RENDER=forward tests/run_screenshots.sh <dir> hud_idle   (1920 × 1080 for hud_* presets)

var tree: SceneTree


func setup(p_tree: SceneTree, preset: String, game: Node, world: World, player: Player, inv: InventoryComponent) -> void:
	tree = p_tree
	var hud: Hud = game.get("hud")
	if hud == null:
		print("FAIL: no HUD")
		return
	UiSettings.get_instance().reset()   # default HUD (Mínimo) whatever this machine saved
	world.get_node("WolfSpawner").enabled = false
	hud.router.feed = null   # the kit each preset hands out is not a pickup: no side-stack lines in the pictures
	if Director.instance != null:
		Director.instance.enabled = false
	if PopulationManager.instance != null:
		PopulationManager.instance.enabled = false
	# the opening notice arrives 1 s after the spawn: let it come and go through the router
	var t0 := Time.get_ticks_msec()
	await tree.create_timer(1.3).timeout
	print("hud_shots: %s setup (%d ms, frame %d)" % [preset, Time.get_ticks_msec() - t0, Engine.get_process_frames()])
	match preset:
		"hud_idle":
			WorldState.instance.set_time(1, 11.0)
			inv.add(&"hacha", 1)
			inv.add(&"madera", 3)
			await _settle(hud)
		"hud_action":
			await _action(hud, world, player, inv)
		"hud_zone":
			WorldState.instance.set_time(1, 22.5)
			world.cabin.stove.burner.add_fuel(600.0)
			inv.add(&"madera", 4)
			var p := player.global_position + Vector3(-2.2, 0, 2.0)
			p.y = world.get_height(p.x, p.z)
			world.spawn_placed("campfire", p, 0.0)
			await _settle(hud)
			var e := Locations.by_id("claro_del_cazador")
			hud.zones.forget_all()
			hud.zone_title.show_card(hud.zones.info_for(e, true, "full"), 1.8)
			await tree.process_frame
			Engine.time_scale = 0.0
		"hud_blizzard":
			WorldState.instance.set_time(1, 21.5)
			world.cabin.stove.burner.add_fuel(600.0)
			inv.add(&"madera", 2)
			var weather: Weather = world.get_node("Weather")
			weather.force_blizzard(160.0)
			world.get_node("DayNight").blizzard_blend = 1.0
			# outside, a few metres in front of the porch, freezing
			var down := Vector3(0.7071, 0.0, 0.7071)
			var c := world.cabin.global_position + down * 7.5 + Vector3(-1.5, 0, 1.5)
			c.y = world.get_height(c.x, c.z)
			player.global_position = c + Vector3(0, 0.2, 0)
			await _settle(hud)
			# Calor falls from 20 to 14 (the trend arrow), the blizzard line was just updated
			for i in 45:
				await tree.process_frame
				player.state.warmth = 20.0 - 6.0 * float(i) / 44.0
				player.state.mark(&"stats")
			hud.vis.poke(HazardLine.EL)
			hud.vis.settle()
			Engine.time_scale = 0.0
		"hud_map", "hud_journal":
			WorldState.instance.set_time(1, 15.3)
			inv.add(&"hacha", 1)
			await _settle(hud)
			# the fog as after a walk: a loop around the clearing and down the road bed to the lake
			var fog: MapFog = hud.map_screen.fog
			fog.clear_all()
			for i in 64:
				var a := TAU * float(i) / 64.0
				fog.reveal(cos(a) * 140.0, sin(a) * 110.0, 60.0)
			for i in 40:
				fog.reveal(lerpf(0.0, -620.0, float(i) / 39.0), lerpf(0.0, 330.0, float(i) / 39.0), 50.0)
			fog.texture.update(fog.image)
			hud.zones.discovered["claro_del_cazador"] = true
			hud.map_screen.open_map(&"journal" if preset == "hud_journal" else &"map")
			hud.map_screen.zoom = 1
			for i in 4:
				await tree.process_frame
		"hud_downed_coop", "hud_downed_coop_cue", "downed_coop":
			await downed_coop(hud, world, player, inv, preset == "hud_downed_coop_cue")
		"hud_info":
			WorldState.instance.set_time(1, 15.3)
			inv.add(&"hacha", 1)
			player.state.emit_sim(&"item_picked_up", [&"madera", 2])
			await _settle(hud)
			hud.input.set_info(true)
			for i in 20:
				await tree.process_frame
			hud.vis.settle()
	var rig := CameraRig.active()
	if rig != null:
		rig.snap_to_player()
	if preset != "hud_action" and not preset.contains("downed_coop"):
		# no mouse in the picture: its context label would float with no cursor
		hud.world_layer._cursor_text = ""
		Engine.time_scale = 0.0
		hud.vis.settle()
	print("hud_shots: %s ready (%d ms, frame %d)" % [preset, Time.get_ticks_msec() - t0, Engine.get_process_frames()])
	for i in 4:
		await tree.process_frame
	hud.feed.lines.clear()
	var tt: Dictionary = hud.mlog.tracked_target(player.global_position)
	print("hud_shots: %s accent %s / %s, tracked step '%s' target %s" % [preset, hud.accent.accent.get("kind", "-"), hud.accent.accent.get("pos", "-"),
		Missions.current_step(hud.mlog.tracked()).get("title", "-"), tt.get("pos", "-")])
	print("hud_shots: %s after 4 frames: mission a %.2f, feed %d, time_scale %.1f" % [preset, hud.vis.alpha_of(MissionLine.EL), hud.feed.lines.size(), Engine.time_scale])


## Lets the opening transients go (zone card, first mission line, banners) and puts the HUD at rest.
func _settle(hud: Hud) -> void:
	hud.zones.enabled = false
	for i in 10:
		await tree.process_frame
	hud.settle_to_rest()
	await tree.process_frame
	hud.settle_to_rest()
	hud.feed.lines.clear()   # the preset's own kit is not a pickup


func _action(hud: Hud, world: World, player: Player, inv: InventoryComponent) -> void:
	WorldState.instance.set_time(1, 18.4)
	world.cabin.stove.burner.add_fuel(600.0)
	var sys := ZombieSystem.instance
	sys.clear_all()
	inv.add(&"bate_clavos", 1)
	inv.add(&"carne_cruda", 4)
	inv.add(&"lata_judias", 1)
	inv.add(&"antorcha", 1)
	inv.add(&"cuchillo", 1)
	await tree.process_frame
	for i in range(1, player.state.slots.size()):
		if not player.state.slots[i].is_empty() and player.state.slots[i]["id"] == &"bate_clavos":
			Net.rpc_server(NetWorld.instance, &"request_use_slot", [i])
			break
	# the bat is worn out (12 %): its name stays on the bar in `warn`
	await tree.process_frame
	if not player.state.slots[0].is_empty():
		player.state.slots[0]["dur"] = 12
		player.state.mark(&"slots")
	# 34 m south-east of the cabin: the refuge (stove) is off screen → the one edge marker
	var right := Vector3(0.7071, 0.0, -0.7071)
	var down := Vector3(0.7071, 0.0, 0.7071)
	var c := world.cabin.global_position + down * 30.0 + right * 16.0
	c.y = world.get_height(c.x, c.z)
	player.global_position = c + Vector3(0, 0.2, 0)
	await tree.physics_frame
	await _settle(hud)
	var at := func(r: float, d: float) -> Vector3:
		var p := c + right * r + down * d
		p.y = world.get_height(p.x, p.z)
		return p
	var ids: Array[int] = []
	for g in [[-1.7, -0.6], [2.0, 1.2], [-3.2, 2.6], [3.4, -2.4], [0.4, 3.6], [-5.0, -3.4]]:
		var p: Vector3 = at.call(float(g[0]), float(g[1]))
		var dv := c - p
		var i := sys.spawn(ZombieKinds.Kind.WALKER, p, atan2(dv.x, dv.z), ZombieKinds.State.CHASE, -1, -2)
		if i >= 0:
			sys.target[i] = player.peer_id
			sys.mem_t[i] = sys._now()
			sys.last_seen[i] = c
			ids.append(i)
	var pf := Engine.get_physics_frames()
	while Engine.get_physics_frames() - pf < 40:
		await tree.process_frame
		player.state.health = maxf(player.state.health, 60.0)
		player.state.stamina = 36.0
	hud.feed.lines.clear()   # the kit given above is not part of the picture
	# the walkers stop where they are (no more bites while the frame is composed)
	sys.set_physics_process(false)
	# step 1 done (wood picked up) → "objetivo actualizado: Entra en casa y alimenta la estufa" + edge marker
	player.state.emit_sim(&"item_picked_up", [&"madera", 2])
	inv.add(&"madera", 3)   # (the next step is the stove: this wood does not count)
	await tree.process_frame
	var zc := ZombieClient.instance
	var tgt := ids[1] if ids.size() > 1 else -1
	var zr: ZombieClient.ZRec = zc.record(sys.net_id[tgt]) if zc != null and tgt >= 0 else null
	var aim: Vector3 = zr.render_pos if zr != null else c + right * 1.5
	# the mouse rests on the walker being hit (its label replaces the scenery's)
	var cam := tree.root.get_camera_3d()
	if cam != null:
		Input.warp_mouse(cam.unproject_position(aim + Vector3(0, 1.0, 0)) * tree.root.get_final_transform().get_scale())
	player.interactor.send_melee(Weapons.Mode.LIGHT, aim, zr.id if zr != null else 0)
	hud.hotbar.poke(true)
	pf = Engine.get_physics_frames()
	var contact := int(ceil((AnimEvents.at("Melee2H_Swing_A", "hit_start", 0.36) + 0.04) * 60.0))
	while Engine.get_physics_frames() - pf < contact:
		await tree.process_frame
		player.state.stamina = 36.0
	# a bite from the nearest walker at the contact frame (health 58 → 42): the damage arc points at it
	player.state.health = 58.0
	player.stats.take_damage(16.0, &"zombi")
	Engine.time_scale = 0.0
	player.state.mark(&"stats")
	player.state.flush_mirror()   # the owner mirror goes out now (the frozen clock runs no more server ticks)
	hud.vitals._update(0.1)
	hud.feed.lines.clear()
	hud.vis.settle()
	print("hud_action: health %.0f, mission '%s' (a %.2f vis %s), feed %d, accent %s, edge %s" % [player.state.health, hud.mission_line.objective,
		hud.vis.alpha_of(MissionLine.EL), hud.mission_line.visible, hud.feed.lines.size(), hud.accent.accent.get("kind", "-"), hud.world_layer.last_edge])


## H3 (mockup v2_e): a teammate — a puppet player of the in-process server, peer 2 «Ana» — down 6 m from the survivor,
## in front of the porch at dusk, walkers standing around. The P0 is the one world indicator (accent), the rest is
## sound (no banner, no frame). `cue`: 0.8 s after the down, the caption still on screen.
func downed_coop(hud: Hud, world: World, player: Player, inv: InventoryComponent, cue: bool) -> void:
	WorldState.instance.set_time(1, 19.35)
	world.cabin.stove.burner.add_fuel(600.0)
	inv.add(&"bate", 1)
	inv.add(&"madera", 3)
	var sys := ZombieSystem.instance
	sys.clear_all()
	var right := Vector3(0.7071, 0.0, -0.7071)
	var down := Vector3(0.7071, 0.0, 0.7071)
	var c := coop_spot(world, right, down)
	player.global_position = c + Vector3(0, 0.2, 0)
	await tree.physics_frame
	await _settle(hud)
	var at := func(r: float, d: float) -> Vector3:
		var p := c + right * r + down * d
		p.y = world.get_height(p.x, p.z)
		return p
	# Ana, 6 m to the lower right (as in the mockup)
	var mate: Player = PlayerManager.instance.spawn_player(2, "Ana", "shot-ana")
	await tree.process_frame
	var ap: Vector3 = at.call(3.6, 4.8)
	mate.global_position = ap + Vector3(0, 0.1, 0)
	mate.net_position = mate.global_position
	for g in [[-5.4, -2.6], [-3.2, -5.0], [5.6, -3.8], [-6.4, 3.6], [7.8, 4.8], [-2.2, 3.4]]:
		var p: Vector3 = at.call(float(g[0]), float(g[1]))
		var dv := ap - p
		sys.spawn(ZombieKinds.Kind.WALKER, p, atan2(dv.x, dv.z), ZombieKinds.State.IDLE, -1, -2)
	for i in 8:
		await tree.process_frame
	sys.set_physics_process(false)   # the walkers hold their pose (and never bite: no arc, no vital in the picture)
	player.state.health = Balance.HEALTH_MAX
	player.state.mark(&"stats")
	HudInput.gamepad = true          # «mantén ⓧ para reanimar» with the pad glyph, like the mockup
	hud.captions.clear()
	# the jump to dusk moved the feels-like temperature: take it as the new reference (no «sentida» poke later)
	hud.vitals._update(0.1)
	hud.info_block.set("_feels_ref", INF)
	hud.vitals.set("_feels_ref", INF)
	hud.info_block._process(0.0)
	hud.vitals._update(0.1)
	hud.vis.clear_all()
	mate.stats.go_down()
	mate.stats.set("_bleed_left", 38.4)
	mate.bleed = 39
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < (800 if cue else 1300):
		await tree.process_frame
		player.state.warmth = 90.0   # steady Calor: its vital stays hidden (the mockup shows none)
		player.state.mark(&"stats")
	mate.bleed = 38
	hud.feed.lines.clear()
	hud.vis.clear_all()   # the preset's own kit and health resets poke nothing into the picture
	hud.world_layer._hits.clear()
	if not cue:
		hud.captions.clear()   # the mockup is the moment after the cue: the indicator alone
	hud.accent.update()
	var rig := CameraRig.active()
	if rig != null:
		rig.snap_to_player()
	hud.world_layer._cursor_text = ""
	Engine.time_scale = 0.0
	hud.vis.settle()
	print("hud_downed_coop: Ana downed at %.1f m, bleed %d s, accent %s, P0 %s, captions %s" % [Vector2(ap.x - c.x, ap.z - c.z).length(), mate.bleed,
		hud.accent.accent.get("kind", "-"), hud.router.p0.keys(), hud.captions.history])


## The survivor's spot for the downed_coop moment: in front of the porch (like mockup v2_e), with no interactable
## within 3.2 m (no prompt in the picture) and no scatter (pines, rocks, logs) within 4 m of the survivor, of Ana
## (3.6 m right, 4.8 m down the screen) or of the ground toward the camera from both (a pine there hides them).
static func coop_spot(world: World, right: Vector3, down: Vector3) -> Vector3:
	var base := world.cabin.global_position + down * 9.5 + right * 1.5
	var nodes := world.get_tree().get_nodes_in_group("interactable")
	var scatter: Array = ScatterGen.clearing_entries(world.seed_value)
	var best := base
	var best_score := INF
	for dd in range(0, 9):
		for rr in range(-6, 7):
			var p := base + right * float(rr) + down * float(dd) * 0.8
			var near_prompt := false
			for n in nodes:
				if n is Node3D and Vector2((n as Node3D).global_position.x - p.x, (n as Node3D).global_position.z - p.z).length() < 3.2:
					near_prompt = true
					break
			if near_prompt:
				continue
			var ana := p + right * 3.6 + down * 4.8
			var probes := [p, ana, p + down * 3.5, ana + down * 3.5, p + down * 6.0, ana + down * 6.0]
			var clash := 0
			for e: Dictionary in scatter:
				var q := Vector2(float(e["x"]), float(e["z"]))
				for pr: Vector3 in probes:
					if q.distance_to(Vector2(pr.x, pr.z)) < 4.0:
						clash += 1
			var score := float(clash) * 100.0 + p.distance_to(base)
			if score < best_score:
				best_score = score
				best = p
	best.y = world.get_height(best.x, best.z)
	return best
