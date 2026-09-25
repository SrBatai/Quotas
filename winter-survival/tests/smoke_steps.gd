extends RefCounted
## Smoke test body (loaded at runtime by tests/smoke_test.gd so autoloads exist when it compiles).
## M1: offline = the authoritative local server runs in this process (OfflineMultiplayerPeer, peer 1); every
## gameplay action goes through the validated NetWorld requests, exactly like a networked client would.
## M2: skeletal survivor (feet metric: ankle >= 0.08 m, sliding < 5 %), action-based interaction, ChunkDelta,
## DropSpawner / StructureSpawner, DamageResolver v0 on wolves and deer, persistence backends.

var tree: SceneTree

var _failed: bool = false
var _checks: int = 0
var _signals: Dictionary = {}
var _chat_lines: Array = []
var _hit_results: Array = []


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		_failed = true
		print("FAIL: ", msg)


func _watch(sig: StringName) -> void:
	_signals[sig] = 0
	var argc := 0
	for s in Events.get_signal_list():
		if s["name"] == String(sig):
			argc = s["args"].size()
	match argc:
		0: Events.connect(sig, func() -> void: _signals[sig] += 1)
		1: Events.connect(sig, func(_a) -> void: _signals[sig] += 1)
		2: Events.connect(sig, func(_a, _b) -> void: _signals[sig] += 1)
		_: Events.connect(sig, func(_a, _b, _c) -> void: _signals[sig] += 1)


func fired(sig: StringName) -> int:
	return int(_signals.get(sig, 0))


func frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func seconds(s: float) -> void:
	await tree.create_timer(s).timeout


func request(method: StringName, args: Array) -> void:
	Net.rpc_server(NetWorld.instance, method, args)


func run(p_tree: SceneTree) -> void:
	tree = p_tree
	print("== VENTISCA smoke test (M1: offline = local server)")
	for sig in [&"world_ready", &"tree_felled", &"item_consumed", &"wolf_died", &"weather_changed", &"shelter_changed",
			&"day_started", &"player_died", &"game_won", &"campfire_placed", &"stove_fueled", &"crafted", &"night_started",
			&"local_player_ready", &"player_respawned", &"inventory_changed", &"quest_updated", &"stat_changed"]:
		_watch(sig)
	Events.chat_message.connect(func(who: String, text: String) -> void: _chat_lines.append([who, text]))
	Events.hit_result.connect(func(v: int, blocked: bool, reason: String) -> void: _hit_results.append([v, blocked, reason]))
	await tree.process_frame
	# 1. load the game scene through the flow (offline local server)
	GameFlow.play_offline()
	var waited := 0
	while fired(&"world_ready") == 0 and waited < 600:
		await tree.process_frame
		waited += 1
	check(fired(&"world_ready") > 0, "world_ready emitted (%d frames)" % waited)
	waited = 0
	while GameFlow.local_player() == null and waited < 300:
		await tree.process_frame
		waited += 1
	await frames(5)
	var game := tree.current_scene
	var player: Player = GameFlow.local_player()
	var world: World = game.get_node("World")
	# 2. structure
	check(player != null, "player exists")
	check(player != null and player.name == "1" and player.get_parent().name == "Players", "player spawned by PlayerSpawner as peer 1 under World/Players")
	check(Net.role == Net.Role.OFFLINE and Net.is_server and Net.has_client and multiplayer_id() == 1, "offline mode = authoritative local server in-process (peer 1)")
	check(player.is_local and player.state.inventory != null and player.state.stats != null and player.state.quests != null, "local player has the server components (Inventory/Stats/Quests)")
	check(player.view != null and player.input != null and player.interactor != null and player.camera_rig != null, "local player has the client branches (View/Input/Interactor/CameraRig)")
	check(game.get_node_or_null("WorldState") != null and game.get_node_or_null("NetWorld") != null and game.get_node_or_null("Chat") != null, "WorldState / NetWorld / Chat at fixed paths")
	check(game.get_node_or_null("UI/HUD") != null and game.get_node_or_null("PlayerManager") != null, "client UI and server PlayerManager branches added at runtime")
	check(world.terrain.get_node_or_null("Shape") != null and world.terrain.get_node("Shape").shape != null, "terrain collision shape present")
	check(world.cabin != null, "cabin exists")
	var stove: WoodStove = world.cabin.get_node("Stove")
	check(stove != null and stove.is_lit, "stove exists and is lit")
	var cabinet := world.cabin.get_node("Cabinet")
	check(cabinet != null, "cabinet exists")
	var trees := tree.get_nodes_in_group("tree")
	check(trees.size() >= 200, "trees in group 'tree': %d" % trees.size())
	check(tree.get_nodes_in_group("pickup").size() >= 1, "pickups exist: %d" % tree.get_nodes_in_group("pickup").size())
	check(String(trees[0].name).begins_with("tree_") and WorldRegistry.get_object(WorldRegistry.wid_of(trees[0])) == trees[0], "scatter names are deterministic and registered (wid)")
	check(WorldState.instance.day == 1, "day == 1")
	check(absf(WorldState.instance.hour - 8.0) < 0.2, "hour ≈ 8 (%.2f)" % WorldState.instance.hour)
	check(tree.get_nodes_in_group("deer").size() >= 1, "deer spawned: %d" % tree.get_nodes_in_group("deer").size())
	# 2b. M0 conventions: Jolt, MODEL_FRONT (+Z), shared vertex-colour material, GPU particles, snow global
	check(str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) == "Jolt Physics", "physics engine is Jolt")
	check(is_zero_approx(world.cabin.rotation.y), "cabin yaw is 0 (porch = +Z = MODEL_FRONT)")
	var door: Node3D = world.cabin.get_door_anchor()
	check(door != null and (door.global_position - world.cabin.global_position).z > 2.0, "cabin DoorAnchor in front (+Z)")
	var to_door := (door.global_position - player.global_position) if door != null else Vector3.MODEL_FRONT
	to_door.y = 0.0
	check(player.facing().dot(to_door.normalized()) > 0.9, "player spawns facing the door with +basis.z")
	check(Assets.count_unshared_vcol(world.cabin.model) == 0 and Assets.count_unshared_vcol(player.model) == 0, "palette_vcol replaced by the shared material")
	var shared_surfaces := 0
	for mi in Assets._mesh_instances(player.model):
		for i in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_material(i) == Assets.get_shared_material():
				shared_surfaces += 1
	check(shared_surfaces >= 1, "player model uses the shared world_vcol material (%d surfaces)" % shared_surfaces)
	check(world.get_node("Snowfall").light_snow is GPUParticles3D, "snowfall is GPUParticles3D")
	check(world.cabin.smoke is GPUParticles3D, "chimney smoke is GPUParticles3D")
	check(ProjectSettings.has_setting("shader_globals/snow_amount"), "snow_amount global shader parameter declared")
	check(Quality.preset in [&"alto", &"medio", &"compat"], "Quality preset set (%s, detected %s)" % [Quality.preset, Quality.detected])
	check(player.camera_rig.camera.far <= 70.0, "camera far <= 70 (%.0f)" % player.camera_rig.camera.far)
	# 2c. M1 speeds (PLAN C19 updated) and packet round trip
	check(is_equal_approx(Balance.WALK_SPEED, 2.2) and is_equal_approx(Balance.RUN_SPEED, 6.0) and is_equal_approx(Balance.CROUCH_SPEED, 1.3), "speeds walk 2.2 / run 6.0 / crouch 1.3 m/s")
	var cmds := [{"seq": 7, "move": Vector2(0.5, -1.0).limit_length(1.0), "aim_yaw": 1.25, "aim": Vector3(3, 1.2, -4), "btn": Packets.BTN_RUN, "slot": 2, "flags": 0, "pos": Vector3.ZERO},
		{"seq": 8, "move": Vector2.ZERO, "aim_yaw": -2.0, "aim": Vector3(1, 0, 1), "btn": 0, "slot": 0, "flags": 0, "pos": Vector3.ZERO}]
	var packed := Packets.pack_cmds(cmds)
	var back := Packets.unpack_cmds(packed, Vector3.ZERO)
	check(packed.size() == 1 + 2 * Packets.CMD_SIZE and back.size() == 2 and int(back[1]["seq"]) == 8 and absf(float(back[0]["aim_yaw"]) - 1.25) < 0.001
		and (back[0]["aim"] as Vector3).distance_to(Vector3(3, 1.2, -4)) < 0.02 and int(back[0]["btn"]) == Packets.BTN_RUN, "input packet pack/unpack round trip (%d B for 2 cmds)" % packed.size())
	# 3. run a bit
	await frames(120)
	check(not is_nan(player.state.health) and not is_nan(player.state.warmth) and not is_nan(player.state.hunger), "stats are numbers")
	check(player.state.hunger < Balance.HUNGER_START, "hunger draining (%.2f)" % player.state.hunger)
	check(fired(&"stat_changed") >= 3, "stat mirror reached the HUD (stat_changed x%d)" % fired(&"stat_changed"))
	check(player.is_on_floor(), "player on floor (y=%.2f)" % player.global_position.y)
	# Jolt + HeightMapShape3D (scaled 2 m cells) + porch collision: the capsule rests on the surface, not in it
	var ground_y: float = world.get_height(player.global_position.x, player.global_position.z)
	check(player.global_position.y > ground_y - 0.15 and player.global_position.y < ground_y + 1.2, "player resting on terrain/porch under Jolt (dy=%.2f)" % (player.global_position.y - ground_y))
	var deer_ok := true
	var deer_info := ""
	for d in tree.get_nodes_in_group("deer"):
		var dy: float = d.global_position.y - world.get_height(d.global_position.x, d.global_position.z)
		deer_info += " [dy=%.2f floor=%s v=%.1f]" % [dy, d.is_on_floor(), d.velocity.length()]
		if not d.is_on_floor() or dy < -0.5 or dy > 0.8:
			deer_ok = false
	check(deer_ok, "deer resting on the heightmap under Jolt%s" % deer_info)
	# 3b. movement through the shared PlayerSim from scripted input (walk speed)
	var p0 := player.global_position
	player.input.scripted_move = Vector2(0, 1)
	await seconds(1.0)
	player.input.scripted_move = Vector2.INF
	var moved := Vector2(player.global_position.x - p0.x, player.global_position.z - p0.z).length()
	check(moved > 1.2 and moved < 2.6, "scripted walk moved %.2f m in 1 s (walk 2.2 m/s)" % moved)
	# 3c. M2 skeletal player: GeneralSkeleton, AnimationTree states synced to the ground speed, feet metric
	var visual: CharacterVisual = player.view.visual
	check(visual.is_skeletal and visual.skeleton != null and visual.skeleton.get_bone_count() == 27, "skeletal survivor spawned (GeneralSkeleton, %d bones)" % (visual.skeleton.get_bone_count() if visual.skeleton != null else 0))
	check(visual.model != null and String(visual.model.name).begins_with("survivor_") and player.outfit == 0 and visual.variant == 0, "jacket variant from the replicated outfit (%s)" % (visual.model.name if visual.model != null else "-"))
	check(visual.tree.active and visual.anim_player.has_animation("loco/Loco_Walk") and visual.anim_player.has_animation("loco/Act_Chop"), "AnimationTree active with the loco library (+ generated Act_Chop)")
	await frames(20)
	check(visual.state == &"Idle" and visual.hips_height() > 0.8 and visual.hips_height() < 1.0, "idle state at rest, hips at %.2f m (motion scale applied)" % visual.hips_height())
	var feet := await _feet_metric(player, Vector2(0, 1), false, 90)
	check(visual.state == &"Walk" and absf(visual.time_scale - 1.0) < 0.12, "walk cycle time-scaled to the ground speed (state %s, scale %.2f)" % [visual.state, visual.time_scale])
	check(feet["ankle_min"] >= 0.08, "walk feet metric: ankle min %.3f m >= 0.08" % feet["ankle_min"])
	check(feet["sliding"] < 5.0, "walk feet metric: stance sliding %.1f %% < 5 %% (body %.2f m/s, %d stance samples)" % [feet["sliding"], feet["body_speed"], feet["stance_samples"]])
	# run across the flat pad around the cabin (a slope or the porch would cut the ground speed below 6 m/s)
	player.input.scripted_move = Vector2.INF
	player.global_position = world.get_spawn_point() + Vector3(-1.0, 0.3, 3.0)
	await frames(10)
	var feet_run := await _feet_metric(player, Vector2(-1, 0), true, 60)
	check(visual.state == &"Run" and absf(visual.time_scale - 1.0) < 0.12, "run cycle time-scaled to the ground speed (state %s, scale %.2f)" % [visual.state, visual.time_scale])
	# the run clip itself bottoms out at 0.077 m in Godot (retarget of Loco_Run; Opus to lift it 3 mm): sliding is the code-side metric
	check(feet_run["ankle_min"] >= 0.07 and feet_run["sliding"] < 5.0, "run feet metric: ankle min %.3f m (clip floor 0.077), sliding %.1f %% < 5 %% (body %.2f m/s, %d stance samples)" % [feet_run["ankle_min"], feet_run["sliding"], feet_run["body_speed"], feet_run["stance_samples"]])
	player.input.scripted_move = Vector2.INF
	player.input.scripted_run = false
	await frames(30)
	check(visual.state == &"Idle", "back to idle after the run")
	# head aim: LookAtModifier3D turns the head toward the (replicated) aim point
	var fwd := visual.global_basis.z
	player.input.scripted_aim = player.global_position + Vector3(0, 1.2, 0) + fwd.rotated(Vector3.UP, deg_to_rad(60.0)) * 5.0
	await frames(30)
	var head_yaw := rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(Vector2(visual.head_forward().x, visual.head_forward().z)))
	check(visual.look_at != null and visual.look_at.active and absf(head_yaw) > 20.0, "LookAtModifier3D turns the head toward aim_point (%.0f deg)" % head_yaw)
	player.input.scripted_aim = Vector3.INF
	await frames(10)
	# cold idle from the replicated flag
	var warmth_saved: float = player.state.warmth
	player.state.warmth = Balance.COLD_VIGNETTE_START - 5.0
	await frames(3)
	check(player.cold and visual.state == &"Cold", "cold flag replicated -> shivering idle (state %s)" % visual.state)
	player.state.warmth = warmth_saved
	await frames(3)
	check(not player.cold and visual.state == &"Idle", "warm again -> idle")
	# 4. inventory + craft axe (server component; mirror + HUD via inventory_changed)
	var inv_events := fired(&"inventory_changed")
	player.state.inventory.add(&"madera", 2)
	player.state.inventory.add(&"piedra", 3)
	await frames(2)
	check(fired(&"inventory_changed") > inv_events, "inventory mirror flushed to the HUD")
	var craft_panel: CraftPanel = game.get_node("UI/CraftPanel")
	var ok := craft_panel.craft(&"hacha")
	check(ok, "crafted hacha via CraftPanel.craft (request_craft)")
	check(fired(&"crafted") >= 1, "crafted signal fired")
	if player.state.hand_tool() != &"hacha":
		for i in range(1, player.state.slots.size()):
			if not player.state.slots[i].is_empty() and player.state.slots[i]["id"] == &"hacha":
				request(&"request_use_slot", [i])
	check(player.state.hand_tool() == &"hacha" and player.hand_tool == &"hacha", "axe equipped in hand (state + replicated hand_tool)")
	check(player.state.count(&"madera") == 0 and player.state.count(&"piedra") == 0, "materials consumed")
	await frames(2)
	check(player.tool_holder.tool_model != null and player.tool_holder.tool_model.get_parent() is BoneAttachment3D
		and (player.tool_holder.tool_model.get_parent() as BoneAttachment3D).bone_name == "RightHandSocket", "axe model attached to the RightHandSocket bone")
	var hand_i: int = visual.skeleton.find_bone("RightHand")
	var hand_world: Vector3 = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(hand_i).origin
	check(player.tool_holder.tool_model.global_position.distance_to(hand_world) < 0.15, "tool follows the animated hand (%.2f m from RightHand)" % player.tool_holder.tool_model.global_position.distance_to(hand_world))
	# 5. chop the nearest pine through the validated request (distance + tool checked on the server)
	var nearest: ChoppableTree = null
	var best := INF
	for t in tree.get_nodes_in_group("tree"):
		if not String(t.variant).begins_with("pine"):
			continue
		var d: float = t.global_position.distance_to(player.global_position)
		if d < best:
			best = d
			nearest = t
	check(nearest != null, "found a tree to chop")
	if nearest != null:
		var wid := WorldRegistry.wid_of(nearest)
		var far := nearest.global_position + Vector3(12.0, 0.3, 0)
		far.y = world.get_height(far.x, far.z) + 0.3
		player.global_position = far
		await frames(3)
		request(&"request_interact", [wid, &"chop", 0])
		await frames(2)
		check(nearest.hits == 0, "far request_interact rejected by the server (hits=%d)" % nearest.hits)
		var side := (player.global_position - nearest.global_position)
		side.y = 0.0
		side = side.normalized() * 1.5
		player.global_position = nearest.global_position + side + Vector3(0, 0.3, 0)
		await frames(3)
		var infr_before: int = NetWorld.instance.infractions_of(1)
		request(&"request_interact", [wid, &"open", 0])
		await frames(2)
		check(nearest.hits == 0 and NetWorld.instance.infractions_of(1) == infr_before + 1, "unknown action rejected and counted as an infraction")
		request(&"request_interact", [wid, &"chop", 0])
		await frames(2)
		check(nearest.hits == 1 and visual.tree.get("parameters/action/active") == true, "chop accepted: hit 1 + torso OneShot playing")
		await seconds(0.55)
		for i in nearest.total_hits - 1:
			request(&"request_interact", [wid, &"chop", 0])
			await seconds(0.55)
		check(fired(&"tree_felled") >= 1, "tree_felled fired")
		check(player.state.count(&"madera") == Balance.TREE_WOOD, "wood after chop == %d (got %d)" % [Balance.TREE_WOOD, player.state.count(&"madera")])
		check(NetWorld.instance.delta_of(wid).get("felled", false) == true, "tree felled recorded as a world delta")
		var cd: ChunkDelta = NetWorld.instance.chunk_for(wid)
		check(cd != null and cd.objects.has(wid) and cd.cx >= 23 and cd.cx <= 25 and cd.cz >= 23 and cd.cz <= 25 and cd.is_dirty(), "delta stored in ChunkDelta (%d, %d) of the clearing, dirty" % [cd.cx, cd.cz])
		var cpk := cd.pack()
		var cback := ChunkDelta.unpack(int(cpk["size"]), cpk["bytes"])
		check(not cback.is_empty() and (cback["objects"] as Dictionary).has(wid) and bool(cback["objects"][wid]["felled"]) and (cpk["bytes"] as PackedByteArray).size() < int(cpk["size"]), "CHUNK_DELTA pack/unpack round trip (%d B zstd of %d)" % [(cpk["bytes"] as PackedByteArray).size(), int(cpk["size"])])
		var stump_near := false
		for c in world.get_node("Scatter").get_children():
			if String(c.name).begins_with("stump_of_") and c.global_position.distance_to(nearest.global_position) < 0.5:
				stump_near = true
		check(stump_near, "stump left where the tree stood")
	# 6. stove
	var fuel_before := stove.burner.fuel
	var fed := stove.add_wood_from_player(player)
	check(fed and stove.burner.fuel > fuel_before, "stove fuel increased (%.0f → %.0f)" % [fuel_before, stove.burner.fuel])
	check(fired(&"stove_fueled") >= 1, "stove_fueled fired")
	await frames(2)
	# steps 1 (wood x2) and 2 (stove) are done; the axe was crafted before the stove step so step 3 is now current
	check(player.state.quests.index >= 2, "quest index advanced to >= 2 (got %d)" % player.state.quests.index)
	check(int(player.state.quest_state.get("index", -1)) == player.state.quests.index and fired(&"quest_updated") >= 1, "quest state mirrored to the owner")
	# 7. container: open through the validated request, take, eat, close
	var storage: Storage = cabinet.get_node("Storage")
	var storage_panel: StoragePanel = game.get_node("UI/StoragePanel")
	player.global_position = cabinet.global_position + Vector3(0.6, 0.3, 0.8)
	await frames(3)
	request(&"request_interact", [WorldRegistry.wid_of(cabinet), &"open", 0])
	await frames(2)
	check(storage.is_open and storage.open_by == 1 and storage_panel.visible, "cabinet storage opened by peer 1 (exclusive)")
	request(&"request_take", [WorldRegistry.wid_of(cabinet), 0, false])
	await frames(2)
	check(player.state.count(&"lata_judias") == 1, "took one lata_judias")
	var hunger_before: float = player.state.hunger
	request(&"request_eat_best", [])
	await frames(2)
	check(player.state.hunger > hunger_before, "eat_best increased hunger (%.1f → %.1f)" % [hunger_before, player.state.hunger])
	check(fired(&"item_consumed") >= 1, "item_consumed fired")
	storage_panel.close()
	await frames(2)
	check(not storage.is_open and storage.open_by == 0, "storage closed (server released it)")
	# 8. campfire placement (client pre-check + request_place + PlacedSpawner)
	player.global_position = world.get_spawn_point() + Vector3(0, 0.3, 0)
	await frames(3)
	player.state.inventory.add(&"madera", 3)
	player.state.inventory.add(&"piedra", 4)
	var fog := Recipes.by_id(&"fogata")
	player.placement.begin("campfire", fog)
	check(player.placement.active, "placement mode active")
	var spot := player.global_position + Vector3(0, 0, 4.0)
	spot.y = world.get_height(spot.x, spot.z)
	var placed := player.placement.confirm_at(spot)
	check(placed, "campfire placed")
	check(tree.get_nodes_in_group("campfire").size() >= 1, "campfire in group")
	var campfire: Campfire = tree.get_nodes_in_group("campfire")[0] if tree.get_nodes_in_group("campfire").size() > 0 else null
	check(campfire != null and campfire.is_lit, "campfire is lit")
	check(campfire != null and campfire.get_parent().name == "Placed", "campfire spawned under World/Placed (StructureSpawner)")
	check(campfire != null and NetWorld.instance.chunk_for(WorldRegistry.wid_of(campfire)).structures.has(WorldRegistry.wid_of(campfire)), "placed campfire recorded in the ChunkDelta structures table")
	check(fired(&"campfire_placed") >= 1, "campfire_placed fired")
	if campfire != null:
		player.global_position = campfire.global_position + Vector3(2.0, 0.3, 0)
	await frames(60)
	check(player.state.stats.warmth_rate() > 0.0, "warmth rate positive near campfire (%.2f)" % player.state.stats.warmth_rate())
	# 9. night + wolves
	WorldState.instance.set_time(1, 20.1)
	await frames(30)
	check(fired(&"night_started") >= 1, "night_started fired")
	var wolves := tree.get_nodes_in_group("wolves")
	check(wolves.size() >= 1, "wolves spawned at night: %d" % wolves.size())
	var wolf: Wolf = wolves[0] if wolves.size() > 0 else null
	if wolf != null:
		check(String(wolf.name).begins_with("wolf_") and wolf.get_parent().name == "Actors", "wolf spawned with a replicable name under World/Actors")
		var far := player.global_position + Vector3(10, 0.3, 0)
		far.y = world.get_height(far.x, far.z) + 0.3
		wolf.global_position = far
		await frames(120)
		check(wolf.state in [Wolf.State.STALK, Wolf.State.CHASE, Wolf.State.ATTACK, Wolf.State.FLEE], "wolf state after 120 frames: %s" % Wolf.State.keys()[wolf.state])
		var prints := 0
		for fp in world.footprints.get_children():
			if fp is MeshInstance3D and fp.visible and fp.global_position.distance_to(wolf.global_position) < 12.0:
				prints += 1
		check(wolf.get_node_or_null("FootprintEmitter") != null and prints >= 2, "wolf leaves footprints too (%d near it)" % prints)
		if campfire != null:
			campfire.global_position = wolf.global_position
			await frames(30)
			check(wolf.state == Wolf.State.FLEE, "wolf flees from the campfire (state %s)" % Wolf.State.keys()[wolf.state])
		else:
			check(false, "no campfire to scare the wolf")
		# 10. kill (through DamageResolver: player → animal is never gated)
		var res := DamageResolver.apply(DamageResolver.ref(DamageResolver.Kind.PLAYER, 1), DamageResolver.ref(DamageResolver.Kind.ANIMAL),
			wolf, 999.0, DamageResolver.DamageKind.MELEE_SHARP, WorldState.rules_now(), player)
		await frames(2)
		check(not bool(res["blocked"]) and fired(&"wolf_died") >= 1, "wolf_died fired")
		await seconds(2.0)
		var drops := 0
		for p in tree.get_nodes_in_group("pickup"):
			if p.item_id in [&"carne_cruda", &"piel"]:
				drops += 1
		check(drops >= 2, "wolf drops spawned: %d" % drops)
		check(drops >= 1 and world.get_node("Drops").get_child_count() >= 2, "drops replicated through DropSpawner under World/Drops")
		var any_drop: Node = world.get_node("Drops").get_child(0)
		check(NetWorld.instance.chunk_for(WorldRegistry.wid_of(any_drop)).drops.has(WorldRegistry.wid_of(any_drop)), "drop recorded in the ChunkDelta drops table")
		# 10b. deer through DamageResolver v0 (hunting): knockback, kill flag, meat drops
		var deer_list := tree.get_nodes_in_group("deer")
		if not deer_list.is_empty():
			var deer: Deer = deer_list[0]
			var meat_before := 0
			for p in tree.get_nodes_in_group("pickup"):
				if p.item_id == &"carne_cruda":
					meat_before += 1
			var dres := DamageResolver.apply(DamageResolver.ref(DamageResolver.Kind.PLAYER, 1), DamageResolver.ref(DamageResolver.Kind.ANIMAL),
				deer, 999.0, DamageResolver.DamageKind.MELEE_SHARP, WorldState.rules_now(), player)
			await frames(2)
			var meat_after := 0
			for p in tree.get_nodes_in_group("pickup"):
				if p.item_id == &"carne_cruda":
					meat_after += 1
			check(bool(dres["killed"]) and deer.is_dead() and meat_after >= meat_before + Balance.DEER_MEAT, "deer killed through DamageResolver v0 (+%d meat drops)" % (meat_after - meat_before))
		else:
			check(false, "no deer to hunt")
	# 11. blizzard (server decision → WorldState → client blend)
	var weather: Weather = world.get_node("Weather")
	weather.force_blizzard(5.0)
	await frames(2)
	check(WorldState.weather_now() == &"blizzard", "weather == blizzard")
	check(fired(&"weather_changed") >= 1, "weather_changed fired")
	var dn: DayNight = world.get_node("DayNight")
	var snow_peak := 0.0
	for i in 360:
		await tree.process_frame
		snow_peak = maxf(snow_peak, dn.snow_amount)
	check(WorldState.weather_now() == &"clear", "weather back to clear")
	check(snow_peak > 0.05, "snow_amount rose during the blizzard (%.2f)" % snow_peak)
	# 12. cutaway
	var shelter_before := fired(&"shelter_changed")
	player.global_position = world.cabin.global_position + Vector3(0, 0.6, 0)
	await frames(10)
	check(fired(&"shelter_changed") > shelter_before and player.in_house, "shelter_changed fired, player in house")
	var roof := world.cabin.model.find_child("Roof", true, false)
	check(roof != null and not roof.visible, "roof hidden while inside")
	check(world.cabin.cutaway.is_wall_hidden("WallFront"), "front wall hidden (cutaway)")
	player.global_position = world.get_spawn_point() + Vector3(0, 0.3, 0)
	await frames(10)
	check(roof != null and roof.visible, "roof visible again outside")
	# 12b. chat (channel 1, sanitized) and the PvP gate (DamageResolver reads the rules)
	Chat.instance.send("hola \u0007mundo")
	await frames(2)
	check(_chat_lines.size() >= 1 and _chat_lines[-1][0] == Identity.player_name and _chat_lines[-1][1] == "hola mundo", "chat relayed and sanitized (%s)" % str(_chat_lines))
	request(&"request_hit_player", [1, 10.0])
	await frames(2)
	check(_hit_results.size() >= 1 and bool(_hit_results[-1][1]), "request_hit_player answered with blocked=true (%s)" % str(_hit_results))
	var pve := DamageResolver.ref(DamageResolver.Kind.PLAYER, 1)
	var other := DamageResolver.ref(DamageResolver.Kind.PLAYER, 2)
	check(is_zero_approx(DamageResolver.player_vs_player_mult({"pvp": false, "friendly_fire": "off"}, pve, other, DamageResolver.DamageKind.MELEE_SHARP))
		and is_equal_approx(DamageResolver.player_vs_player_mult({"pvp": false, "friendly_fire": "reduced"}, pve, other, DamageResolver.DamageKind.EXPLOSION), 0.125)
		and is_equal_approx(DamageResolver.player_vs_player_mult({"pvp": true, "friendly_fire": "off"}, DamageResolver.ref(DamageResolver.Kind.PLAYER, 1, "a"), DamageResolver.ref(DamageResolver.Kind.PLAYER, 2, "b"), DamageResolver.DamageKind.BULLET), 1.0),
		"DamageResolver rules: off=0, reduced explosion=0.125, pvp other faction=1")
	# 13. day roll
	WorldState.instance.set_time(1, 5.98)
	await frames(90)
	check(WorldState.instance.day == 2, "day == 2 after roll (got %d)" % WorldState.instance.day)
	check(fired(&"day_started") >= 1, "day_started fired")
	var leaving := true
	for w in tree.get_nodes_in_group("wolves"):
		if w.state != Wolf.State.LEAVE:
			leaving = false
	check(leaving, "wolves leaving at dawn")
	check(player.state.quests.index == 0 and player.state.quests.steps.size() == 4, "quest reset for day 2 (index %d, %d steps)" % [player.state.quests.index, player.state.quests.steps.size()])
	# 13b. persistence: MemoryBackend (offline) holds profiles + dirty chunk deltas after save_all; FileBackend round trip
	var pm: PlayerManager = game.get_node("PlayerManager")
	pm.save_all()
	var saved_delta: ChunkDelta = pm.backend.load_chunk_delta(24, 24)
	check(pm.backend is MemoryBackend and pm.backend.player_count() == 1 and pm.backend.chunk_keys().size() >= 1, "save_all stored %d profile(s) and %d chunk delta(s) in the MemoryBackend" % [pm.backend.player_count(), pm.backend.chunk_keys().size()])
	check(saved_delta != null and not saved_delta.objects.is_empty() and not saved_delta.structures.is_empty(), "chunk (24, 24) delta persisted with objects + structures")
	var fb := FileBackend.new()
	var fpath := "user://smoke_save_test.json"
	fb.open(fpath)
	fb.from_document((pm.backend as MemoryBackend).to_document())
	check(fb.flush() == OK and FileAccess.file_exists(fpath), "FileBackend atomic JSON write")
	var fb2 := FileBackend.new()
	var norm := func(d: Dictionary) -> String: return JSON.stringify(JSON.parse_string(JSON.stringify(d)))
	check(fb2.open(fpath) == OK and fb2.player_count() == 1 and fb2.chunk_keys() == pm.backend.chunk_keys()
		and norm.call(fb2.load_chunk_delta(24, 24).to_dict()) == norm.call(saved_delta.to_dict()), "FileBackend reload == memory store")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fpath))
	# 14. death (persistent world: death screen + respawn instead of game over)
	player.state.warmth = 0.0
	player.state.health = 1.0
	await frames(30)
	check(fired(&"player_died") >= 1, "player_died fired")
	check(player.state.dead and player.dead and player.state.death_cause == &"frio", "dead by frio (cause=%s)" % player.state.death_cause)
	var go: Control = game.get_node("UI/GameOver")
	check(go.visible, "death screen visible")
	GameFlow.request_respawn()
	await frames(5)
	check(not player.dead and fired(&"player_respawned") >= 1 and not go.visible and player.state.health > 50.0, "respawn restores the player at the spawn (health %.0f)" % player.state.health)
	# 15. five days survived (achievement in the persistent world)
	WorldState.instance.set_time(5, 5.98)
	await frames(90)
	check(fired(&"game_won") >= 1, "game_won fired")
	check(GameFlow.best_days >= 5, "best_days saved (%d)" % GameFlow.best_days)
	check(go.visible and WorldState.instance.day == 6, "win screen shown, world keeps running (day %d)" % WorldState.instance.day)
	print("== %d checks, %s" % [_checks, "FAILED" if _failed else "ALL PASSED"])
	tree.quit(1 if _failed else 0)


func multiplayer_id() -> int:
	return tree.get_multiplayer().get_unique_id()


## Walks the local player with a scripted move for `n` frames and measures the skeletal feet in the model frame:
## minimum ankle height and the stance sliding (horizontal speed of the lowest foot vs the body speed).
func _feet_metric(player: Player, move: Vector2, run: bool, n: int) -> Dictionary:
	var visual: CharacterVisual = player.view.visual
	player.input.scripted_move = move
	player.input.scripted_run = run
	await seconds(0.7)   # accelerate + crossfade into the cycle
	var ankle_min := INF
	var stance_speed_sum := 0.0
	var stance_samples := 0
	var body_speed_sum := 0.0
	var body_samples := 0
	var prev_feet := {}
	var prev_pos := Vector3.INF
	var prev_t := 0.0
	var tick_dt := 1.0 / float(Engine.physics_ticks_per_second)
	for i in n:
		# sampled per physics tick (body and AnimationTree both advance there): immune to wall-clock jitter / CPU load
		await tree.physics_frame
		var t := float(Engine.get_physics_frames()) * tick_dt
		var feet := visual.foot_positions()
		var inv := visual.global_transform.affine_inverse()
		for k in ["LeftFoot", "RightFoot"]:
			ankle_min = minf(ankle_min, (inv * (feet[k] as Vector3)).y)
		var pos: Vector3 = player.global_position
		if prev_pos != Vector3.INF:
			var dt := t - prev_t
			if dt > 0.0005:
				var body_v := Vector2(pos.x - prev_pos.x, pos.z - prev_pos.z).length() / dt
				body_speed_sum += body_v
				body_samples += 1
				# stance contact = the lowest of the heel (Foot) / ball (Toes) points while planted (< 0.045 m: the
				# touchdown frame above that is the foot still decelerating, not sliding)
				var lowest := ""
				var lowest_y := INF
				for k in ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]:
					var y := (inv * (feet[k] as Vector3)).y
					if y < lowest_y:
						lowest_y = y
						lowest = k
				if lowest_y < 0.045 and prev_feet.has(lowest):
					var fv := Vector2((feet[lowest] as Vector3).x - (prev_feet[lowest] as Vector3).x, (feet[lowest] as Vector3).z - (prev_feet[lowest] as Vector3).z).length() / dt
					stance_speed_sum += fv
					stance_samples += 1
		prev_feet = feet
		prev_pos = pos
		prev_t = t
	var body_speed := body_speed_sum / maxf(body_samples, 1.0)
	var stance_speed := stance_speed_sum / maxf(stance_samples, 1.0)
	return {"ankle_min": ankle_min, "sliding": stance_speed / maxf(body_speed, 0.01) * 100.0, "body_speed": body_speed,
		"stance_samples": stance_samples}
