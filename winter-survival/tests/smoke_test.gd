extends SceneTree
## Headless smoke test (ARCHITECTURE §21.1). Run: godot --headless --path . -s tests/smoke_test.gd

var _failed: bool = false
var _checks: int = 0
var _signals: Dictionary = {}


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
	for s in events.get_signal_list():
		if s["name"] == String(sig):
			argc = s["args"].size()
	match argc:
		0: events.connect(sig, func() -> void: _signals[sig] += 1)
		1: events.connect(sig, func(_a) -> void: _signals[sig] += 1)
		2: events.connect(sig, func(_a, _b) -> void: _signals[sig] += 1)
		_: events.connect(sig, func(_a, _b, _c) -> void: _signals[sig] += 1)


func fired(sig: StringName) -> int:
	return int(_signals.get(sig, 0))


func frames(n: int) -> void:
	for i in n:
		await process_frame


func seconds(s: float) -> void:
	await create_timer(s).timeout


var events: Node
var game_state: Node
var inventory: Node
var quest_manager: Node


func _initialize() -> void:
	events = root.get_node("Events")
	game_state = root.get_node("GameState")
	inventory = root.get_node("Inventory")
	quest_manager = root.get_node("QuestManager")
	Engine.max_fps = 60
	_run()


func _run() -> void:
	print("== VENTISCA smoke test")
	for sig in [&"world_ready", &"tree_felled", &"item_consumed", &"wolf_died", &"weather_changed", &"shelter_changed",
			&"day_started", &"player_died", &"game_won", &"campfire_placed", &"stove_fueled", &"crafted", &"night_started"]:
		_watch(sig)
	await process_frame
	# 1. load the game scene
	change_scene_to_file("res://scenes/main/game.tscn")
	var waited := 0
	while fired(&"world_ready") == 0 and waited < 600:
		await process_frame
		waited += 1
	check(fired(&"world_ready") > 0, "world_ready emitted (%d frames)" % waited)
	await frames(5)
	var game := current_scene
	var player: Player = game.get_node("Player")
	var world: World = game.get_node("World")
	# 2. structure
	check(player != null, "player exists")
	check(world.terrain.get_node_or_null("Shape") != null and world.terrain.get_node("Shape").shape != null, "terrain collision shape present")
	check(world.cabin != null, "cabin exists")
	var stove: WoodStove = world.cabin.get_node("Stove")
	check(stove != null and stove.is_lit, "stove exists and is lit")
	var cabinet := world.cabin.get_node("Cabinet")
	check(cabinet != null, "cabinet exists")
	var trees := get_nodes_in_group("tree")
	check(trees.size() >= 200, "trees in group 'tree': %d" % trees.size())
	check(get_nodes_in_group("pickup").size() >= 1, "pickups exist: %d" % get_nodes_in_group("pickup").size())
	check(game_state.day == 1, "day == 1")
	check(absf(game_state.hour - 8.0) < 0.2, "hour ≈ 8 (%.2f)" % game_state.hour)
	check(get_nodes_in_group("deer").size() >= 1, "deer spawned: %d" % get_nodes_in_group("deer").size())
	# 3. run a bit
	await frames(120)
	check(not is_nan(player.stats.health) and not is_nan(player.stats.warmth) and not is_nan(player.stats.hunger), "stats are numbers")
	check(player.stats.hunger < Balance.HUNGER_START, "hunger draining (%.2f)" % player.stats.hunger)
	check(player.is_on_floor(), "player on floor (y=%.2f)" % player.global_position.y)
	# 4. inventory + craft axe
	inventory.add(&"madera", 2)
	inventory.add(&"piedra", 3)
	var craft_panel: CraftPanel = game.get_node("UI/CraftPanel")
	var ok := craft_panel.craft(&"hacha")
	check(ok, "crafted hacha via CraftPanel.craft")
	check(fired(&"crafted") >= 1, "crafted signal fired")
	if inventory.hand_tool() != &"hacha":
		for i in range(1, inventory.slots.size()):
			if not inventory.slots[i].is_empty() and inventory.slots[i]["id"] == &"hacha":
				inventory.equip_from_slot(i)
	check(inventory.hand_tool() == &"hacha", "axe equipped in hand")
	check(inventory.count(&"madera") == 0 and inventory.count(&"piedra") == 0, "materials consumed")
	await frames(2)
	check(player.tool_holder.tool_model != null, "axe model spawned in ToolSocket")
	# 5. chop the nearest pine
	var nearest: ChoppableTree = null
	var best := INF
	for t in get_nodes_in_group("tree"):
		if t.variant == "fallen_log":
			continue
		var d: float = t.global_position.distance_to(player.global_position)
		if d < best:
			best = d
			nearest = t
	check(nearest != null, "found a tree to chop")
	if nearest != null:
		var side := (player.global_position - nearest.global_position)
		side.y = 0.0
		side = side.normalized() * 1.5
		player.global_position = nearest.global_position + side + Vector3(0, 0.3, 0)
		await frames(3)
		for i in nearest.total_hits:
			nearest.interactable.interact(player)
			await seconds(0.55)
		check(fired(&"tree_felled") >= 1, "tree_felled fired")
		check(inventory.count(&"madera") == Balance.TREE_WOOD, "wood after chop == %d (got %d)" % [Balance.TREE_WOOD, inventory.count(&"madera")])
	# 6. stove
	var fuel_before := stove.burner.fuel
	var fed := stove.add_wood_from_player(player)
	check(fed and stove.burner.fuel > fuel_before, "stove fuel increased (%.0f → %.0f)" % [fuel_before, stove.burner.fuel])
	check(fired(&"stove_fueled") >= 1, "stove_fueled fired")
	await frames(2)
	check(quest_manager.index >= 3, "quest index advanced to >= 3 (got %d)" % quest_manager.index)
	# 7. container
	var storage: Storage = cabinet.get_node("Storage")
	var storage_panel: StoragePanel = game.get_node("UI/StoragePanel")
	storage_panel.open(storage)
	check(storage.is_open, "cabinet storage open")
	inventory.take_from_container(storage, 0, false)
	check(inventory.count(&"lata_judias") == 1, "took one lata_judias")
	var hunger_before := player.stats.hunger
	var ate: bool = inventory.eat_best()
	await frames(2)
	check(ate and player.stats.hunger > hunger_before, "eat_best increased hunger (%.1f → %.1f)" % [hunger_before, player.stats.hunger])
	check(fired(&"item_consumed") >= 1, "item_consumed fired")
	storage_panel.close()
	check(not storage.is_open, "storage closed")
	# 8. campfire placement
	player.global_position = world.get_spawn_point() + Vector3(0, 0.3, 0)
	await frames(3)
	inventory.add(&"madera", 3)
	inventory.add(&"piedra", 4)
	var fog := Recipes.by_id(&"fogata")
	player.placement.begin("campfire", fog)
	check(player.placement.active, "placement mode active")
	var placed := player.placement.confirm_at(player.global_position + Vector3(2.5, 0, 0))
	check(placed, "campfire placed")
	check(get_nodes_in_group("campfire").size() >= 1, "campfire in group")
	var campfire: Campfire = get_nodes_in_group("campfire")[0] if get_nodes_in_group("campfire").size() > 0 else null
	check(campfire != null and campfire.is_lit, "campfire is lit")
	check(fired(&"campfire_placed") >= 1, "campfire_placed fired")
	await frames(60)
	check(player.stats.warmth_rate() > 0.0, "warmth rate positive near campfire (%.2f)" % player.stats.warmth_rate())
	# 9. night + wolves
	game_state.set_time(1, 20.1)
	await frames(30)
	check(fired(&"night_started") >= 1, "night_started fired")
	var wolves := get_nodes_in_group("wolves")
	check(wolves.size() >= 1, "wolves spawned at night: %d" % wolves.size())
	var wolf: Wolf = wolves[0] if wolves.size() > 0 else null
	if wolf != null:
		var far := player.global_position + Vector3(10, 0.3, 0)
		far.y = world.get_height(far.x, far.z) + 0.3
		wolf.global_position = far
		await frames(120)
		check(wolf.state in [Wolf.State.STALK, Wolf.State.CHASE, Wolf.State.ATTACK, Wolf.State.FLEE], "wolf state after 120 frames: %s" % Wolf.State.keys()[wolf.state])
		campfire.global_position = wolf.global_position
		await frames(30)
		check(wolf.state == Wolf.State.FLEE, "wolf flees from the campfire (state %s)" % Wolf.State.keys()[wolf.state])
		# 10. kill
		wolf.take_damage(999.0, player)
		await frames(2)
		check(fired(&"wolf_died") >= 1, "wolf_died fired")
		await seconds(2.0)
		var drops := 0
		for p in get_nodes_in_group("pickup"):
			if p.item_id in [&"carne_cruda", &"piel"]:
				drops += 1
		check(drops >= 2, "wolf drops spawned: %d" % drops)
	# 11. blizzard
	var weather: Weather = world.get_node("Weather")
	weather.force_blizzard(5.0)
	await frames(2)
	check(game_state.weather == &"blizzard", "weather == blizzard")
	check(fired(&"weather_changed") >= 1, "weather_changed fired")
	await seconds(6.0)
	check(game_state.weather == &"clear", "weather back to clear")
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
	# 13. day roll
	game_state.set_time(1, 5.98)
	await frames(90)
	check(game_state.day == 2, "day == 2 after roll (got %d)" % game_state.day)
	check(fired(&"day_started") >= 1, "day_started fired")
	var leaving := true
	for w in get_nodes_in_group("wolves"):
		if w.state != Wolf.State.LEAVE:
			leaving = false
	check(leaving, "wolves leaving at dawn")
	check(quest_manager.index == 0 and quest_manager.steps.size() == 4, "quest reset for day 2 (index %d, %d steps)" % [quest_manager.index, quest_manager.steps.size()])
	# 14. death
	player.stats.warmth = 0.0
	player.stats.health = 1.0
	await frames(30)
	check(fired(&"player_died") >= 1, "player_died fired")
	check(game_state.is_game_over and game_state.death_cause == &"frio", "game over by frio (cause=%s)" % game_state.death_cause)
	var go: Control = game.get_node("UI/GameOver")
	check(go.visible, "GameOver screen visible")
	# 15. win
	go.visible = false
	game_state.debug_revive()
	player.stats.debug_revive()
	game_state.set_time(5, 5.98)
	await frames(90)
	check(fired(&"game_won") >= 1, "game_won fired")
	check(game_state.best_days >= 5, "best_days saved (%d)" % game_state.best_days)
	print("== %d checks, %s" % [_checks, "FAILED" if _failed else "ALL PASSED"])
	quit(1 if _failed else 0)
