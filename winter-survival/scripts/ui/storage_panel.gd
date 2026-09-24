class_name StoragePanel
extends PanelContainer
## Container UI: title, ✕, 6 slots (+N badge for food), footer, COGER TODO.

signal closed()

var storage: Storage
var player: Node3D
var _title: Label
var _slots: Array[HotbarSlot] = []


func _ready() -> void:
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiTheme.flat_box(UiTheme.PANEL_BG, UiTheme.BORDER, 1, 4, 8))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	_title = UiTheme.label("ARMARIO", 13, UiTheme.TEXT, false, true, true)
	head.add_child(_title)
	head.add_child(UiTheme.hspacer())
	var x := Button.new()
	x.text = "✕"
	x.custom_minimum_size = Vector2(26, 26)
	x.focus_mode = Control.FOCUS_NONE
	x.add_theme_font_size_override("font_size", 12)
	x.pressed.connect(close)
	head.add_child(x)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	vb.add_child(row)
	for i in Balance.CONTAINER_SLOTS:
		var s := HotbarSlot.new()
		s.index = i
		s.show_bonus = true
		s.pressed.connect(_on_slot_pressed)
		row.add_child(s)
		_slots.append(s)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	vb.add_child(foot)
	var hint := UiTheme.label("Clic: coger uno · Mayús+clic: la pila · Clic en tu barra: guardar", 9, UiTheme.TEXT_2)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(hint)
	var all_btn := UiTheme.primary_button("COGER TODO")
	all_btn.pressed.connect(take_all)
	foot.add_child(all_btn)
	UiTheme.add_ice_edge(self)
	visible = false


func open(s: Storage) -> void:
	if storage != null and storage != s:
		storage.is_open = false
		if storage.changed.is_connected(refresh):
			storage.changed.disconnect(refresh)
	storage = s
	storage.is_open = true
	if not storage.changed.is_connected(refresh):
		storage.changed.connect(refresh)
	_title.text = storage.title
	refresh()
	visible = true


func close() -> void:
	if storage != null:
		storage.is_open = false
		if storage.changed.is_connected(refresh):
			storage.changed.disconnect(refresh)
	storage = null
	if visible:
		visible = false
		Events.storage_closed.emit()
		closed.emit()
		AudioManager.play(&"ui_close")


func refresh() -> void:
	if storage == null:
		return
	for i in _slots.size():
		_slots[i].set_item(storage.slots[i])


func _on_slot_pressed(i: int, shift: bool) -> void:
	if storage == null:
		return
	AudioManager.play(&"ui_click")
	Inventory.take_from_container(storage, i, shift)


func take_all() -> void:
	if storage == null:
		return
	for i in storage.slots.size():
		if not storage.slots[i].is_empty():
			Inventory.take_from_container(storage, i, true)


func _process(_delta: float) -> void:
	if not visible or storage == null or player == null:
		return
	var p := storage.anchor_position()
	var d := Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length()
	if d > 3.5:
		close()
