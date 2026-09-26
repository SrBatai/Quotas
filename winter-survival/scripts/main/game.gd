extends Node3D
## Game scene root, two flavours (ARQ v2 §5): the same game.tscn runs in the dedicated server and in the client.
## Client-only branches (UI, chat box, net HUD) are added here at runtime; server-only ones (PlayerManager,
## AdminSocket) likewise. Nodes with RPCs (WorldState, NetWorld, Chat, World/Players/*) keep identical paths.

@onready var world: World = $World
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var drop_spawner: DropSpawner = $DropSpawner
@onready var placed_spawner: StructureSpawner = $PlacedSpawner

var hud: Hud
var craft_panel: CraftPanel
var storage_panel: StoragePanel
var pause_menu: PauseMenu
var game_over: GameOverScreen
var chat_box: ChatBox
var net_hud: NetDebugHud
var player_manager: PlayerManager
var player: Player
## M4 server systems (ARQ v2 §5 "Systems"): zombies, population, director, replication; client: views + fx.
var zombies: ZombieSystem
var population: PopulationManager
var director: Director
var zombie_net: ZombieNet
var zombie_client: ZombieClient
var combat_fx: CombatFx
var _last_category: StringName = &"herramientas"
var _ui: CanvasLayer


func _enter_tree() -> void:
	WorldRegistry.reset()   # before any child registers (World builds in its own _ready, before ours)


func _ready() -> void:
	if Net.role == Net.Role.NONE:
		Net.start_offline()   # scene run directly (F6): offline local server
	# The spawners sit BEFORE World in the scene on purpose: the tree is torn down in reverse child order, so
	# every spawned node leaves the tree (and untracks itself through its one-shot tree_exiting) before its
	# spawner's NOTIFICATION_EXIT_TREE runs. The other order makes the release template print "Attempt to
	# disconnect a nonexistent connection … tree_exiting" for every tracked node at shutdown. Because they enter
	# the tree before World exists, their spawn paths are resolved again here.
	for sp in [player_spawner, $ActorSpawner, drop_spawner, placed_spawner]:
		(sp as MultiplayerSpawner).spawn_path = (sp as MultiplayerSpawner).spawn_path
	if Net.has_client:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_add_client_branches()
	if Net.is_server:
		_add_server_branches()
	Events.world_ready.connect(_on_world_ready)
	if world.is_ready:
		_on_world_ready()


func _add_server_branches() -> void:
	player_manager = PlayerManager.new()
	player_manager.name = "PlayerManager"
	add_child(player_manager)
	var systems := Node.new()
	systems.name = "Systems"
	add_child(systems)
	zombies = ZombieSystem.new()
	systems.add_child(zombies)
	population = PopulationManager.new()
	systems.add_child(population)
	director = Director.new()
	systems.add_child(director)
	zombie_net = ZombieNet.new()
	zombie_net.name = "ZombieNet"
	systems.add_child(zombie_net)
	if world.is_configured:
		_setup_zombies()
	else:
		world.configured.connect(_setup_zombies, CONNECT_ONE_SHOT)
	if Net.is_dedicated:
		var admin := AdminSocket.new()
		admin.name = "AdminSocket"
		add_child(admin)
		admin.setup(player_manager)


func _setup_zombies() -> void:
	zombies.setup(world)
	population.setup(zombies, world)
	director.setup(zombies, world)
	zombie_net.setup(zombies)


func _add_client_branches() -> void:
	zombie_client = ZombieClient.new()
	zombie_client.world = world
	add_child(zombie_client)
	combat_fx = CombatFx.new()
	combat_fx.world = world
	add_child(combat_fx)
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	_ui.layer = 10
	add_child(_ui)
	hud = preload("res://scenes/ui/hud.tscn").instantiate()
	_ui.add_child(hud)
	craft_panel = preload("res://scenes/ui/craft_panel.tscn").instantiate()
	craft_panel.visible = false
	_ui.add_child(craft_panel)
	storage_panel = preload("res://scenes/ui/storage_panel.tscn").instantiate()
	storage_panel.visible = false
	_ui.add_child(storage_panel)
	chat_box = ChatBox.new()
	chat_box.name = "ChatBox"
	_ui.add_child(chat_box)
	net_hud = NetDebugHud.new()
	net_hud.name = "NetDebugHud"
	_ui.add_child(net_hud)
	pause_menu = preload("res://scenes/ui/pause_menu.tscn").instantiate()
	pause_menu.visible = false
	_ui.add_child(pause_menu)
	game_over = preload("res://scenes/ui/game_over.tscn").instantiate()
	game_over.visible = false
	_ui.add_child(game_over)
	hud.hotbar.open_storage = null
	craft_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	craft_panel.offset_left = 72
	craft_panel.offset_top = -160
	storage_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	storage_panel.offset_left = -190
	storage_panel.offset_right = 190
	storage_panel.offset_top = -262
	storage_panel.offset_bottom = -114
	storage_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud.category_bar.category_pressed.connect(_on_category)
	craft_panel.opened.connect(func(cat: StringName) -> void:
		_last_category = cat
		hud.category_bar.set_active(cat)
		storage_panel.close())
	craft_panel.closed.connect(func() -> void: hud.category_bar.set_active(&""))
	storage_panel.closed.connect(func() -> void: hud.hotbar.open_storage = null)
	Events.storage_opened.connect(_on_storage_opened)
	Events.game_over.connect(_show_game_over)
	Events.game_won.connect(_show_win)
	Events.player_respawned.connect(func() -> void: game_over.visible = false)
	Events.local_player_ready.connect(_on_local_player)
	var lp := GameFlow.local_player()
	if lp != null and lp.is_inside_tree():
		_on_local_player(lp)


func _on_local_player(p: Node) -> void:
	player = p
	craft_panel.player = player
	storage_panel.player = player
	Events.region_changed.emit(Regions.name_at(player.global_position.x, player.global_position.z))
	await get_tree().create_timer(1.0).timeout
	if GameFlow.in_game and is_instance_valid(player) and not player.dead:
		Events.notify.emit("Recoge leña y alimenta la estufa antes de que anochezca.", 6.0)


func _on_world_ready() -> void:
	Net.mark_world_ready()
	if player_manager != null:
		player_manager.on_world_ready()
	if Net.is_client or not GameFlow.pending_join.is_empty():
		GameFlow.complete_pending_join()


func _on_category(cat: StringName) -> void:
	craft_panel.toggle(cat)


func _on_storage_opened(storage: Storage) -> void:
	craft_panel.close()
	storage_panel.open(storage)
	hud.hotbar.open_storage = storage


func _show_game_over(days: int, hours: int, cause: StringName) -> void:
	_close_panels()
	if player != null and player.placement != null:
		player.placement.cancel()
	game_over.show_death(days, hours, cause)


func _show_win(days: int) -> void:
	_close_panels()
	game_over.show_win(days)


func _close_panels() -> bool:
	var any := false
	if craft_panel.visible:
		craft_panel.close()
		any = true
	if storage_panel.visible:
		storage_panel.close()
		any = true
	if player != null and player.placement != null and player.placement.active:
		player.placement.cancel()
		any = true
	return any


func _unhandled_input(event: InputEvent) -> void:
	if not Net.has_client or hud == null:
		return
	if game_over.visible or chat_box.is_typing:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("cancel"):
		if GameFlow.is_paused:
			if event.is_action_pressed("pause"):
				pause_menu.resume()
				get_viewport().set_input_as_handled()
			return
		if _close_panels():
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("pause") and event is InputEventKey:
			pause_menu.open()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_craft"):
		var lp := GameFlow.local_player() as Player
		if lp != null and lp.downed:
			return   # Y is also "rendirse" (give_up) while downed: the Interactor takes it
		if craft_panel.visible:
			craft_panel.close()
		else:
			craft_panel.open(_last_category)
		get_viewport().set_input_as_handled()
