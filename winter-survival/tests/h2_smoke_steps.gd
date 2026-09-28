extends RefCounted
## H2 part of the smoke test (step 19, called by tests/smoke_steps.gd after the HUD checks): the HUD's ZoneTracker
## enters two real zones of the valley after a /tp (12 m / 1.5 s at the player's position), the title shows (the
## second one waits the 20 s between cards), the offline ZoneDiscovery records both (user://hud_discovered.cfg), the
## P3 exit line when leaving the military checkpoint, and a scripted fast mover (the real player body moved at 25 m/s
## along the N‐140) gets the highway sign instead of the title. No SCRIPT ERROR on the way (run_smoke.sh greps them).

var s: RefCounted   # tests/smoke_steps.gd (check / frames / seconds)
var tree: SceneTree


func run(p_smoke: RefCounted, p_tree: SceneTree, game: Node, world: World, player: Player) -> void:
	s = p_smoke
	tree = p_tree
	print("-- H2: zones (enter, leave, discovery, highway sign)")
	var hud: Hud = game.get("hud")
	var disc := ZoneDiscovery.instance
	s.check(hud != null and disc != null and hud.zones.publish and hud.zone_sign != null and game.get_node_or_null("ZoneDiscovery") == disc,
		"H2 nodes: /root/Game/ZoneDiscovery, the HUD's publishing ZoneTracker, the highway sign")
	if hud == null or disc == null:
		return
	var zt := hud.zones
	# a quiet valley: a chasing zombie or a wolf would defer the cards (that is tested in the unit test)
	var dir_on := Director.instance != null and Director.instance.enabled
	var pop_on := PopulationManager.instance != null and PopulationManager.instance.enabled
	if Director.instance != null:
		Director.instance.enabled = false
	if PopulationManager.instance != null:
		PopulationManager.instance.enabled = false
	if ZombieSystem.instance != null:
		ZombieSystem.instance.clear_all()
	world.get_node("WolfSpawner").enabled = false
	WorldState.instance.set_time(WorldState.instance.day, 11.0)
	player.state.health = Balance.HEALTH_MAX
	player.state.warmth = 90.0   # no P0 (freezing) from the previous steps
	player.state.mark(&"stats")
	hud.settle_to_rest()
	zt.forget_all()
	await _until(func() -> bool: return not hud.in_combat() and not hud.p0_active(), 8.0)   # the HUD steps' hits fade (5 s)
	await s.frames(3)
	s.check(zt.discovery == disc and disc.synced and disc.known.is_empty(), "the tracker uses the group discovery (synced on spawn; forgotten for the test)")
	var cards: Array = []
	var zevents: Array = []
	var found: Array = []
	var c1 := func(i: Dictionary) -> void:
		if str(i.get("card", "none")) != "none":
			cards.append(i)
	var c2 := func(i: Dictionary) -> void: zevents.append(str(i["id"]))
	var c3 := func(id: StringName, _by: String, own: bool) -> void: found.append([String(id), own])
	Events.location_entered.connect(c1)
	Events.zone_entered.connect(c2)
	Events.zone_discovered.connect(c3)
	# zone 1: Granja del Molino (first visit → the 5.6 s title, discovery recorded by the offline server)
	Chat.instance.send("/tp -128 -896")
	var ok1 := await _until(func() -> bool: return str(zt.current.get("id", "")) == "granja_del_molino", 6.0)
	await s.frames(2)
	var card1: Dictionary = cards[-1] if not cards.is_empty() else {}
	s.check(ok1 and str(card1.get("id", "")) == "granja_del_molino" and str(card1.get("card", "")) == "full" and bool(card1.get("first_visit", false))
		and hud.zone_title.is_showing() and zevents.has("granja_del_molino") and found.has(["granja_del_molino", true]),
		"zone 1 entered after /tp: «%s» full title, zone_entered, discovered by the server (%s)" % [card1.get("name", "-"), found])
	# zone 2: Valdenieve — confirmed at once, its title waits the 20 s between cards (the clock is advanced)
	Chat.instance.send("/tp 176 -512")
	var ok2 := await _until(func() -> bool: return str(zt.current.get("id", "")) == "valdenieve", 6.0)
	var waited := str(zt.queued.get("id", "")) == "valdenieve"
	zt.clock += UiTokens.ZONE_GAP
	await _until(func() -> bool: return zt.queued.is_empty(), 2.0)
	var card2: Dictionary = cards[-1] if not cards.is_empty() else {}
	s.check(ok2 and waited and str(card2.get("id", "")) == "valdenieve" and str(card2.get("card", "")) == "full" and hud.zone_title.is_showing()
		and str(hud.zone_title.info.get("id", "")) == "valdenieve", "zone 2 entered: «%s» title after the 20 s gap between cards" % card2.get("name", "-"))
	var cfg := ConfigFile.new()
	cfg.load(ZoneDiscovery.OFFLINE_PATH)
	var ids: PackedStringArray = cfg.get_value("seed_%d" % WorldState.instance.world_seed, "ids", PackedStringArray())
	s.check(disc.known.has("granja_del_molino") and disc.known.has("valdenieve") and ids.has("granja_del_molino") and ids.has("valdenieve"),
		"both discoveries stored (offline: %s %s)" % [ZoneDiscovery.OFFLINE_PATH, ids])
	# leaving the military checkpoint (peligro extremo) for the N‐140: one P3 line in the feed
	Chat.instance.send("/tp 640 -1152")
	await _until(func() -> bool: return str(zt.current.get("id", "")) == "control_militar_km_12", 6.0)
	Chat.instance.send("/tp 640 -960")
	await _until(func() -> bool: return str(zt.current.get("id", "")) != "control_militar_km_12", 6.0)
	await s.frames(2)
	var feed_lines: Array = hud.feed.lines.map(func(l: Dictionary) -> String: return str(l["label"]))
	s.check(feed_lines.has("Has salido del Control militar km 12"), "leaving the checkpoint: P3 line «Has salido del Control militar km 12» (feed %s)" % [feed_lines])
	# a scripted fast mover: the player body at 25 m/s (90 km/h) south along the N‐140 into the Área de descanso
	Chat.instance.send("/tp 640 -10")
	await _until(func() -> bool: return str(zt.current.get("id", "")) == "n140", 6.0)
	zt.queued = {}   # the N‐140's own sign (first visit, still waiting its 20 s) is not part of this check
	zt.clock += UiTokens.ZONE_GAP
	cards.clear()
	var z := -10.0
	var pf := 0
	while z < 110.0 and pf < 600:
		await tree.physics_frame
		pf += 1
		z += 25.0 / float(Engine.physics_ticks_per_second)
		var x := lerpf(662.0, 652.0, (z + 60.0) / 188.0)   # on the bed (macro_roads n140: (662, −60) → (652, 128))
		player.global_position = Vector3(x, world.get_height(x, z) + 0.05, z)
		player.velocity = Vector3(0, 0, 25.0)
	await s.frames(2)
	var sign: Dictionary = cards[-1] if not cards.is_empty() else {}
	var sd: Dictionary = sign.get("sign", {})
	s.check(str(sign.get("id", "")) == "area_de_descanso" and str(sign.get("card", "")) == "sign" and hud.zone_sign.is_showing() and str(sd.get("style", "")) == "nacional"
		and str(sd.get("plate", "")) == "N‐140", "fast mover (%.0f km/h) on the N‐140: highway sign «%s» (%s, plate %s) instead of the title" % [zt.speed * 3.6,
		sd.get("dest", "-"), sd.get("style", "-"), sd.get("plate", "-")])
	var rig := CameraRig.active()
	s.check(rig == null or rig.profile.id == &"default", "valley zones keep the default camera profile")
	Events.location_entered.disconnect(c1)
	Events.zone_entered.disconnect(c2)
	Events.zone_discovered.disconnect(c3)
	# back home, the world as it was
	Chat.instance.send("/tp %.2f %.2f" % [world.get_spawn_point().x, world.get_spawn_point().z])
	await s.frames(5)
	if Director.instance != null:
		Director.instance.enabled = dir_on
	if PopulationManager.instance != null:
		PopulationManager.instance.enabled = pop_on
	hud.settle_to_rest()


## Waits (real time, ≤ `limit` s) until `cond` holds; true when it did.
func _until(cond: Callable, limit: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()):
		if Time.get_ticks_msec() - t0 > int(limit * 1000.0):
			return false
		await tree.process_frame
	return true
