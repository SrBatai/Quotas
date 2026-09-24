class_name Hotbar
extends PanelContainer
## 10-slot bar bound to the Inventory autoload (slot 0 = MANO).

var slots: Array[HotbarSlot] = []
var open_storage: Storage
var _hold_time: float = 0.0
var _held: bool = false
var _selected: int = 1


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.flat_box(UiTheme.PANEL_BG, UiTheme.BORDER, 1, 5, 6))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	for i in Balance.HOTBAR_SLOTS:
		var s := HotbarSlot.new()
		s.index = i
		s.is_hand = i == 0
		s.pressed.connect(_on_slot_pressed)
		row.add_child(s)
		slots.append(s)
		if i == 0:
			var sep := Control.new()
			sep.custom_minimum_size = Vector2(4, 4)
			row.add_child(sep)
	Events.inventory_changed.connect(refresh)
	refresh()
	UiTheme.add_ice_edge(self)


func refresh() -> void:
	for i in slots.size():
		slots[i].set_item(Inventory.slots[i])


func _on_slot_pressed(i: int, shift: bool) -> void:
	AudioManager.play(&"ui_click")
	if open_storage != null and is_instance_valid(open_storage) and open_storage.is_open:
		Inventory.deposit_to_container(open_storage, i, shift)
		return
	Inventory.use_slot(i)


func _unhandled_input(event: InputEvent) -> void:
	if not GameState.is_running or GameState.is_game_over:
		return
	for i in range(1, 10):
		if event.is_action_pressed("hotbar_%d" % i):
			_on_slot_pressed(i - 1, false)
			return
	if event.is_action_pressed("hotbar_prev"):
		_selected = wrapi(_selected - 1, 0, Balance.HOTBAR_SLOTS)
	elif event.is_action_pressed("hotbar_next"):
		_selected = wrapi(_selected + 1, 0, Balance.HOTBAR_SLOTS)
	elif event.is_action_pressed("hotbar_use"):
		_on_slot_pressed(_selected, false)


func _process(delta: float) -> void:
	# D-pad down held 0.4 s toggles the torch (joypad button 12 is also zoom_out; the hold is separate)
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN):
		_hold_time += delta
		if _hold_time >= 0.4 and not _held:
			_held = true
			Inventory.toggle_torch()
	else:
		_hold_time = 0.0
		_held = false
