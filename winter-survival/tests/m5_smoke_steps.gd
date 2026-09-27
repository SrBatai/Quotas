extends RefCounted
## M5 part of the smoke test (step 17b, called by tests/smoke_steps.gd after the M4 checks). Offline = the local
## server runs in this process; every action goes through the validated NetWorld requests like a networked client.
## PLAN M5 acceptance: a shot → the noise ring → a zombie investigates. Plus: pistol reload from the ammo items
## (clip mag_in time), reticle data (spread closing to green, 30 Hz signal), hitscan damage / kill, dry fire, the
## shotgun's pellets and its 150 m ring, jam + unjam, the bow's arrow (server projectile), a thrown can (noise lure),
## loot containers at the campsite POI (deterministic roll, exclusive opening, contents persisted in the chunk delta),
## medicine, weight thresholds and the admin chat commands offline.

var s: RefCounted   # tests/smoke_steps.gd (check / frames / seconds / request / helpers)
var tree: SceneTree
var _reticles: int = 0
var _last_spread: float = -1.0
var _last_band: StringName = &""
var _mirror: Dictionary = {}
var _results: Array = []
var _loot_events: Array = []


func run(p_smoke: RefCounted, p_tree: SceneTree, game: Node, world: World, player: Player) -> void:
	s = p_smoke
	tree = p_tree
	print("-- M5: firearms, noise, loot")
	Events.reticle_changed.connect(func(sp: float, b: StringName, _a: Vector3, _r: float) -> void:
		_reticles += 1
		_last_spread = sp
		_last_band = b)
	Events.weapon_state_changed.connect(func(d: Dictionary) -> void: _mirror = d)
	Events.fire_result.connect(func(q: int, ok: bool, reason: String, hits: int, kills: int, _c: bool) -> void: _results.append([q, ok, reason, hits, kills]))
	Events.loot_opened.connect(func(wid: int, t: StringName, n: int) -> void: _loot_events.append([wid, t, n]))
	var sys := ZombieSystem.instance
	var gun := player.get_node_or_null("Firearm") as FirearmClient
	s.check(gun != null and Projectiles.instance != null and FirearmFx.instance != null and LootSpawns.instance != null
		and game.get_node_or_null("UI/ReticleHook") != null, "M5 nodes: FirearmClient on the local player, Projectiles (server), FirearmFx, LootSpawns, ReticleHook")
	if gun == null or sys == null:
		return
	sys.clear_all()
	# no wolves in these steps: a wolf that finds the player bites 15 every 1.5 s (weapon checks, the HUD steps after)
	world.get_node("WolfSpawner").enabled = false
	_no_wolves(world)
	# the M4 steps leave a full inventory: keep it aside and give it back at the end
	var saved_health: float = player.state.health
	var saved_slots: Array[Dictionary] = []
	for sl in player.state.slots:
		saved_slots.append(sl.duplicate())
	player.state.inventory.clear()
	WorldState.instance.set_time(WorldState.instance.day, 11.0)
	player.global_position = world.get_spawn_point() + Vector3(0, 0.3, 4.0)
	await s.frames(5)
	# -- medicine first (the HUD's health vital has settled again by the end of these steps)
	player.state.health = 50.0
	Chat.instance.send("/give vendas 1")
	await s.frames(3)
	for i in range(1, player.state.slots.size()):
		if not player.state.slots[i].is_empty() and player.state.slots[i]["id"] == &"vendas":
			s.request(&"request_use_slot", [i])
			break
	await s.frames(3)
	s.check(absf(player.state.health - 65.0) < 1.0 and player.state.count(&"vendas") == 0, "vendas: +15 health (%.1f)" % player.state.health)
	player.state.health = saved_health
	player.state.mark(&"stats")
	# -- give + equip the pistol (admin chat commands work offline), reload from the ammo items
	await s.seconds(1.05)
	Chat.instance.send("/give pistola 1")
	await s.seconds(0.6)
	Chat.instance.send("/give municion_9mm 30")
	await s.frames(3)
	s._equip(player, &"pistola")
	await s.frames(4)
	s.check(player.state.hand_tool() == &"pistola" and player.state.count(&"municion_9mm") == 30 and Gunplay.ammo_in(player) == 0
		and player.tool_holder.tool_model != null and player.tool_holder.tool_model.find_child("Muzzle", true, false) != null,
		"/give + equip: pistol in hand (empty magazine, model with its Muzzle anchor), 30 rounds of 9 mm")
	s.check(_mirror.get("w", "") == "pistola" and int(_mirror.get("reserve", -1)) == 30 and int(_mirror.get("mag", 0)) == 15,
		"weapon_state_changed mirror: %s" % str(_mirror))
	var t_reload := Firearms.reload_time(&"pistola")
	s.request(&"request_reload", [])
	await s.frames(2)
	s.check(player.state.gun.reload_until > 0.0 and Gunplay.ammo_in(player) == 0, "reload started (%.2f s to the clip's mag_in)" % t_reload)
	await s.seconds(t_reload + 0.15)
	s.check(Gunplay.ammo_in(player) == 15 and player.state.count(&"municion_9mm") == 15 and int(_mirror.get("ammo", -1)) == 15,
		"reload done: 15 in the magazine, 15 left in the inventory")
	# -- reticle: standing still the spread closes to the pistol's minimum (green); data at 30 Hz
	var r0 := _reticles
	await s.seconds(1.0)
	s.check(_reticles - r0 >= 20 and absf(_last_spread - 1.5) < 0.05 and _last_band == &"green",
		"reticle_changed %d times in 1 s, spread %.2f° (minimum 1.5), band %s" % [_reticles - r0, _last_spread, _last_band])
	# -- shot → noise ring (80 m) → a zombie 30 m behind the shooter, out of sight, comes to investigate
	var behind := player.global_position - player.facing() * 30.0
	var z: int = sys.spawn(ZombieKinds.Kind.WALKER, Vector3(behind.x, world.get_height(behind.x, behind.z), behind.z), player.aim_yaw, ZombieKinds.State.IDLE, -1, -2)
	await s.seconds(0.8)
	var st0 := sys.state[z]
	var goal0: Vector3 = sys.goal[z]
	var rings0 := CombatFx.instance.rings_spawned
	var emitted0 := SoundEvents.emitted
	var fired0 := Gunplay.fired
	var aim := player.global_position + player.facing() * 12.0 + Vector3(0, 1.2, 0)
	var ammo_before := Gunplay.ammo_in(player)
	player.input.scripted_aim = aim
	await s.frames(2)
	gun.aim_point = aim
	gun.fire()
	await s.frames(3)
	s.check(Gunplay.fired == fired0 + 1 and Gunplay.ammo_in(player) == ammo_before - 1 and SoundEvents.emitted > emitted0,
		"a pistol shot: server fired it (1 round spent), SoundEvents emitted")
	s.check(CombatFx.instance.rings_spawned > rings0 and absf(ZombieClient.instance.last_noise_radius - 80.0) < 1.0,
		"noise ring on the client: radius %.0f m (GDD §6.3: pistol 80)" % ZombieClient.instance.last_noise_radius)
	s.check(FirearmFx.instance.flashes >= 1 and FirearmFx.instance.tracers_spawned >= 1, "muzzle flash + tracer drawn (FirearmFx)")
	# hearing is a roll per think while the sound lives (1 − d/radius = 0.625 at 30 m inside the pistol's 80 m ring),
	# so a zombie can miss one shot: keep shooting, up to 10 shots (a false failure ≤ 0.375^10 ≈ 0.01 %)
	var investigating := false
	var hear_shots := 1
	while true:
		for k in 10:
			await s.seconds(0.1)
			if sys.state[z] == ZombieKinds.State.INVESTIGATE or sys.state[z] == ZombieKinds.State.CHASE:
				investigating = true
				break
		if investigating or hear_shots >= 10:
			break
		gun.aim_point = aim
		gun.fire()
		hear_shots += 1
	if hear_shots > 1:
		# the extra shots only re-roll the hearing: put the magazine back where the single shot left it
		player.state.slots[0]["ammo"] = ammo_before - 1
		player.state.mark(&"gun")
		await s.frames(3)
		gun.ammo = ammo_before - 1
	var goal: Vector3 = sys.goal[z]
	# before the shot it idles or wanders (not already after the player); afterwards it investigates the shooter's spot
	var calm := st0 == ZombieKinds.State.IDLE or st0 == ZombieKinds.State.WANDER or goal0.distance_to(player.global_position) > 10.0
	s.check(calm and investigating and goal.distance_to(player.global_position) < 6.0,
		"the zombie 30 m behind heard the shots and investigates (%d shot(s), state %d → %d, goal %.1f → %.1f m from the shooter)" % [hear_shots, st0, sys.state[z],
			goal0.distance_to(player.global_position), goal.distance_to(player.global_position)])
	sys.clear_all()
	await s.frames(2)
	# -- hitscan: a walker 6 m ahead dies to pistol shots (server damage, cadence respected)
	var t: int = s._spawn_front(sys, player, ZombieKinds.Kind.WALKER, 6.0)
	var tid := sys.net_id[t]
	await s.seconds(0.4)
	var shots := 0
	_results.clear()
	for k in 10:
		if not sys.is_alive(t):
			break
		s._hold_zombie(sys, t, player, 6.0)
		gun.aim_point = sys.pos[t] + Vector3(0, 1.1, 0)
		gun.aim_zombie = tid
		if gun.fire():
			shots += 1
		await s.seconds(0.3)
	var hits := 0
	for r in _results:
		hits += int(r[3])
	s.check(not sys.is_alive(t) and shots >= 2 and shots <= 7 and hits >= 2, "pistol kills a walker at 6 m in %d shots (%d hits reported to the shooter)" % [shots, hits])
	# -- dry fire: empty magazine clicks, nothing spent, reason sin_municion
	player.state.slots[0]["ammo"] = 0
	player.state.mark(&"gun")
	await s.frames(3)
	gun.ammo = 0
	_results.clear()
	var dry0 := Gunplay.dry
	await s.seconds(0.3)
	gun.fire()
	await s.frames(3)
	s.check(Gunplay.dry == dry0 + 1 and not _results.is_empty() and _results[-1][2] == "sin_municion", "dry fire refused: %s" % str(_results))
	# -- jam + unjam (R clears it: Act_Unjam `clear`)
	player.state.slots[0]["ammo"] = 5
	player.state.gun.jammed = true
	player.state.mark(&"gun")
	await s.frames(3)
	gun.ws.jammed = true
	_results.clear()
	await s.seconds(0.3)
	gun.fire()
	await s.frames(3)
	var refused: bool = not _results.is_empty() and _results[-1][2] == "encasquillada"
	s.check(refused and gun.wants_reload(), "a jammed gun refuses to fire; R wants to clear it")
	gun.reload()
	await s.seconds(Firearms.unjam_time() + 0.2)
	s.check(not player.state.gun.jammed and not bool(_mirror.get("jammed", true)), "unjammed after %.2f s" % Firearms.unjam_time())
	# -- shotgun: 12 pellets, 150 m ring (sent in whole metres), knockdown / kill at 4 m
	Chat.instance.send("/give escopeta 1")
	await s.seconds(0.6)
	Chat.instance.send("/give cartuchos 12")
	await s.frames(3)
	s._equip(player, &"escopeta")
	await s.frames(3)
	player.state.slots[0]["ammo"] = 4
	player.state.mark(&"gun")
	await s.frames(3)
	var sg: int = s._spawn_front(sys, player, ZombieKinds.Kind.WALKER, 4.0)
	await s.seconds(0.4)
	s._hold_zombie(sys, sg, player, 4.0)
	var tr0 := FirearmFx.instance.tracers_spawned
	gun.aim_point = sys.pos[sg] + Vector3(0, 1.1, 0)
	gun.fire()
	await s.frames(3)
	s.check(FirearmFx.instance.tracers_spawned - tr0 >= 12 and (Gunplay.last_shot.get("ends", PackedVector3Array()) as PackedVector3Array).size() == 12,
		"shotgun: 12 pellet tracers (%d)" % (FirearmFx.instance.tracers_spawned - tr0))
	s.check(absf(ZombieClient.instance.last_noise_radius - 150.0) < 1.0, "shotgun ring 150 m reaches the client intact (%.0f m)" % ZombieClient.instance.last_noise_radius)
	s.check(not sys.is_alive(sg) or sys.hp[sg] < 40.0 or sys.state[sg] == ZombieKinds.State.KNOCKED, "the buckshot at 4 m kills or floors the walker (hp %.0f)" % (sys.hp[sg] if sys.is_alive(sg) else 0.0))
	# shell-by-shell reload
	var shells0 := Gunplay.ammo_in(player)
	s.request(&"request_reload", [])
	await s.seconds(Firearms.reload_time(&"escopeta") * 2.0 + 0.2)
	s.check(Gunplay.ammo_in(player) >= shells0 + 2, "shotgun loads shell by shell (%d → %d)" % [shells0, Gunplay.ammo_in(player)])
	sys.clear_all()
	await s.frames(2)
	# -- bow: a server-simulated arrow hits a walker 8 m ahead
	Chat.instance.send("/give arco 1")
	await s.seconds(0.6)
	Chat.instance.send("/give flechas 5")
	await s.frames(3)
	s._equip(player, &"arco")
	await s.frames(3)
	var bz: int = s._spawn_front(sys, player, ZombieKinds.Kind.WALKER, 8.0)
	await s.seconds(1.5)
	s._hold_zombie(sys, bz, player, 8.0)
	var hp0: float = sys.hp[bz]
	var arrows0 := Projectiles.instance.arrows_fired
	var ahits0 := Projectiles.instance.arrow_hits
	gun.aim_point = sys.pos[bz] + Vector3(0, 1.1, 0)
	gun.trigger_pressed()
	await s.seconds(1.45)
	s._hold_zombie(sys, bz, player, 8.0)
	gun.aim_point = sys.pos[bz] + Vector3(0, 1.1, 0)
	var held_at: Vector3 = sys.pos[bz]
	gun.trigger_released()
	# the walker stays where the arrow was aimed while it flies (8 m at 42 m/s; slow frames under load)
	var t_fly := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_fly < 600:
		if sys.is_alive(bz) and Projectiles.instance.arrow_hits == ahits0:
			sys.pos[bz] = held_at
			if sys.body[bz] != null:
				(sys.body[bz] as CharacterBody3D).global_position = held_at + Vector3(0, 0.05, 0)
		await s.frames(1)
	s.check(Projectiles.instance.arrows_fired == arrows0 + 1 and Projectiles.instance.arrow_hits == ahits0 + 1 and (not sys.is_alive(bz) or sys.hp[bz] < hp0)
		and player.state.count(&"flechas") == 4, "bow: a full draw looses one arrow that hits the walker 8 m ahead (hp %.0f → %.0f; fired %d, hits %d, arrows left %d)" % [hp0,
			sys.hp[bz] if sys.is_alive(bz) else 0.0, Projectiles.instance.arrows_fired - arrows0, Projectiles.instance.arrow_hits - ahits0, player.state.count(&"flechas")])
	sys.clear_all()
	# -- a thrown can: lands, makes a 15 m noise (lure)
	Chat.instance.send("/give lata_vacia 2")
	await s.frames(3)
	s._equip(player, &"lata_vacia")
	await s.frames(3)
	var landed0 := Projectiles.instance.landed
	var ev0 := SoundEvents.emitted
	var target := player.global_position + player.facing() * 8.0
	gun.throw_at(target)
	await s.seconds(1.2)
	s.check(Projectiles.instance.landed == landed0 + 1 and SoundEvents.emitted > ev0 and player.state.count(&"lata_vacia") == 1,
		"a thrown can lands %.1f m away and makes noise" % target.distance_to(player.global_position))
	# -- loot: the containers of a campsite POI (Spawn_Container_0 'campsite', Spawn_Loot_0/1)
	await _loot_checks(world, player)
	# -- weight thresholds
	var ratio0: float = player.state.inventory.carry_ratio
	player.state.inventory.add(&"piedra", 60, true)
	await s.frames(4)
	var heavy: bool = player.state.inventory.carry_ratio > 1.0 and player.speed_mult <= Balance.CARRY_HEAVY_MULT + 0.01 and not player.can_run
	player.state.inventory.remove(&"piedra", player.state.count(&"piedra"))
	await s.frames(4)
	s.check(heavy and is_equal_approx(player.speed_mult, 1.0), "weight: > 100 %% of %.0f kg slows to ×0.6 and stops running; back to ×1 after dropping it (%.2f → heavy)" % [Balance.CARRY_CAPACITY, ratio0])
	# clean up for the next steps
	sys.clear_all()
	for i in player.state.slots.size():
		player.state.slots[i] = saved_slots[i] if i < saved_slots.size() else {}
	player.state.inventory.after_load()
	player.input.scripted_aim = Vector3.INF
	# the zombies of these steps bit a little; full health now, and warm / fed enough that nothing drains it while
	# the next steps start (the HUD steps set 100 / 90 / 80: a health jump ≥ 2 inside 2 s would show the vital)
	player.state.health = maxf(saved_health, Balance.HEALTH_MAX)
	player.state.warmth = maxf(player.state.warmth, 90.0)
	player.state.hunger = maxf(player.state.hunger, 80.0)
	player.state.mark(&"stats")
	Chat.instance.send("/tp %.2f %.2f" % [world.get_spawn_point().x, world.get_spawn_point().z])
	_no_wolves(world)
	await s.seconds(4.5)


func _no_wolves(world: World) -> void:
	for w in world.get_tree().get_nodes_in_group("wolves"):
		w.queue_free()


func _loot_checks(world: World, player: Player) -> void:
	var camp: Dictionary = {}
	for pad in PoiRegistry.PADS:
		if str(pad["id"]) == "camp_1":
			camp = pad
	if camp.is_empty():
		s.check(false, "camp_1 POI in PoiRegistry.PADS")
		return
	var c2: Vector2 = camp["center"]
	await s.seconds(1.05)
	Chat.instance.send("/tp %.2f %.2f" % [c2.x + 4.0, c2.y + 4.0])
	await s.seconds(1.0)
	var found: Array[LootContainer] = []
	for n in tree.get_nodes_in_group("loot_container"):
		var lc := n as LootContainer
		if lc != null and Vector2(lc.global_position.x - c2.x, lc.global_position.z - c2.y).length() < 8.0:
			found.append(lc)
	var big: LootContainer = null
	for lc in found:
		if not lc.loose:
			big = lc
	s.check(found.size() == 3 and big != null and big.table_id == &"campsite", "campsite POI: %d loot containers from its Spawn_* empties (1 'campsite' + 2 loose)" % found.size())
	if big == null:
		return
	var poi := big.get_parent()
	var wid := WorldRegistry.wid_of(big)
	# spawns sorted by name: Spawn_Container_0 is the first → index 1
	s.check(wid == WorldConst.hash64(world.seed_value, Loot.GEN_LOOT, int(poi.get_meta("wid", 0)), 1),
		"container wid is deterministic (hash64 of seed, POI wid, spawn index): %x" % wid)
	# walk to it and open it (validated request): rolled on the server = Loot.roll(seed, wid, table, day)
	player.global_position = big.global_position + big.global_basis.z * 1.0 + Vector3(0, 0.3, 0)
	await s.frames(4)
	var expect := Loot.roll(world.seed_value, wid, &"campsite", WorldState.day_now())
	_loot_events.clear()
	s.request(&"request_interact", [wid, &"open", 0])
	await s.frames(4)
	var st := big.storage
	var got := []
	for sl in st.slots:
		if not sl.is_empty():
			got.append("%s×%d" % [sl["id"], int(sl["count"])])
	var want := []
	for it in expect:
		want.append("%s×%d" % [it["id"], int(it["count"])])
	var entry := NetWorld.instance.container_entry(wid)
	s.check(st.open_by == player.peer_id and got == want and int(entry.get("rolled_day", -1)) == WorldState.day_now() and _loot_events.size() == 1,
		"opening rolls the table once, deterministically: %s (expected %s), stored as the container delta" % [str(got), str(want)])
	# take one stack: the delta follows; closing saves; reopening does not re-roll
	var took := false
	for i in st.slots.size():
		if not st.slots[i].is_empty():
			s.request(&"request_take", [wid, i, true])
			took = true
			break
	await s.frames(3)
	var left := 0
	for sl in st.slots:
		if not sl.is_empty():
			left += 1
	var stored: Array = NetWorld.instance.container_entry(wid).get("items", [])
	var stored_n := 0
	for it in stored:
		if not (it as Dictionary).is_empty():
			stored_n += 1
	s.check(not took or (left == got.size() - 1 and stored_n == left), "taking a stack updates the persisted contents (%d left)" % left)
	s.request(&"request_close_storage", [wid])
	await s.frames(3)
	s.request(&"request_interact", [wid, &"open", 0])
	await s.frames(3)
	var left2 := 0
	for sl in st.slots:
		if not sl.is_empty():
			left2 += 1
	s.check(left2 == left and Loot.rolls >= 1, "reopening shows what was left (no re-roll)")
	s.request(&"request_close_storage", [wid])
	await s.frames(2)
