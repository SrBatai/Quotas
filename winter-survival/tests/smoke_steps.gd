extends RefCounted
## Smoke test body (loaded at runtime by tests/smoke_test.gd so autoloads exist when it compiles).
## M1: offline = the authoritative local server runs in this process (OfflineMultiplayerPeer, peer 1); every
## gameplay action goes through the validated NetWorld requests, exactly like a networked client would.
## M2: skeletal survivor (feet metric: ankle >= 0.08 m, sliding < 5 %), action-based interaction, ChunkDelta,
## DropSpawner / StructureSpawner, DamageResolver v0 on wolves and deer, persistence backends.
## M3: 3 km world in 64 m chunks (WorldConst, HeightFunction, macro map, streamer rings), the slice clearing kept
## exactly (legacy scatter port), MultiMesh trees choppable by index (materialized on request), big lake, road
## beds, regions per chunk, world border, teleport far + back (felled tree survives an unload), trail map follows.

var tree: SceneTree

var _failed: bool = false
var _checks: int = 0
var _signals: Dictionary = {}
var _chat_lines: Array = []
var _hit_results: Array = []
var _felled_wid: int = 0
var _felled_pos: Vector3 = Vector3.ZERO


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
	# M4: the 20 s respawn wait (Balance.RESPAWN_DELAY) is shortened for the scripted deaths below
	StatsComponent.respawn_delay = 0.2
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
	var under := world.streamer.loaded_chunk_at(player.global_position.x, player.global_position.z)
	var hm: HeightMapShape3D = under.terrain_body.get_child(0).shape if under != null and under.terrain_body != null else null
	check(hm != null and hm.map_width == WorldConst.SAMPLES and hm.map_depth == WorldConst.SAMPLES, "terrain collision under the player: chunk %s HeightMapShape3D %dx%d" % [under.name if under != null else "-", hm.map_width if hm != null else 0, hm.map_depth if hm != null else 0])
	var ring1_ok := true
	for k in WorldConst.ring_keys(WorldConst.CENTER_CHUNK, WorldConst.CENTER_CHUNK, 1):
		if not world.streamer.chunks.has(k) or (world.streamer.chunks[k] as WorldChunk).state != WorldChunk.State.LOADED:
			ring1_ok = false
	check(ring1_ok, "clearing chunks 23–25 loaded synchronously before the spawn (%d chunks loaded)" % world.streamer.loaded_keys().size())
	check(world.cabin != null, "cabin exists")
	var stove: WoodStove = world.cabin.get_node("Stove")
	check(stove != null and stove.is_lit, "stove exists and is lit")
	var cabinet := world.cabin.get_node("Cabinet")
	check(cabinet != null, "cabinet exists")
	check(world.scatter_tree_count() >= 200, "choppable scatter trees (MultiMesh entries) in the loaded chunks: %d" % world.scatter_tree_count())
	check(tree.get_nodes_in_group("tree").size() < 20, "trees are not nodes until needed (%d materialized)" % tree.get_nodes_in_group("tree").size())
	check(tree.get_nodes_in_group("pickup").size() >= 1, "pickups exist: %d" % tree.get_nodes_in_group("pickup").size())
	var clearing: Array = ScatterGen.clearing_entries(world.seed_value)
	var e0: Dictionary = clearing[0]
	check(clearing.size() == 723 and ScatterCatalog.name_of(int(e0["v"])) == "pine_b" and absf(float(e0["x"]) - 13.100) < 0.001 and absf(float(e0["z"]) - 75.295) < 0.001
		and absf(float(e0["yaw"]) - 3.2761) < 0.0001, "slice clearing scatter ported exactly (%d entries, first %s at %.3f, %.3f)" % [clearing.size(), ScatterCatalog.name_of(int(e0["v"])), float(e0["x"]), float(e0["z"])])
	var f0 := world.nearest_scatter(world.get_spawn_point(), "pine", 1)
	var t0: ChoppableTree = (f0[0] as WorldChunk).materialize(int(f0[1])) if not f0.is_empty() else null
	check(t0 != null and WorldRegistry.get_object(WorldRegistry.wid_of(t0)) == t0 and WorldRegistry.wid_of(t0) == int((f0[0] as WorldChunk).data.entries[int(f0[1])]["wid"]),
		"a MultiMesh tree materializes on demand with its deterministic wid (hash64) registered")
	if t0 != null:
		(f0[0] as WorldChunk).dematerialize(int(f0[1]))
	check(t0 == null or not is_instance_valid(t0), "an untouched materialized tree goes back to the MultiMesh")
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
	# G1 survivors: Loco_Run bottoms out at 0.082 m after import (v2.1 retarget), so the run clip meets the 0.08 m rule too
	check(feet_run["ankle_min"] >= 0.08 and feet_run["sliding"] < 5.0, "run feet metric: ankle min %.3f m >= 0.08, sliding %.1f %% < 5 %% (body %.2f m/s, %d stance samples)" % [feet_run["ankle_min"], feet_run["sliding"], feet_run["body_speed"], feet_run["stance_samples"]])
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
	# 5. chop the nearest pine through the validated request (distance + tool checked on the server). M3: trees
	# are MultiMesh entries; the server materializes the one a request names (WorldRegistry.resolve).
	var fnear := world.nearest_scatter(player.global_position, "pine", 1)
	var nchunk: WorldChunk = fnear[0] if not fnear.is_empty() else null
	var nidx: int = fnear[1] if not fnear.is_empty() else -1
	var wid: int = int(nchunk.data.entries[nidx]["wid"]) if nchunk != null else 0
	var tree_pos: Vector3 = nchunk.entry_position(nidx) if nchunk != null else Vector3.ZERO
	check(nchunk != null and WorldRegistry.get_object(wid) == null, "found a MultiMesh pine to chop (entry %d of %s, not a node yet)" % [nidx, nchunk.name if nchunk != null else "-"])
	if nchunk != null:
		var far := tree_pos + Vector3(12.0, 0.3, 0)
		far.y = world.get_height(far.x, far.z) + 0.3
		player.global_position = far
		await frames(3)
		request(&"request_interact", [wid, &"chop", 0])
		await frames(2)
		var nearest := WorldRegistry.get_object(wid) as ChoppableTree
		check(nearest != null and nearest.hits == 0 and nearest.scatter_chunk == nchunk, "far request_interact: the server materialized the tree and rejected the hit (hits=%d)" % (nearest.hits if nearest != null else -1))
		var side := (player.global_position - tree_pos)
		side.y = 0.0
		side = side.normalized() * 1.5
		player.global_position = tree_pos + side + Vector3(0, 0.3, 0)
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
		check(cd != null and cd.objects.has(wid) and cd.cx >= 23 and cd.cx <= 25 and cd.cz >= 23 and cd.cz <= 25 and cd.is_dirty() and cd.key() == nchunk.key, "delta stored in the tree's own ChunkDelta (%d, %d) of the clearing, dirty" % [cd.cx, cd.cz])
		var cpk := cd.pack()
		var cback := ChunkDelta.unpack(int(cpk["size"]), cpk["bytes"])
		check(not cback.is_empty() and (cback["objects"] as Dictionary).has(wid) and bool(cback["objects"][wid]["felled"]) and (cpk["bytes"] as PackedByteArray).size() < int(cpk["size"]), "CHUNK_DELTA pack/unpack round trip (%d B zstd of %d)" % [(cpk["bytes"] as PackedByteArray).size(), int(cpk["size"])])
		await seconds(1.6)   # the fall animation frees the tree node after ≈ 1.3 s
		check(_stump_near(world, tree_pos, wid), "stump left where the tree stood")
		check(bool(nchunk.data.entries[nidx]["felled"]) and nchunk.removed[nidx] == 1 and NetWorld.instance.felled.has(wid) and WorldRegistry.get_object(wid) == null,
			"scatter entry marked felled (instance hidden, shape disabled, NetWorld.felled, node freed)")
		_felled_wid = wid
		_felled_pos = tree_pos
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
		var prints := world.footprints.count_near(wolf.global_position, 12.0)
		check(wolf.get_node_or_null("FootprintEmitter") != null and prints >= 2, "wolf leaves footprints too (%d near it, trail map backend %s)" % [prints, world.footprints.backend])
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
	await seconds(0.3)
	GameFlow.request_respawn()
	await frames(5)
	check(not player.dead and fired(&"player_respawned") >= 1 and not go.visible and player.state.health > 50.0, "respawn restores the player at the spawn (health %.0f)" % player.state.health)
	# 15. five days survived (achievement in the persistent world)
	WorldState.instance.set_time(5, 5.98)
	await frames(90)
	check(fired(&"game_won") >= 1, "game_won fired")
	check(GameFlow.best_days >= 5, "best_days saved (%d)" % GameFlow.best_days)
	check(go.visible and WorldState.instance.day == 6, "win screen shown, world keeps running (day %d)" % WorldState.instance.day)
	# 16. M3 — open world by chunks (PLAN M3)
	await _m3_checks(world, player)
	# 17. M4 — zombies, navigation, melee, downed / revive / death / corpse (PLAN M4)
	await _m4_checks(game, world, player)
	print("== %d checks, %s" % [_checks, "FAILED" if _failed else "ALL PASSED"])
	tree.quit(1 if _failed else 0)


func _m3_checks(world: World, player: Player) -> void:
	var hf := world.hf
	var st := world.streamer
	# grid + hashing
	check(WorldConst.WORLD_CHUNKS == 48 and WorldConst.CHUNK_SIZE == 64.0 and WorldConst.chunk_of(0.0) == 24 and WorldConst.chunk_of(-31.9) == 24
		and WorldConst.chunk_of(32.1) == 25 and WorldConst.key_cx(WorldConst.key(47, 3)) == 47 and WorldConst.key_cz(WorldConst.key(47, 3)) == 3,
		"WorldConst: 48 × 48 chunks of 64 m, chunk 24 centred on the origin, key round trip")
	var h1 := WorldConst.hash64(1337, 101, -5, 7, 0)
	check(h1 == WorldConst.hash64(1337, 101, -5, 7, 0) and h1 != WorldConst.hash64(1337, 101, -5, 8, 0) and h1 >= 0, "hash64 deterministic, 63-bit (%d)" % h1)
	# height function: clearing untouched by the macro, big lake, road beds, border
	check(hf.macro.ok and hf.macro.height_rel(50.0, -60.0) == 0.0 and hf.macro.height_rel(-100.0, 90.0) == 0.0 and hf.macro.height_rel(900.0, 300.0) != 0.0, "macro map loaded; exactly 0 around the clearing")
	var lake_ok := true
	for q in [Vector2(-760, 380), Vector2(-700, 300), Vector2(-660, 520), Vector2(-900, 450)]:
		if absf(hf.height_at(q.x, q.y) - PoiRegistry.LAKE_LEVEL) > 0.001 or hf.surface_at(q.x, q.y).g8 < 250 or not world.terrain.is_lake(q.x, q.y):
			lake_ok = false
	check(lake_ok, "Lago de las Ánimas: flat ice at %.1f m (surface mask ice)" % PoiRegistry.LAKE_LEVEL)
	var rp := Vector2(646, -240)
	var rdir := (Vector2(662, -60) - rp).normalized()
	var rh0 := hf.height_at(rp.x, rp.y)
	var rh1 := hf.height_at(rp.x + rdir.x * 2.0, rp.y + rdir.y * 2.0)
	check(hf.surface_at(rp.x, rp.y).r8 > 200 and absf(rh1 - rh0) < 0.3 and hf.road_distance(rp.x, rp.y, 10.0, "highway") < 0.0, "N‑140 road bed: asphalt mask, smooth profile (%.2f m over 2 m)" % absf(rh1 - rh0))
	check(hf.height_at(1400.0, 0.0) > hf.height_at(0.0, 0.0) + 40.0, "border mountains rise at the world edge (%.0f m)" % hf.height_at(1400.0, 0.0))
	# regions per chunk (+ the slice's small zones inside the clearing)
	var names := [Regions.name_at(0, 0), Regions.name_at(-21, -13), Regions.name_at(-760, 380), Regions.name_at(646, -240), Regions.name_at(1400, 100), Regions.name_at(176, -512)]
	check(names == ["CLARO", "CABAÑA DEL PESCADOR", "LAGO DE LAS ÁNIMAS", "N-140", "LAS CUMBRES", "VALDENIEVE"], "regions by chunk: %s" % [names])
	# a client-side chunk build (headless runs have no meshes): mesh arrays, CUSTOM0 mask, baked AO, MultiMesh buffers
	var job := ChunkJob.new()
	job.cx = 24
	job.cz = 24
	job.key = WorldConst.key(24, 24)
	job.hf = hf
	job.visual = true
	job.clearing = ScatterGen.clearing_entries(world.seed_value)
	job.run()
	var ao_min := 1.0
	for a in job.ao:
		ao_min = minf(ao_min, a)
	var instances := 0
	for mk in job.mm_keys:
		instances += (job.mm[mk]["idx"] as PackedInt32Array).size()
	check(job.verts.size() == 65 * 65 and job.custom.size() == 65 * 65 * 4 and job.normals.size() == 65 * 65 and ao_min < 0.8 and instances > 50 and job.mm_keys.size() >= 8,
		"visual chunk data: 4225 verts, CUSTOM0 RGBA8, AO baked (min %.2f), %d MultiMesh instances in %d blocks×variants (%d ms)" % [ao_min, instances, job.mm_keys.size(), job.usec / 1000])
	var lake_job := ChunkJob.new()
	lake_job.cx = WorldConst.chunk_of(-760.0)
	lake_job.cz = WorldConst.chunk_of(380.0)
	lake_job.key = WorldConst.key(lake_job.cx, lake_job.cz)
	lake_job.hf = hf
	lake_job.visual = true
	lake_job.run()
	var ice := 0
	for k in 65 * 65:
		if lake_job.custom[k * 4 + 1] > 200:
			ice += 1
	check(ice > 3000 and lake_job.region == "LAGO DE LAS ÁNIMAS", "lake chunk: %d ice samples in CUSTOM0.g, region %s" % [ice, lake_job.region])
	# streaming around the player: ring 2 (5 × 5) loaded, main-thread steps inside the budget
	var waited := 0
	while not st.is_idle() and waited < 600:
		await tree.process_frame
		waited += 1
	check(st.loaded_keys().size() == 25, "ring 2 (5 × 5) streamed around the player: %d chunks after %d frames" % [st.loaded_keys().size(), waited])
	# every step fits the 2 ms budget; one isolated stall (VM page fault / preemption, < 8 ms) is tolerated as in
	# perf_budgets.json "perf_walk_cpu"
	var smax := int(st.stats["step_usec_max"])
	var sover := int(st.stats["steps_over_budget"])
	check(smax < WorldConst.STREAM_BUDGET_USEC or (sover <= 1 and smax < 8000), "streaming steps within the 2 ms/frame budget (%d steps, %d over, max step %d µs %s, gen max %d µs in workers)" % [int(st.stats["steps"]), sover, smax, st.stats.get("step_max_by_kind", {}), int(st.stats["gen_usec_max"])])
	# hover pick through a tree crown (the ray misses the trunk collider): materializes that tree
	var fp := world.nearest_scatter(player.global_position, "pine", 1)
	if not fp.is_empty():
		var tp: Vector3 = (fp[0] as WorldChunk).entry_position(fp[1])
		var from := tp + Vector3(0.0, 20.0, 12.0)
		var picked := world.pick_scatter(from, (tp + Vector3(0.0, 3.5, 0.0) - from).normalized(), tp + Vector3(0.0, 0.0, -3.0))
		check(picked != null and picked.global_position.distance_to(tp) < 0.01, "cursor ray through a crown picks (materializes) that MultiMesh tree")
	# teleport 1 km away onto the lake (debug /tp): synchronous load, standing on the ice, banner, clearing unloaded
	var region_now := [""]   # lambdas capture locals by value: a reference holder
	var rc := func(n: String) -> void: region_now[0] = n
	Events.region_changed.connect(rc)
	Chat.instance.send("/tp -760 380")
	await frames(3)
	check(player.global_position.distance_to(Vector3(-760, PoiRegistry.LAKE_LEVEL, 380)) < 1.0 and st.loaded_chunk_at(-760, 380) != null, "teleported 900 m onto the lake: its chunk loaded synchronously (y %.2f)" % player.global_position.y)
	await seconds(1.0)
	check(player.is_on_floor() and absf(player.global_position.y - PoiRegistry.LAKE_LEVEL) < 0.2, "standing on the flat lake ice (y %.2f)" % player.global_position.y)
	check(region_now[0] == PoiRegistry.REGION_LAKE, "region banner from the chunk data: %s" % region_now[0])
	# walk east across a chunk seam: no fall, no bump
	var seam := WorldConst.chunk_origin(WorldConst.chunk_of(player.global_position.x) + 1, 0).x
	player.global_position = Vector3(seam - 3.0, PoiRegistry.LAKE_LEVEL + 0.2, 380.0)
	await frames(10)
	player.input.scripted_move = Vector2(1, 0)
	var y_min := INF
	var y_max := -INF
	var floor_all := true
	for i in 150:
		await tree.physics_frame
		if i > 10:
			y_min = minf(y_min, player.global_position.y)
			y_max = maxf(y_max, player.global_position.y)
			floor_all = floor_all and player.is_on_floor()
	player.input.scripted_move = Vector2.INF
	check(player.global_position.x > seam + 1.0 and floor_all and y_max - y_min < 0.05, "walked across the chunk seam at x=%.0f on the ice (Δy %.3f m, always on floor)" % [seam, y_max - y_min])
	check(world.footprints == null or (world.footprints.rect.has_point(Vector2(player.global_position.x, player.global_position.z)) and world.footprints.count_near(player.global_position, 6.0) >= 2),
		"snow trail map re-projected with the player 900 m away (%d prints near it)" % (world.footprints.count_near(player.global_position, 6.0) if world.footprints != null else -1))
	waited = 0
	while (st.chunks.has(WorldConst.key(24, 24)) or not st.is_idle()) and waited < 900:
		await tree.process_frame
		waited += 1
	check(not st.chunks.has(WorldConst.key(24, 24)) and st.loaded_keys().size() <= 35 and int(st.stats["unloaded"]) >= 20, "the clearing unloaded behind the player (%d loaded incl. the 1-chunk hysteresis, %d unloaded)" % [st.loaded_keys().size(), int(st.stats["unloaded"])])
	# back home: the felled tree is still felled after its chunk was unloaded and rebuilt from the delta
	Chat.instance.send("/tp %.2f %.2f" % [world.get_spawn_point().x, world.get_spawn_point().z])
	await frames(5)
	check(_felled_wid != 0 and _stump_near(world, _felled_pos, _felled_wid), "back in the clearing: the felled pine is a stump again (chunk rebuilt from its delta)")
	var fc := world.streamer.chunk_at(_felled_pos.x, _felled_pos.z)
	check(fc != null and fc.wid_index.has(_felled_wid) and fc.removed[fc.wid_index[_felled_wid]] == 1, "…and its MultiMesh instance / collider stay removed")
	# server hibernation of a chunk nobody is near: its ChunkDelta keeps the drop, the node goes away and comes back
	var nw := NetWorld.instance
	if nw != null and DropSpawner.instance != null:
		var hp := Vector3(300.0, 0.0, -900.0)
		hp.y = world.get_height(hp.x, hp.z) + 0.3
		var hk := WorldConst.key(WorldConst.chunk_of(hp.x), WorldConst.chunk_of(hp.z))
		var hdrop := DropSpawner.instance.spawn_drop(&"madera", "firewood", hp)
		var hname := String(hdrop.name)
		var hwid := WorldRegistry.wid_of(hdrop)
		nw.hibernate_chunk(hk)
		await frames(2)
		var gone := DropSpawner.instance.drops_root().get_node_or_null(hname) == null
		var kept := nw.chunk_for(hwid).drops.has(hwid)
		nw.wake_chunk(hk)
		await frames(1)
		var back := DropSpawner.instance.drops_root().get_node_or_null(hname) as Node3D
		check(gone and kept and nw.is_hibernated(hk) == false and back != null and back.global_position.distance_to(hp) < 0.01,
			"chunk hibernation: drop despawned with its delta kept (%s, %s), restored on wake (%s)" % [gone, kept, back != null])
		if back != null:
			nw.erase_drop(WorldRegistry.wid_of(back))
			back.queue_free()
	# world border
	check(not world.terrain.in_bounds(WorldConst.WALL + 5.0, 0.0) and world.get_node("Bounds").get_child_count() == 4, "world wall at ±%.0f m" % WorldConst.WALL)
	Chat.instance.send("/tp 1460 60")
	await seconds(1.0)
	player.input.scripted_move = Vector2(1, 0)
	await seconds(1.0)
	player.input.scripted_move = Vector2.INF
	var dn := world.get_node_or_null("DayNight") as DayNight
	check(player.global_position.x < WorldConst.WALL and (dn == null or dn.fog_density_scale > 2.0), "the border stops the player (x %.1f) and the fog thickens (×%.1f)" % [player.global_position.x, dn.fog_density_scale if dn != null else 0.0])
	Events.region_changed.disconnect(rc)
	Chat.instance.send("/tp %.2f %.2f" % [world.get_spawn_point().x, world.get_spawn_point().z])
	await frames(5)


func _m4_checks(game: Node, world: World, player: Player) -> void:
	var sys := ZombieSystem.instance
	var zc := ZombieClient.instance
	check(sys != null and sys.nav != null and ZombieNet.instance != null and zc != null and CombatFx.instance != null
		and PopulationManager.instance != null and Director.instance != null, "M4 systems: ZombieSystem + NavBaker + ZombieNet (server), ZombieClient + CombatFx (client), population, director")
	if sys == null or zc == null:
		return
	# deterministic conditions: the director and the residents only where they are tested, clear weather
	Director.instance.enabled = false
	PopulationManager.instance.enabled = false
	var weather: Weather = world.get_node("Weather")
	weather.scheduler_enabled = false
	weather.cancel()
	sys.clear_all()
	WorldState.instance.set_time(WorldState.instance.day, 11.0)
	StatsComponent.solo_getup_time = 1.0
	player.state.stats.reset_stats()
	player.global_position = world.get_spawn_point() + Vector3(0, 0.3, 0)
	await frames(5)
	# -- navigation: per-chunk navmesh around the clearing; a route from behind the cabin to the porch goes round it
	var baked := sys.nav.bake_now(player.global_position, 1)
	var cab := world.cabin.global_position
	var behind := cab + Vector3(0.5, 0.0, -8.0)
	behind.y = world.get_height(behind.x, behind.z)
	var porch := world.get_spawn_point()
	# NavigationServer3D applies region meshes asynchronously (region async iterations): wait for the map to
	# pick up the fresh regions (a few physics frames) before asking for the route
	var route := PackedVector3Array()
	for k in 120:
		await tree.physics_frame
		route = NavigationServer3D.map_get_path(sys.nav.map, behind, porch, true)
		if route.size() >= 3:
			break
	var route_len := 0.0
	var through := false
	for k in route.size():
		if k > 0:
			route_len += route[k - 1].distance_to(route[k])
			for f in 8:
				var q := route[k - 1].lerp(route[k], float(f) / 8.0) - cab
				if absf(q.x) < 2.6 and q.z > -2.2 and q.z < 2.2:
					through = true
	# regions meet on the chunk seams (Recast border outside the chunk): a route from one chunk into the next
	var seam_x := WorldConst.chunk_origin(WorldConst.chunk_of(cab.x) - 1, 0).x + WorldConst.CHUNK_SIZE
	var sa := Vector3(seam_x - 8.0, 0.0, cab.z - 20.0)
	var sb := Vector3(seam_x + 12.0, 0.0, cab.z - 20.0)
	sa.y = world.get_height(sa.x, sa.z)
	sb.y = world.get_height(sb.x, sb.z)
	var cross := NavigationServer3D.map_get_path(sys.nav.map, sa, sb, true)
	check(cross.size() >= 2 and cross[cross.size() - 1].distance_to(sb) < 1.5,
		"a route crosses the chunk seam at x=%.0f (ends %.2f m from the goal)" % [seam_x, cross[cross.size() - 1].distance_to(sb) if cross.size() > 0 else -1.0])
	check(sys.nav.regions.size() >= 9 and route.size() >= 3 and route_len > behind.distance_to(porch) + 1.5 and not through,
		"navmesh baked per chunk (%d regions, %d baked now, max %d ms); route behind the cabin → porch: %d points, %.1f m vs %.1f m straight, never through the walls" % [
		sys.nav.regions.size(), baked, int(sys.nav.stats["bake_usec_max"]) / 1000, route.size(), route_len, behind.distance_to(porch)])
	# -- weapons (M4 table, models from weapons/ when delivered) + durability in the slot mirror
	await seconds(1.05)   # chat rate limit (2 lines/s): the M3 teleports were just sent
	Chat.instance.send("/armas")
	await frames(3)
	check(player.state.count(&"cuchillo") == 1 and player.state.count(&"bate") == 1 and player.state.count(&"palanca") == 1 and player.state.count(&"machete") == 1,
		"/armas: knife, crowbar, bat, machete in the inventory")
	_equip(player, &"bate")
	await frames(3)
	check(player.state.hand_tool() == &"bate" and int(player.state.slots[0].get("dur", -1)) == 100 and player.tool_holder.tool_model != null,
		"bat in hand, durability 100 in the slot (4-byte mirror), weapon model on the RightHandSocket")
	var packed := Packets.pack_slots(player.state.slots)
	var back := Packets.unpack_slots(packed)
	check(packed.size() == Packets.SLOT_SIZE * player.state.slots.size() and int(back[0].get("dur", -1)) == 100, "slot mirror round trip keeps the durability (%d B)" % packed.size())
	# -- spawn 20 zombies around the player (debug command), replication to the local client, LOD bodies
	var before_spawn := int(sys.stats["spawned"])
	await seconds(1.05)
	Chat.instance.send("/zombies 20 walker 24")
	await frames(3)
	check(sys.count_alive() >= 18 and int(sys.stats["spawned"]) - before_spawn >= 18, "/zombies 20: %d walkers spawned around the player" % sys.count_alive())
	await seconds(1.2)
	check(zc.records.size() >= 15 and zc.packets > 0 and zc.snap_entries > 0, "zombies replicated to the local client: %d records, %d packets, %d snapshot entries" % [zc.records.size(), zc.packets, zc.snap_entries])
	check(sys.bodies_in_use() >= 15 and sys.l0.size() >= 15, "L0 zombies got pooled CharacterBody3D bodies (%d bodies)" % sys.bodies_in_use())
	check(zc.views_in_use() >= 8, "client views assigned from the pool (%d in use, pool %d)" % [zc.views_in_use(), zc.pool_size])
	var zv: ZombieView = null
	for v in zc.views:
		if v.visible and v.id != 0:
			zv = v
			break
	check(zv != null and zv.is_skeletal and zv.tree.active and zv.anim_player.get_animation_list().size() > 5,
		"zombie view: skeletal model %s, AnimationTree active (%d clips, Zom_* delivered: %s)" % [zv.model.name if zv != null and zv.model != null else "-",
		zv.anim_player.get_animation_list().size() if zv != null else 0, zv.has_zom_clips if zv != null else false])
	if Assets.has_model("zombies/zombie_walker_01") and ResourceLoader.exists(ZombieView.ZOM_LIB):
		# art contract (ASSET_SPEC v2 M4): the delivered bodies + zombie_anims.glb, no generated stand-ins needed
		var real := 0
		for v in zc.views:
			if v.visible and v.id != 0 and not v.is_placeholder_model and v.has_zom_clips and v.anim_player.has_animation("z/Zom_Shamble_A") and not v.anim_player.has_animation("z/Gen_Arms"):
				real += 1
		check(real >= 8, "zombie views use zombies/zombie_walker_NN.glb + zombie_anims.glb clips (%d views, no Gen_* stand-ins)" % real)
	check(is_equal_approx(Weapons.hit_delay(&"bate", Weapons.Mode.LIGHT), AnimEvents.at("Melee2H_Swing_A", "hit_start", -1.0)) and AnimEvents.has("Zom_Grab", "bite_1")
		and is_equal_approx(ZombieSystem.attack_windup(ZombieKinds.Kind.WALKER, 0), AnimEvents.at("Zom_Attack_A", "hit_start", -1.0)),
		"data/anim_events.json: '-loop' keys normalised; bat blow at %.2f s, Zom_Attack_A window at %.2f s" % [Weapons.hit_delay(&"bate", Weapons.Mode.LIGHT), ZombieSystem.attack_windup(ZombieKinds.Kind.WALKER, 0)])
	# sight is probabilistic (distance, light, the 120° cone, the cabin in the way): up to 6 s for three of them
	var chasing := 0
	var waited_s := 0.0
	while waited_s < 6.0:
		await seconds(0.5)
		waited_s += 0.5
		chasing = sys.count_state(ZombieKinds.State.CHASE) + sys.count_state(ZombieKinds.State.ATTACK)
		if chasing >= 3 and waited_s >= 2.5:
			break
	check(chasing >= 3, "zombies saw the player and chase it (%d chasing / attacking after %.1f s)" % [chasing, waited_s])
	var moved := 0
	for i in sys.l0:
		if sys.used[i] == 1 and sys.pos[i].distance_to(sys.home[i]) > 1.0:
			moved += 1
	check(moved >= 3 and int(sys.queue.stats["queries"]) + int(sys.queue.stats["shared"]) >= 1, "chasers move along navmesh routes (%d moved, %d route queries, %d shared)" % [moved, int(sys.queue.stats["queries"]), int(sys.queue.stats["shared"])])
	# -- kill one with the bat (validated melee: cone, reach, stamina, noise, blood, same death on the client)
	sys.clear_all()
	await frames(2)
	var t := _spawn_front(sys, player, ZombieKinds.Kind.WALKER, 1.3)
	var tid := sys.net_id[t]
	await seconds(0.7)
	var noise0 := SoundEvents.emitted
	var blood0 := CombatFx.instance.blood_spawned
	var stam0: float = player.state.stamina
	var hits := 0
	var bat_delay := Weapons.hit_delay(&"bate", Weapons.Mode.LIGHT)
	for k in 8:
		if not sys.is_alive(t):
			break
		_hold_zombie(sys, t, player, 1.3)
		player.melee_ready_at = 0.0
		var hp_before := sys.hp[t]
		request(&"request_melee", [Weapons.Mode.LIGHT, _yaw_to(player, sys.pos[t]), tid])
		hits += 1
		if k == 0 and bat_delay > 0.1:
			await frames(2)
			check(is_equal_approx(sys.hp[t], hp_before), "the swing is accepted but the blow waits for the clip's hit_start (%.2f s)" % bat_delay)
		await seconds(bat_delay + 0.1)
		_hold_zombie(sys, t, player, 1.3)
	await frames(10)
	check(not sys.is_alive(t) and sys.state[t] == ZombieKinds.State.DEAD, "a walker (100 PV) dies to the bat in %d swings" % hits)
	check(zc.died_ids.has(tid) and zc.record(tid) != null and zc.record(tid).state == ZombieKinds.State.DEAD, "the client saw the same zombie (id %d) die" % tid)
	check(SoundEvents.emitted > noise0 and int(zc.fx_count.get(ZombieNet.FX_NOISE, 0)) >= 1 and CombatFx.instance.rings_spawned >= 1,
		"melee made noise: %d SoundEvents, the ring reached the client (%d rings)" % [SoundEvents.emitted - noise0, CombatFx.instance.rings_spawned])
	check(CombatFx.instance.blood_spawned > blood0, "blood decals on the snow (%d)" % (CombatFx.instance.blood_spawned - blood0))
	check(player.state.stamina < stam0, "swings cost stamina (%.0f → %.0f)" % [stam0, player.state.stamina])
	# -- friendly fire off: the bat swing through a teammate position hurts nobody (no teammate offline: rules check)
	check(DamageResolver.blocked_pvp >= 0 and is_zero_approx(DamageResolver.player_vs_player_mult({"friendly_fire": "off"}, DamageResolver.ref(DamageResolver.Kind.PLAYER, 1), DamageResolver.ref(DamageResolver.Kind.PLAYER, 2), DamageResolver.DamageKind.MELEE_BLUNT)),
		"friendly_fire=off blocks player→player melee (DamageResolver)")
	# -- a frozen zombie ignores a quiet player, wakes by a loud noise within 8 m
	var fz := _spawn_front(sys, player, ZombieKinds.Kind.FROZEN, 5.0, ZombieKinds.State.FROZEN)
	var fid := sys.net_id[fz]
	await seconds(0.8)
	check(sys.state[fz] == ZombieKinds.State.FROZEN and sys.body[fz] == null, "frozen zombie stays frozen (no body) while the player is quiet 5 m away")
	var wake0 := int(zc.events.get(ZombieSystem.EVT_WAKE, 0))
	SoundEvents.emit(player.global_position, 20.0, 2, SoundEvents.Kind.OTHER, 1)
	await seconds(0.6)
	check(sys.state[fz] in [ZombieKinds.State.WAKING, ZombieKinds.State.INVESTIGATE, ZombieKinds.State.CHASE, ZombieKinds.State.ATTACK] and int(zc.events.get(ZombieSystem.EVT_WAKE, 0)) > wake0,
		"a 20 m noise 5 m away wakes the frozen zombie (%s, wake event on the client)" % ZombieKinds.State.keys()[sys.state[fz]])
	await seconds(Balance.ZOMBIE_WAKE_TIME + 0.4)
	check(sys.state[fz] in [ZombieKinds.State.CHASE, ZombieKinds.State.INVESTIGATE, ZombieKinds.State.ATTACK], "…and then comes for the player (%s)" % ZombieKinds.State.keys()[sys.state[fz]])
	sys.release(fz)
	# -- silent knife execution of a frozen one
	_equip(player, &"cuchillo")
	var ex := _spawn_front(sys, player, ZombieKinds.Kind.FROZEN, 1.1, ZombieKinds.State.FROZEN)
	await frames(10)
	var noise1 := SoundEvents.emitted
	player.melee_ready_at = 0.0
	request(&"request_melee", [Weapons.Mode.EXECUTE, _yaw_to(player, sys.pos[ex]), sys.net_id[ex]])
	await seconds(Weapons.hit_delay(&"cuchillo", Weapons.Mode.EXECUTE) + 0.15)
	check(not sys.is_alive(ex) and SoundEvents.emitted == noise1, "knife execution kills a frozen zombie silently at the stab (%.2f s, no SoundEvent)" % Weapons.hit_delay(&"cuchillo", Weapons.Mode.EXECUTE))
	# -- shove (stagger or knockdown) then stomp the knocked one
	var sv := _spawn_front(sys, player, ZombieKinds.Kind.WALKER, 1.2)
	await seconds(0.5)
	var knocked := false
	for k in 8:
		_hold_zombie(sys, sv, player, 1.2)
		player.melee_ready_at = 0.0
		player.state.stamina = Balance.STAMINA_MAX
		request(&"request_melee", [Weapons.Mode.SHOVE, _yaw_to(player, sys.pos[sv]), sys.net_id[sv]])
		await seconds(Weapons.hit_delay(&"", Weapons.Mode.SHOVE) + 0.08)
		if k == 0:
			check(sys.state[sv] in [ZombieKinds.State.STAGGER, ZombieKinds.State.KNOCKED], "a shove staggers or knocks down (%s)" % ZombieKinds.State.keys()[sys.state[sv]])
		if sys.state[sv] == ZombieKinds.State.KNOCKED:
			knocked = true
			break
		await seconds(0.7)
	check(knocked, "a shove knocks the zombie down (35 %% per shove)")
	if knocked:
		player.melee_ready_at = 0.0
		var heads0 := CombatFx.instance.heads_popped
		var sv_id := sys.net_id[sv]
		request(&"request_melee", [Weapons.Mode.STOMP, _yaw_to(player, sys.pos[sv]), sys.net_id[sv]])
		await seconds(Weapons.hit_delay(&"", Weapons.Mode.STOMP) + 0.12)
		check(not sys.is_alive(sv), "stomp on the knocked-down zombie kills it")
		var svr := zc.record(sv_id)
		var popped := svr != null and svr.view != null and svr.view.is_skeletal and svr.view.skeleton.get_bone_pose_scale(svr.view.skeleton.find_bone("Head")).x < 0.01
		check(CombatFx.instance.heads_popped > heads0 and (popped or svr == null or svr.view == null),
			"the stomp bursts the head (gore-lite: Head bone scaled to 0, gore/head_fragments from HeadSocket)")
	sys.clear_all()
	# -- a zombie bites the player (DamageResolver ZOMBIE → PLAYER), then combat damage downs instead of killing
	player.state.stats.reset_stats()
	var biter := _spawn_front(sys, player, ZombieKinds.Kind.WALKER, 1.0)
	var hp0: float = player.state.health
	for k in 30:
		await frames(6)
		_hold_zombie(sys, biter, player, 1.0)
		if player.state.health < hp0:
			break
	check(player.state.health < hp0 and player.state.stats.death_cause() == &"zombi", "a walker's attack hurts the player (%.0f → %.0f, cause %s)" % [hp0, player.state.health, player.state.stats.death_cause()])
	await frames(3)
	if player.view.visual.anim_player.has_animation("combat/Hit_Front"):
		check(is_equal_approx(float(player.view.visual.tree.get("parameters/hit_add/add_amount")), 1.0), "the bitten survivor flinches (Hit_Front on the additive layer)")
	sys.clear_all()
	await seconds(1.05)
	Chat.instance.send("/hurt 200")
	await frames(3)
	check(player.downed and not player.dead and player.state.health <= 0.0 and player.bleed > 30, "combat damage at 0 PV downs the player (bleed %d s)" % player.bleed)
	check(is_equal_approx(PlayerSim.speed_for({"move": Vector2(1, 0), "btn": Packets.BTN_RUN}, player.sim_params()), Balance.DOWNED_CRAWL_SPEED) and not player.can_run,
		"downed: crawls at %.1f m/s, cannot run" % Balance.DOWNED_CRAWL_SPEED)
	var hud: Hud = game.get_node("UI/HUD")
	await frames(2)
	check(hud.down_panel.visible and hud.down_title.text.begins_with("DESANGRÁNDOTE"), "HUD: %s" % hud.down_title.text)
	await seconds(1.4)
	check(not player.downed and not player.dead and absf(player.state.health - Balance.REVIVE_HEALTH) < 2.0 and player.speed_mult < 0.9,
		"alone on the server: gets up by itself once per day (health %.0f, Malherido ×%.2f)" % [player.state.health, player.speed_mult])
	# -- death: second down + give up → corpse with the whole inventory, death screen, respawn at the bed, loot back
	var items_before := 0
	for s in player.state.slots:
		if not s.is_empty():
			items_before += 1
	await seconds(0.6)
	Chat.instance.send("/hurt 200")
	await frames(3)
	request(&"request_give_up", [])
	await frames(5)
	var corpses := tree.get_nodes_in_group("corpse")
	var corpse: Corpse = corpses[0] if not corpses.is_empty() else null
	var corpse_items := 0
	if corpse != null:
		for s in corpse.storage.slots:
			if not s.is_empty():
				corpse_items += 1
	check(player.dead and corpse != null and corpse_items == items_before and items_before >= 4 and player.state.count(&"bate") == 0,
		"death after giving up: a corpse holds the whole inventory (%d stacks), the pockets are empty" % corpse_items)
	check(corpse != null and NetWorld.instance.chunk_for(WorldRegistry.wid_of(corpse)).structures.has(WorldRegistry.wid_of(corpse)), "the corpse is a persisted structure (ChunkDelta)")
	var go: Control = game.get_node("UI/GameOver")
	check(go.visible and GameOverScreen.cause_text(player.state.death_cause) != "", "death screen: %s" % GameOverScreen.cause_text(player.state.death_cause))
	await seconds(0.3)
	GameFlow.request_respawn()
	await frames(5)
	var bed := world.get_respawn_point()
	check(not player.dead and player.global_position.distance_to(bed) < 1.5 and player.in_house, "respawned beside the bed in the cabin (%.2f m)" % player.global_position.distance_to(bed))
	if corpse != null:
		player.global_position = corpse.global_position + Vector3(0.8, 0.3, 0)
		await frames(3)
		request(&"request_interact", [WorldRegistry.wid_of(corpse), &"open", 0])
		await frames(2)
		var sp: StoragePanel = game.get_node("UI/StoragePanel")
		sp.take_all()
		await frames(3)
		sp.close()
		await seconds(2.5)
		check(player.state.count(&"bate") == 1 and player.state.count(&"cuchillo") == 1 and not is_instance_valid(corpse), "looted the corpse back (bat, knife…); the empty corpse went away")
	# -- director v0: day 1 daylight is quiet, the first night sends a few walkers to the clearing
	check(Director.instance.budget(1) >= 1 and _budget_at(1, 11.0) == 0 and _budget_at(1, 21.0) >= 2 and _budget_at(1, 21.0) <= 4 and _budget_at(6, 21.0) > _budget_at(1, 21.0),
		"director budget: day 1 day 0, day 1 night %d, day 6 night %d" % [_budget_at(1, 21.0), _budget_at(6, 21.0)])
	WorldState.instance.set_time(1, 21.0)
	player.global_position = world.get_spawn_point() + Vector3(0, 0.3, 0)
	Director.instance.enabled = true
	await seconds(2.5)
	Director.instance.enabled = false
	check(Director.instance.spawned >= 1 and sys.count_alive() >= 1, "night 1: the director sent %d walkers toward the clearing" % Director.instance.spawned)
	sys.clear_all()
	# -- residents of a forest chunk (population): some frozen outdoors
	PopulationManager.instance.enabled = true
	var pm := PopulationManager.instance
	var forest_total := 0
	for k in world.streamer.chunks:
		forest_total += pm.target_of(int(k))
	check(pm.target_of(WorldConst.key(24, 24)) == 0 and forest_total >= 0, "population: the clearing has no residents, loaded forest chunks %d" % forest_total)
	PopulationManager.instance.enabled = false
	sys.clear_all()
	StatsComponent.solo_getup_time = Balance.SOLO_GETUP_TIME


func _budget_at(day: int, hour: float) -> int:
	var d := WorldState.instance.day
	var h := WorldState.instance.hour
	WorldState.instance.day = day
	WorldState.instance.hour = hour
	WorldState.instance.is_night = hour >= Balance.NIGHT_START or hour < Balance.NIGHT_END
	var b := Director.instance.budget(1)
	WorldState.instance.day = d
	WorldState.instance.hour = h
	WorldState.instance.is_night = h >= Balance.NIGHT_START or h < Balance.NIGHT_END
	return b


func _equip(player: Player, id: StringName) -> void:
	for i in range(1, player.state.slots.size()):
		if not player.state.slots[i].is_empty() and player.state.slots[i]["id"] == id:
			request(&"request_use_slot", [i])
			return


func _yaw_to(player: Player, p: Vector3) -> float:
	var d := p - player.global_position
	return atan2(d.x, d.z)


## A zombie of `kind` `dist` m in front of the player (facing it).
func _spawn_front(sys: ZombieSystem, player: Player, kind: int, dist: float, st: int = ZombieKinds.State.IDLE) -> int:
	var p := player.global_position + player.facing() * dist
	var i := sys.spawn(kind, p, player.aim_yaw + PI, st, -1, -2)
	sys._assign_lod(i, dist)
	if sys.lod[i] == 0 and not sys.l0.has(i):
		sys.l0.append(i)
	return i


## Keeps a zombie at `dist` m in front of the player (tests: the melee target does not wander out of the cone).
func _hold_zombie(sys: ZombieSystem, i: int, player: Player, dist: float) -> void:
	if not sys.is_alive(i):
		return
	var p := player.global_position + player.facing() * dist
	p.y = sys.world.get_height(p.x, p.z)
	sys.pos[i] = p
	if sys.body[i] != null:
		(sys.body[i] as CharacterBody3D).global_position = p + Vector3(0, 0.05, 0)


## A stump node (chunk objects) at `pos` left by the tree `wid`.
func _stump_near(world: World, pos: Vector3, wid: int) -> bool:
	var c := world.streamer.chunk_at(pos.x, pos.z)
	if c == null or c.objects == null:
		return false
	for n in c.objects.get_children():
		if String(n.name).begins_with("stump_of_") and int(n.get_meta("of_wid", 0)) == wid and (n as Node3D).global_position.distance_to(pos) < 0.6:
			return true
	return false


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
				# stance contact = the lowest of the heel (Foot) / ball (Toes) points while planted: the ball rests at
				# 0.035 m and oscillates 0.024–0.035 while locked; the 0.04–0.05 m frames are touchdown / lift-off
				# (the foot still decelerating or leaving the ground), not sliding
				var lowest := ""
				var lowest_y := INF
				for k in ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]:
					var y := (inv * (feet[k] as Vector3)).y
					if y < lowest_y:
						lowest_y = y
						lowest = k
				if lowest_y < 0.038 and prev_feet.has(lowest):
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
