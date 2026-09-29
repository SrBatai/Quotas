extends RefCounted
## H3 part of the smoke test (step 21, after the audio steps): notices, hazards and the group in the running game.
##   · a SIMULATED P0: a teammate (a puppet player spawned by the in-process server, peer 2 «Ana») goes down 5 m away
##     → HudNet pushes it, the TeamTracker notices it the same frame, the router raises the P0 in the world (no
##     central banner): the one downed indicator (+ the accent), `ui_mate_down` with its caption «… · Ana ·
##     <dirección>, 8 m», the heartbeat under it and the radio static 10 s later; revived → all of it ends
##   · the replicated team block (health) → «herido» below 25 %
##   · directional damage: a bite from a walker to the east and a shot from the west → player_hit_from toward each
##   · a forced blizzard with its 60 s warning: «ventisca · se acerca · 1:00», the countdown, then «visibilidad 6 m ·
##     1:30» when it starts and icon + time after 5 s; thin ice underfoot → a P0 «!» at the feet
##   · pings through the server (danger / place, rate limit, range), drawn in the world, with their positioned sound
##   · the M5 hooks: the reticle by band and the ammo on the hotbar line
## No SCRIPT ERROR on the way (run_smoke.sh greps them).

var s: RefCounted   # tests/smoke_steps.gd (check / frames / seconds)
var tree: SceneTree
var hud: Hud
var played: Array = []   # [event, at, ticks ms]


func run(p_smoke: RefCounted, p_tree: SceneTree, game: Node, world: World, player: Player) -> void:
	s = p_smoke
	tree = p_tree
	print("-- H3: notices, hazards and the group (simulated P0, blizzard warning, pings, hit direction)")
	hud = game.get("hud")
	var hn := HudNet.instance
	s.check(hud != null and hn != null and game.get_node_or_null("HudNet") == hn and hud.captions != null and hud.pings != null
		and hud.hit_dir != null and hud.ui_audio != null and hud.hazard.stack != null,
		"H3 nodes: /root/Game/HudNet, captions, pings, hit direction, UI audio, the hazard stack")
	if hud == null or hn == null:
		return
	var cb := func(e: StringName, _v: Node, at: Vector3) -> void: played.append([e, at, Time.get_ticks_msec()])
	AudioManager.event_played.connect(cb)
	# a quiet valley at noon, the player home and well
	if Director.instance != null:
		Director.instance.enabled = false
	if PopulationManager.instance != null:
		PopulationManager.instance.enabled = false
	if ZombieSystem.instance != null:
		ZombieSystem.instance.clear_all()
	world.get_node("WolfSpawner").enabled = false
	var weather: Weather = world.get_node("Weather")
	weather.scheduler_enabled = false
	weather.cancel()
	WorldState.instance.set_time(WorldState.instance.day, 11.0)
	if player.dead:
		GameFlow.request_respawn()
		await s.frames(5)
	player.state.health = Balance.HEALTH_MAX
	player.state.warmth = 90.0
	player.state.mark(&"stats")
	UiSettings.get_instance().reset()
	hud.settle_to_rest()
	await s.frames(3)
	s.check(hn.synced and hn._synced.has(1), "HudNet synced on spawn (offline: the in-process server)")
	await _p0_teammate(world, player)
	await _hit_direction(world, player)
	await _blizzard(weather, player)
	await _pings(player)
	await _m5_hooks(player)
	AudioManager.event_played.disconnect(cb)
	AudioManager.heartbeat(0.0)
	hud.hazard.stack.clear_all()
	hud.settle_to_rest()


# ------------------------------------------------------------------ the simulated P0: a teammate down
func _p0_teammate(world: World, player: Player) -> void:
	var pm := PlayerManager.instance
	var mate: Player = pm.spawn_player(2, "Ana", "h3-smoke-ana") if pm != null else null
	await s.frames(4)
	if mate == null:
		s.check(false, "puppet teammate spawned")
		return
	var cam := tree.root.get_camera_3d()
	var right := cam.global_basis.x if cam != null else Vector3.RIGHT
	right.y = 0.0
	right = right.normalized()
	# 5 m: on screen even in the square headless viewport (1280 × 1280: ±7.8 m across at 24 m)
	var at := player.global_position + right * 5.0
	at.y = world.get_height(at.x, at.z) + 0.1
	mate.global_position = at
	mate.net_position = at
	await s.frames(8)
	var tt := hud.team
	tt.refresh()
	var m0: Dictionary = tt.mates[0] if not tt.mates.is_empty() else {}
	s.check(str(m0.get("name", "")) == "Ana" and absf(float(m0.get("dist", 0.0)) - 5.0) < 1.0 and not bool(m0.get("downed", true)),
		"a teammate 5 m to the right (puppet peer 2 of the in-process server): %s" % [m0.get("name", "-")])
	# replicated health (HudNet team block, 2 Hz): healthy → not hurt; 20 → «herido»
	mate.state.health = 20.0
	await _until(func() -> bool: return float((hn_team().get(2, {}) as Dictionary).get("health", -1.0)) == 20.0, 2.0)
	tt.refresh()
	var hurt := bool((tt.mates[0] as Dictionary).get("hurt", false)) if not tt.mates.is_empty() else false
	s.check(float((hn_team().get(2, {}) as Dictionary).get("health", -1.0)) == 20.0 and hurt, "replicated team block: Ana's health 20 reaches the HUD → «herido» (< 25 %)")
	mate.state.health = Balance.HEALTH_MAX
	# DOWN: the server's stats go down → the P0
	played.clear()
	hud.captions.clear()
	var t0 := Time.get_ticks_msec()
	mate.stats.go_down()
	var both := func() -> bool:
		var cue := not played.filter(func(p: Array) -> bool: return p[0] == &"ui_mate_down").is_empty()
		return hud.world_layer.downed_seen.has(2) and tt.downed_at.has(2) and cue
	var seen := await _until(both, 2.0)
	var t_ind := int(hud.world_layer.downed_seen.get(2, 0)) - t0
	var snd: Array = played.filter(func(p: Array) -> bool: return p[0] == &"ui_mate_down")
	var t_snd := int(snd[0][2]) - t0 if not snd.is_empty() else -1
	s.check(seen and t_ind <= 200 and t_snd >= 0 and t_snd <= 200, "P0 teammate down → the indicator in %d ms and ui_mate_down in %d ms (≤ 200 ms)" % [t_ind, t_snd])
	await s.frames(2)
	hud.accent.update()
	var p0: Dictionary = hud.router.p0.get("mate_down:2", {})
	s.check(not p0.is_empty() and p0["target"] == &"world" and hud.router.p0_active() and hud.p0_active()
		and not hud.banner.text_now().contains("Ana") and hud.accent.accent.get("kind", &"") == &"downed",
		"the P0 lives in the world (target %s, accent %s), never on the central line («%s»)" % [p0.get("target", "-"), hud.accent.accent.get("kind", "-"), hud.banner.text_now()])
	var cap: Dictionary = hud.captions.lines[-1] if not hud.captions.lines.is_empty() else {}
	var ctext := hud.captions.text_of(cap) if not cap.is_empty() else "-"
	s.check(ctext.begins_with("latido y estática de radio · Ana · ") and ctext.contains("derecha") and ctext.ends_with("5 m"),
		"sound caption with direction: «%s»" % ctext)
	await s.frames(3)
	s.check(is_equal_approx(hud.ui_audio.intensity, UiTokens.HEARTBEAT_MATE) and is_equal_approx(AudioManager.heartbeat_intensity(), UiTokens.HEARTBEAT_MATE),
		"heartbeat under it while Ana bleeds out (%.2f)" % AudioManager.heartbeat_intensity())
	var statics := hud.ui_audio.statics
	hud.ui_audio._process(UiTokens.MATE_DOWN_REPEAT + 0.1)
	s.check(hud.ui_audio.statics == statics + 1 and not played.filter(func(p: Array) -> bool: return p[0] == &"ui_radio_static").is_empty(),
		"radio static every 10 s while she is down (captioned toward her)")
	# the one indicator: on screen → drawn in the world (ring, skull, «Ana 38 s», «mantén … para reanimar · 8 m»)
	var drawn := hud.world_layer.downed_drawn
	hud.world_layer.queue_redraw()
	await s.frames(2)
	s.check(hud.world_layer.downed_drawn > drawn, "the one downed indicator is drawn in the world, not on the edge (%d draws)" % hud.world_layer.downed_drawn)
	# revived → the P0 ends, the heartbeat stops
	mate.stats.revive(null)
	await _until(func() -> bool: return not hud.router.p0.has("mate_down:2"), 2.0)
	await s.frames(3)
	s.check(not hud.router.p0.has("mate_down:2") and not hud.world_layer.downed_seen.has(2) and hud.ui_audio.intensity == 0.0,
		"revived: the P0, the indicator and the heartbeat end")
	mate.queue_free()
	await s.frames(3)
	hud.team.refresh()


func hn_team() -> Dictionary:
	return HudNet.instance.team if HudNet.instance != null else {}


# ------------------------------------------------------------------ directional damage
func _hit_direction(world: World, player: Player) -> void:
	var sys := ZombieSystem.instance
	var cam := tree.root.get_camera_3d()
	var right := cam.global_basis.x if cam != null else Vector3.RIGHT
	right.y = 0.0
	right = right.normalized()
	var me := player.global_position
	var zp := me + right * 1.6
	zp.y = world.get_height(zp.x, zp.z)
	var i := sys.spawn(ZombieKinds.Kind.WALKER, zp, 0.0, ZombieKinds.State.CHASE, -1, -2)
	await _until(func() -> bool: return ZombieClient.instance != null and ZombieClient.instance.nearest_to(me, 4.0) != null, 2.0)
	var n0 := hud.hit_dir.emitted
	var got: Array = []
	var cb := func(dir: Vector3, amount: float) -> void: got.append([dir, amount])
	Events.player_hit_from.connect(cb)
	player.stats.take_damage(4.0, &"zombi")
	await s.frames(3)
	var d1: Vector3 = got[0][0] if not got.is_empty() else Vector3.ZERO
	s.check(hud.hit_dir.emitted > n0 and d1.dot(right) > 0.8 and hud.world_layer._hits.size() >= 1,
		"a bite from the walker to the right → player_hit_from toward it (dot %.2f, via %s) and the arc on the ground" % [d1.dot(right), hud.hit_dir.last.get("via", "-")])
	sys.clear_all()
	await s.frames(3)
	# a shot from the west (another player's line passes through the survivor)
	got.clear()
	var origin := player.global_position - right * 20.0 + Vector3(0, 1.2, 0)
	var end := player.global_position + right * 5.0 + Vector3(0, 1.0, 0)
	Events.shot_fired.emit(9, &"pistola", origin, PackedVector3Array([end]), 0)
	await s.frames(4)   # the offline dedupe window (0.06 s) is long past after these frames
	player.stats.take_damage(4.0, &"jugador")
	await s.frames(3)
	var d2: Vector3 = got[0][0] if not got.is_empty() else Vector3.ZERO
	s.check(d2.dot(-right) > 0.8 and hud.hit_dir.last.get("via", &"") == &"shot", "a shot from the left → toward the shooter (dot %.2f, via %s)" % [d2.dot(-right), hud.hit_dir.last.get("via", "-")])
	Events.player_hit_from.disconnect(cb)
	player.state.health = Balance.HEALTH_MAX
	player.state.mark(&"stats")


# ------------------------------------------------------------------ forced blizzard: warning 60 s before
func _blizzard(weather: Weather, player: Player) -> void:
	var hz := hud.hazard
	hz.stack.clear_all()
	hz.raised.clear()
	HudNet.instance.request_test_warning(90.0)
	await s.frames(3)
	var soon := " · ".join(hz.line_parts())
	s.check(Balance.BLIZZARD_WARNING == 60.0 and hz.stack.state_of(&"blizzard") == &"soon" and soon == "ventisca · se acerca · 1:00"
		and hz.raised.has([&"blizzard", &"soon", &"ui_warn"]) and hud.vis.is_on(HazardLine.EL),
		"forced blizzard: warning 60 s before → «%s» with ui_warn" % soon)
	# the countdown (the HUD's clock), then the server starts it 60 s later (Weather fast-forwarded)
	for k in 20:
		hz._process(0.5)
	var ten := " · ".join(hz.line_parts())
	# the server's Weather counts its own 60 s: run it to the end of the warning, then one short step starts it
	weather._process(float(weather.get("_warning_left")) - 0.05)
	weather._process(0.1)
	await s.frames(3)
	var act := " · ".join(hz.line_parts())
	s.check(ten == "ventisca · se acerca · 0:50" and WorldState.weather_now() == &"blizzard" and act == "ventisca · visibilidad 6 m · 1:30"
		and hz.raised.has([&"blizzard", &"active", &"ui_hazard"]), "countdown «%s» → the blizzard starts: «%s» with ui_hazard" % [ten, act])
	for k in 12:
		hz._process(0.5)
		hud.vis._process(0.5)
	s.check(hz.visible and hud.vis.alpha_of(HazardLine.EL) < 0.01 and hz.shown_alpha > 0.99, "after 5 s: icon + time (%s)" % UiTokens.countdown(hz.stack.left(&"blizzard")))
	weather.cancel()
	await s.frames(3)
	s.check(hz.stack.state_of(&"blizzard") == &"end" or not hz.stack.has(&"blizzard"), "the sky clears → the line ends")
	# thin ice underfoot (the E1 API): a P0 «!» in the world at the feet, with its caption
	var drawn := hud.world_layer.p0_drawn
	Events.hazard_changed.emit(&"thin_ice", &"active", {"pos": player.global_position})
	hud.world_layer.queue_redraw()
	await s.frames(2)
	s.check(hud.router.p0.has("hazard:thin_ice") and hud.world_layer.p0_drawn > drawn and hud.p0_active(),
		"thin ice underfoot → P0 in the world at the feet («%s»)" % str(hud.router.p0.get("hazard:thin_ice", {}).get("body", "-")))
	Events.hazard_changed.emit(&"thin_ice", &"end", {})
	s.check(not hud.router.p0.has("hazard:thin_ice"), "off the ice → the P0 ends")
	hz.stack.clear_all()


# ------------------------------------------------------------------ pings
func _pings(player: Player) -> void:
	var pg := hud.pings
	var hn := HudNet.instance
	pg.clear()
	await tree.create_timer(2.1).timeout   # a fresh rate-limit window
	played.clear()
	var cam := tree.root.get_camera_3d()
	var fwd := -cam.global_basis.z if cam != null else Vector3.FORWARD
	fwd.y = 0.0
	var at := player.global_position + fwd.normalized() * 6.0
	pg.place(&"danger", at)
	await s.frames(3)
	var g: Dictionary = pg.live[-1] if not pg.live.is_empty() else {}
	var snd := played.filter(func(p: Array) -> bool: return p[0] == &"ui_ping_danger")
	s.check(not g.is_empty() and g["kind"] == &"danger" and int(g["peer"]) == 1 and absf(float(g["seconds"]) - UiTokens.PING_DANGER_SECONDS) < 0.01
		and not snd.is_empty() and (snd[0][1] as Vector3).distance_to(at) < 0.01, "danger ping through the server: 8 s, ui_ping_danger at the ping")
	hud.world_layer.queue_redraw()
	await s.frames(2)
	s.check(hud.world_layer.pings_drawn.has(int(g.get("id", -1))), "the ping is drawn in the world (▲ + countdown ring)")
	pg.place(&"place", at + fwd * 2.0)
	pg.place(&"place", at + fwd * 3.0)
	pg.place(&"place", at + fwd * 4.0)   # the 4th inside 2 s: refused
	var rej := hn.pings_rejected
	pg.place(&"place", player.global_position + Vector3(900, 0, 0))   # out of range (and over the rate)
	await s.frames(3)
	s.check(hn.pings_rejected >= rej + 1 and pg.live.size() == 3, "3 pings per player (the oldest goes), rate-limited and range-checked (%d live, %d refused)" % [pg.live.size(), hn.pings_rejected])
	# an own ping makes no line; a teammate's danger ping would be P2 (the net scenario `team` covers it)
	s.check(not hud.banner.text_now().contains("peligro"), "own pings raise no line")
	pg.clear()


# ------------------------------------------------------------------ M5 hooks: reticle and ammo
func _m5_hooks(player: Player) -> void:
	var game := tree.current_scene
	var ret: ReticleHook = game.get_node_or_null("UI/ReticleHook")
	var hb := hud.hotbar
	# a pistol in hand
	player.state.inventory.add(&"pistola", 1, true)
	await s.frames(3)
	for i in range(1, player.state.slots.size()):
		if not player.state.slots[i].is_empty() and player.state.slots[i]["id"] == &"pistola":
			Net.rpc_server(NetWorld.instance, &"request_use_slot", [i])
			break
	await s.frames(4)
	# the real FirearmClient drives the reticle at 30 Hz while the pistol is in hand: the ring takes its band's colour
	var bands: Array = []
	var rc := func(sp: float, b: StringName, _a: Vector3, _r: float) -> void:
		if sp >= 0.0:
			bands.append(b)
	Events.reticle_changed.connect(rc)
	await s.frames(6)
	Events.reticle_changed.disconnect(rc)
	var last_band: StringName = bands[-1] if not bands.is_empty() else &""
	s.check(ret != null and ret.visible and not bands.is_empty() and ret.drawn_color == ret.color_of(last_band) and ret.drawn_radius > 5.0,
		"reticle while the pistol is in hand: band %s → its colour, ring %.0f px" % [last_band, ret.drawn_radius if ret != null else -1.0])
	s.check(ret != null and ret.color_of(&"green") == UiTokens.RETICLE_GREEN and ret.color_of(&"amber") == UiTokens.RETICLE_AMBER
		and ret.color_of(&"red") == UiTokens.RETICLE_RED and ret.color_of(&"grey") == UiTokens.RETICLE_GREY, "spread bands: green < 4°, amber 4–8°, red > 8°, grey = ally in the line")
	Events.weapon_state_changed.emit({"w": "pistola", "ammo": 3, "mag": 15, "reserve": 20, "jammed": false, "reload_left": -1.0, "reload_total": 0.0})
	var low := hb.ammo_text == "3/15 · 20" and hb._hand_is_gun() and hud.vis.is_on(Hotbar.EL_AMMO) and hb._ammo_low()
	Events.weapon_state_changed.emit({"w": "pistola", "ammo": 3, "mag": 15, "reserve": 20, "jammed": true, "reload_left": -1.0, "reload_total": 0.0})
	var jam := hb.ammo_text == "encasquillada"
	Events.weapon_state_changed.emit({"w": "pistola", "ammo": 0, "mag": 15, "reserve": 20, "jammed": false, "reload_left": 1.2, "reload_total": 2.0})
	s.check(low and jam and hb.ammo_text == "recargando", "ammo on the hotbar line: «3/15 · 20» (low: held), «encasquillada», «recargando»")
	Events.reticle_changed.emit(-1.0, &"green", Vector3.ZERO, 0.0)
	s.check(ret != null and not ret.visible, "spread < 0 (no firearm) → no reticle")


func check_line(cond: bool, msg: String) -> void:
	s.check(cond, msg)


## Waits (real time, ≤ `limit` s) until `cond` holds; true when it did.
func _until(cond: Callable, limit: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()):
		if Time.get_ticks_msec() - t0 > int(limit * 1000.0):
			return false
		await tree.process_frame
	return true
