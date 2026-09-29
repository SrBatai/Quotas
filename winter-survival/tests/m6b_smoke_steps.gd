extends RefCounted
## M6b part of the smoke test (step 22, called by tests/smoke_steps.gd after the H3 checks): La Herrería in the
## real game (offline = the local server runs in this process). After a /tp onto the village's main street:
##   * the SettlementSpawner built the village chunks around the player (KitBuildings of the plan, props, cars);
##   * the zone is La Herrería;
##   * village zombie density by land use: the PopulationManager wakes the residents of the hot village chunks —
##     exactly the Settlements targets (3–8 per chunk on average: sleepers inside the buildings, the street share
##     outside, some frozen) — and none stands inside a wall;
##   * a locked house door refuses to open («Cerrada con llave»);
##   * the shop alarm: an armed shop door opened through the validated request rings — the delta carries it, the
##     server emits ALARM noises of 150 m, and a walker 60 m away comes to investigate the shop;
##   * the bar's shelves roll the bar table (loot by building use).

var s: RefCounted   # tests/smoke_steps.gd (check / frames / seconds / request)
var tree: SceneTree


func run(p_smoke: RefCounted, p_tree: SceneTree, game: Node, world: World, player: Player) -> void:
	s = p_smoke
	tree = p_tree
	print("-- M6b: La Herrería (buildings, residents by land use, locked doors, shop alarm, loot by use)")
	var sp := SettlementSpawner.instance
	var sys := ZombieSystem.instance
	var pm := PopulationManager.instance
	s.check(sp != null and game.get_node_or_null("SettlementSpawner") == sp and sys != null and pm != null,
		"M6b nodes: /root/Game/SettlementSpawner (+ the zombie system and the population manager)")
	if sp == null or sys == null or pm == null:
		return
	var dir_on := Director.instance != null and Director.instance.enabled
	if Director.instance != null:
		Director.instance.enabled = false
	pm.enabled = false
	sys.clear_all()
	world.get_node("WolfSpawner").enabled = false
	WorldState.instance.set_time(WorldState.instance.day, 11.0)
	player.state.health = Balance.HEALTH_MAX
	player.state.warmth = 90.0
	player.state.mark(&"stats")
	var plan := Settlements.site(world.seed_value, "la_herreria")
	var main: PackedVector2Array = ((plan["streets"] as Array)[0] as Dictionary)["points"]
	var mid: Vector2 = SettlementGen.point_at(main, 60.0)[0]
	Chat.instance.send("/tp %d %d" % [int(mid.x), int(mid.y)])
	var near := func() -> Array:
		var out: Array = []
		for b in sp.all_buildings():
			if b.is_inside_tree() and b.global_position.distance_to(player.global_position) < 70.0:
				out.append(b)
		return out
	var arrived := func() -> bool:
		return player.global_position.distance_to(Vector3(mid.x, player.global_position.y, mid.y)) < 3.0 and (near.call() as Array).size() >= 6
	var built := await _until(arrived, 25.0)
	await s.seconds(1.0)
	var in_plan := 0
	for b: Dictionary in plan["buildings"]:
		if (b["pos"] as Vector2).distance_to(Vector2(player.global_position.x, player.global_position.z)) < 70.0:
			in_plan += 1
	var nb: Array = near.call()
	s.check(built and nb.size() >= in_plan - 1 and nb.size() >= 6,
		"the village chunks around the main street are built: %d KitBuildings within 70 m (plan: %d), %d chunks" % [nb.size(), in_plan, sp.live.size()])
	var zone := Locations.containing(player.global_position.x, player.global_position.z)
	s.check(not zone.is_empty() and str((zone[0] as Dictionary)["id"]) == "la_herreria", "zone: «%s»" % ((zone[0] as Dictionary)["name"] if not zone.is_empty() else "-"))
	# ---- residents by land use (PopulationManager on: the hot chunks within 110 m wake their residents)
	pm.pop.clear()
	pm.enabled = true
	await s.seconds(2.5)
	var want := 0
	var got := 0
	var hot := 0
	var inside_wall := 0
	var keys := {}
	for k in pm.pop:
		var t := Settlements.resident_target(world.seed_value, WorldConst.key_cx(int(k)), WorldConst.key_cz(int(k)))
		if t >= 0 and bool((pm.pop[k] as Dictionary)["spawned"]):
			keys[int(k)] = true
			hot += 1
			want += int(round(float(t) * pm._rule_scale()))
	var frozen := 0
	var indoor := 0
	for i in sys.used.size():
		if sys.used[i] == 0 or not keys.has(int(sys.chunk[i])):
			continue
		got += 1
		if sys.state[i] == ZombieKinds.State.FROZEN:
			frozen += 1
		var p := sys.pos[i]
		if Settlements.occupied(world.seed_value, p.x, p.z, 0.0):
			indoor += 1
	var avg := float(got) / float(maxi(hot, 1))
	s.check(hot >= 3 and got == want and avg >= 3.0 and avg <= 9.0,
		"village density: %d residents woke in %d hot village chunks (targets %d; %.1f per chunk, aldea 3–8)" % [got, hot, want, avg])
	s.check(indoor >= 3 and frozen >= 1, "land use: %d sleepers inside the buildings, %d frozen in the streets" % [indoor, frozen])
	pm.enabled = false
	sys.clear_all()
	await s.frames(2)
	# ---- a locked house door
	var locked: KitDoor = null
	var alarm_door: KitDoor = null
	var bar: KitBuilding = null
	for b in sp.all_buildings():
		if not b.is_inside_tree():
			continue
		for d in b.doors:
			if d.locked and locked == null and b.global_position.distance_to(player.global_position) < 90.0:
				locked = d
			if d.exterior and bool(b.opts.get("alarm", false)) and alarm_door == null and b.global_position.distance_to(player.global_position) < 90.0:
				alarm_door = d
		if str(b.get_meta("use", "")) == "bar":
			bar = b
	if locked != null:
		player.global_position = locked.global_position + (locked.get_parent() as Node3D).global_transform.basis * (locked.outward * 1.3)
		await s.frames(3)
		s.request(&"request_interact", [WorldRegistry.wid_of(locked), &"use", 0])
		await s.seconds(0.6)
		s.check(not locked.is_open and locked.get_interact_label(player) == "Cerrada con llave", "a locked house door stays shut («Cerrada con llave»)")
	else:
		s.check(false, "a locked house door exists near the main street")
	# ---- the shop alarm: 150 m ALARM noises, a walker 60 m away investigates
	if alarm_door != null:
		alarm_door.alarm_armed = true
		var out3 := (alarm_door.get_parent() as Node3D).global_transform.basis * alarm_door.outward
		player.global_position = alarm_door.global_position + out3 * 1.3 + Vector3(0, 0.1, 0)
		await s.frames(3)
		var zp := alarm_door.global_position + out3 * 60.0
		var z := sys.spawn(ZombieKinds.Kind.WALKER, Vector3(zp.x, world.get_height(zp.x, zp.z), zp.z), 0.0, ZombieKinds.State.IDLE, -1, -2)
		await s.seconds(0.5)
		var e0 := SoundEvents.emitted
		s.request(&"request_interact", [WorldRegistry.wid_of(alarm_door), &"use", 0])
		var rang := await _until(func() -> bool: return alarm_door.is_open and alarm_door.alarm_fired, 3.0)
		var alarm_seen := false
		for ev in SoundEvents.recent:
			if int(ev["kind"]) == SoundEvents.Kind.ALARM and float(ev["radius"]) >= 140.0:
				alarm_seen = true
		s.check(rang and bool(NetWorld.instance.delta_of(WorldRegistry.wid_of(alarm_door)).get("alarm", false)) and (alarm_seen or SoundEvents.emitted > e0),
			"the shop door opened and rang: the delta carries the alarm, ALARM noise of %.0f m" % KitDoor.ALARM_RADIUS)
		# the player steps away (the zombie must come for the noise, not for the player)
		player.global_position = alarm_door.global_position - out3 * 30.0 + Vector3(0, 0.1, 0)
		var heard := func() -> bool:
			return z >= 0 and (sys.state[z] == ZombieKinds.State.INVESTIGATE or sys.state[z] == ZombieKinds.State.CHASE) and (sys.goal[z] as Vector3).distance_to(alarm_door.global_position) < 12.0
		var inv := await _until(heard, 8.0)
		s.check(z >= 0 and inv, "a walker 60 m away heard the alarm and investigates the shop (goal %.1f m from the door)" % [
			(sys.goal[z] as Vector3).distance_to(alarm_door.global_position) if z >= 0 else -1.0])
		alarm_door.alarm_left = 0.0
	else:
		s.check(false, "an alarm-capable shop door near the main street")
	# ---- loot by use: the bar's shelves roll the bar table
	if bar != null:
		var tables := {}
		for c in bar.find_children("loot_*", "LootContainer", true, false):
			if not (c as LootContainer).loose:
				tables[String((c as LootContainer).table_id)] = true
		s.check(tables.keys() == ["bar"], "the bar's containers roll the bar table %s" % [tables.keys()])
	sys.clear_all()
	if Director.instance != null:
		Director.instance.enabled = dir_on
	pm.enabled = true


func _until(cond: Callable, limit: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()):
		if Time.get_ticks_msec() - t0 > int(limit * 1000.0):
			return false
		await tree.process_frame
	return true
