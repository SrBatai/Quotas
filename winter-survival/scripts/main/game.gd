extends Node3D
## Game scene root: wires player ↔ world ↔ UI, pause and end screens.

@onready var world: World = $World
@onready var player: Player = $Player
@onready var hud: Hud = $UI/HUD
@onready var craft_panel: CraftPanel = $UI/CraftPanel
@onready var storage_panel: StoragePanel = $UI/StoragePanel
@onready var pause_menu: PauseMenu = $UI/PauseMenu
@onready var game_over: GameOverScreen = $UI/GameOver

var _last_category: StringName = &"herramientas"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.begin_run()
	craft_panel.player = player
	storage_panel.player = player
	hud.hotbar.open_storage = null
	craft_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	craft_panel.offset_left = 72
	craft_panel.offset_top = -160
	storage_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	storage_panel.offset_left = -190
	storage_panel.offset_right = 190
	storage_panel.offset_top = -290
	storage_panel.offset_bottom = -118
	storage_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud.category_bar.category_pressed.connect(_on_category)
	craft_panel.opened.connect(func(cat: StringName) -> void:
		_last_category = cat
		hud.category_bar.set_active(cat)
		storage_panel.close())
	craft_panel.closed.connect(func() -> void: hud.category_bar.set_active(&""))
	storage_panel.closed.connect(func() -> void: hud.hotbar.open_storage = null)
	Events.storage_opened.connect(_on_storage_opened)
	Events.player_died.connect(func(_c: StringName) -> void: pass)
	Events.game_over.connect(_show_game_over)
	Events.game_won.connect(_show_win)
	Events.world_ready.connect(_on_world_ready)
	if world.is_ready:
		_on_world_ready()


func _on_world_ready() -> void:
	Events.region_changed.emit(Regions.name_at(player.global_position.x, player.global_position.z))
	await get_tree().create_timer(1.0).timeout
	if GameState.is_running and not GameState.is_game_over:
		Events.notify.emit("Recoge leña y alimenta la estufa antes de que anochezca.", 6.0)


func _on_category(cat: StringName) -> void:
	craft_panel.toggle(cat)


func _on_storage_opened(storage: Storage) -> void:
	craft_panel.close()
	storage_panel.open(storage)
	hud.hotbar.open_storage = storage


func _show_game_over(days: int, hours: int, cause: StringName) -> void:
	_close_panels()
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
	if player.placement.active:
		player.placement.cancel()
		any = true
	return any


func _unhandled_input(event: InputEvent) -> void:
	if GameState.is_game_over:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("cancel"):
		if get_tree().paused:
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
		if craft_panel.visible:
			craft_panel.close()
		else:
			craft_panel.open(_last_category)
		get_viewport().set_input_as_handled()
