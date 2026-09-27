extends RefCounted
## M5 screenshot preset `firearms` (loaded by tests/screenshot_steps.gd): late afternoon at the campsite of camp_1.
## The survivor fires the pump shotgun at a walker 7 m away (12 pellet tracers, muzzle flash, the 150 m noise ring
## arc), the reticle hook shows the spread and the magazine; the campsite backpack lies open beside him (art manifest
## hinge) and two more walkers come out of the trees. Frozen (Engine.time_scale 0) on the shot.
##   RENDER=forward tests/run_screenshots.sh docs/screenshots/m5 firearms
## Camera yaw 45°: screen right = (+x, −z), toward the camera = (+x, +z).

var tree: SceneTree


func setup(p_tree: SceneTree, game: Node, world: World, player: Player, inv: InventoryComponent) -> void:
	tree = p_tree
	WorldState.instance.set_time(1, 17.1)
	world.get_node("WolfSpawner").enabled = false
	if Director.instance != null:
		Director.instance.enabled = false
	if PopulationManager.instance != null:
		PopulationManager.instance.enabled = false
	var sys := ZombieSystem.instance
	sys.clear_all()
	# the campsite of camp_1: its backpack container (LootSpawns builds it from the POI's Spawn_Container_* empty)
	var camp := Vector3(150.0, 0.0, 60.0)
	for pad in PoiRegistry.PADS:
		if str(pad["id"]) == "camp_1":
			var cc: Vector2 = pad["center"]
			camp = Vector3(cc.x, 0.0, cc.y)
	Chat.instance.send("/tp %.1f %.1f" % [camp.x + 3.0, camp.z + 3.0])
	for i in 30:
		await tree.process_frame
	world.streamer.flush_all()
	for i in 20:
		await tree.process_frame
	var lc: LootContainer = null
	var bd := 25.0
	for n in tree.get_nodes_in_group("loot_container"):
		var l := n as LootContainer
		if l != null and not l.loose and l.global_position.distance_to(camp) < bd:
			bd = l.global_position.distance_to(camp)
			lc = l
	var right := Vector3(0.7071, 0.0, -0.7071)
	var down := Vector3(0.7071, 0.0, 0.7071)
	# stand 1.6 m from the container, toward the camera and to its right, facing up-screen (away from the camera)
	var c := (lc.global_position if lc != null else camp) + down * 1.3 + right * 1.2
	c.y = world.get_height(c.x, c.z)
	player.global_position = c + Vector3(0, 0.2, 0)
	if lc != null:
		lc.storage.open_by = -1   # the lid / flap swings open without the storage panel on screen
	# the pump shotgun, loaded (6 shells in the tube), 9 more in the pockets
	inv.add(&"escopeta", 1, true, -1, 6)
	inv.add(&"cartuchos", 9)
	inv.add(&"vendas", 2)
	inv.add(&"bengala", 1)
	await tree.process_frame
	for i in range(1, player.state.slots.size()):
		if not player.state.slots[i].is_empty() and player.state.slots[i]["id"] == &"escopeta":
			Net.rpc_server(NetWorld.instance, &"request_use_slot", [i])
			break
	# the walkers: one 7 m up-screen (the target), two further out on the flanks
	var at := func(r: float, d: float) -> Vector3:
		var p := c + right * r + down * d
		p.y = world.get_height(p.x, p.z)
		return p
	var ids: Array[int] = []
	for g in [[0.6, -7.0], [-4.2, -9.5], [5.0, -10.5]]:
		var p: Vector3 = at.call(float(g[0]), float(g[1]))
		var dv := c - p
		var i := sys.spawn(ZombieKinds.Kind.WALKER, p, atan2(dv.x, dv.z), ZombieKinds.State.CHASE, -1, -2)
		if i >= 0:
			sys.target[i] = player.peer_id
			sys.mem_t[i] = sys._now()
			sys.last_seen[i] = c
			ids.append(i)
	var rig := CameraRig.active()
	if rig != null:
		rig.set_dist(15.0)
	var gun := player.get_node_or_null("Firearm") as FirearmClient
	var target_pos: Vector3 = at.call(0.6, -7.0) + Vector3(0, 1.2, 0)
	player.input.scripted_aim = target_pos
	# aim still for a second: the spread closes to green, the weapon class blend settles on Shotgun_Aim
	var pf := Engine.get_physics_frames()
	while Engine.get_physics_frames() - pf < 70:
		await tree.process_frame
		player.state.health = maxf(player.state.health, 90.0)
		var zc := ZombieClient.instance
		if not ids.is_empty() and zc != null:
			var zr: ZombieClient.ZRec = zc.record(sys.net_id[ids[0]])
			if zr != null:
				target_pos = zr.render_pos + Vector3(0, 1.2, 0)
				player.input.scripted_aim = target_pos
	# freeze first (the frame in flight keeps its delta), then fire: the muzzle flash and the tracers exist at once
	# (offline, the server validates and broadcasts the shot in the same call) and FirearmFx runs on the scaled game
	# clock, so they stay while the software-rendered frame settles (one lavapipe frame > a tracer's 90 ms)
	Engine.time_scale = 0.0
	sys.set_physics_process(false)
	# keep the camera where the firearm lean put it (screenshot_steps snaps the rig back onto the player, and with
	# the clock frozen it could not lean again): the rig stops following
	if rig != null:
		var cam_at := player.global_position.lerp(rig.global_position, 0.45)   # half the lean: shooter and target in frame
		rig.player = null
		rig.global_position = cam_at
	await tree.process_frame
	if gun != null:
		gun.aim_point = target_pos
		gun.ws.last_shot = -100.0
		gun.fire()
	print("firearms: gun %s ammo %s, tracers %d, flashes %d, noise radius %.0f m, loot %s (%s), zombies %d" % [player.state.hand_tool(),
		player.state.gun_view.get("ammo", "?"), FirearmFx.instance.tracers_spawned if FirearmFx.instance != null else -1,
		FirearmFx.instance.flashes if FirearmFx.instance != null else -1,
		ZombieClient.instance.last_noise_radius if ZombieClient.instance != null else -1.0,
		lc.model_name if lc != null else "none", lc.table_id if lc != null else &"", ids.size()])
