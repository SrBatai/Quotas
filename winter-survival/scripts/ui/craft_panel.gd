class_name CraftPanel
extends PanelContainer
## Recipe list for one category, status line and FABRICAR button.

signal opened(category: StringName)
signal closed()

var category: StringName = &""
var selected: Dictionary = {}
var player: Node
var _title: Label
var _list: VBoxContainer
var _status: Label
var _craft_btn: Button
var _rows: Dictionary = {}


func _ready() -> void:
	theme = UiTheme.get_theme()
	custom_minimum_size = Vector2(190, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	_title = UiTheme.label("FUEGO", 12, UiTheme.TEXT_2, false, true, true)
	vb.add_child(_title)
	var line := ColorRect.new()
	line.color = UiTheme.BORDER
	line.custom_minimum_size = Vector2(0, 1)
	vb.add_child(line)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	vb.add_child(_list)
	_status = UiTheme.label(Recipes.STATUS_MISSING, 10, UiTheme.TEXT_2)
	vb.add_child(_status)
	_craft_btn = UiTheme.primary_button("FABRICAR")
	_craft_btn.pressed.connect(_on_craft_pressed)
	vb.add_child(_craft_btn)
	UiTheme.add_ice_edge(self)
	Events.inventory_changed.connect(_refresh_status)
	visible = false


func open(cat: StringName) -> void:
	category = cat
	_title.text = Recipes.TITLES[cat]
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	selected = {}
	var recipes := Recipes.for_category(cat)
	if recipes.is_empty():
		var l := UiTheme.label(Recipes.EMPTY_CATEGORY, 11, UiTheme.TEXT_2)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(160, 0)
		_list.add_child(l)
		_status.visible = false
		_craft_btn.visible = false
	else:
		_status.visible = true
		_craft_btn.visible = true
		for r in recipes:
			_list.add_child(_make_row(r))
		_select(recipes[0])
	visible = true
	opened.emit(cat)
	AudioManager.play(&"ui_open")


func close() -> void:
	if visible:
		visible = false
		closed.emit()
		AudioManager.play(&"ui_close")


func toggle(cat: StringName) -> void:
	if visible and category == cat:
		close()
	else:
		open(cat)


func _make_row(r: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_stylebox_override("panel", UiTheme.flat_box(UiTheme.SLOT_BG, UiTheme.BORDER, 1, 3, 6))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	row.add_child(hb)
	var icon := UiIcons.make(r["icon"], 28, Color.WHITE, String(r["name"]).substr(0, 1))
	hb.add_child(icon)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	hb.add_child(vb)
	vb.add_child(UiTheme.label(r["name"], 12, UiTheme.TEXT, true))
	var cost := HBoxContainer.new()
	cost.add_theme_constant_override("separation", 6)
	for id in r["cost"]:
		var ci := UiIcons.item_icon(id, 13)
		cost.add_child(ci)
		cost.add_child(UiTheme.label(str(int(r["cost"][id])), 10, UiTheme.TEXT_2))
	vb.add_child(cost)
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_select(r)
			row.accept_event())
	_rows[r["id"]] = row
	return row


func _select(r: Dictionary) -> void:
	selected = r
	for id in _rows:
		var row: PanelContainer = _rows[id]
		if id == r["id"]:
			row.add_theme_stylebox_override("panel", UiTheme.flat_box(Color("#2A3A50", 0.95), UiTheme.ICE, 1, 3, 6))
		else:
			row.add_theme_stylebox_override("panel", UiTheme.flat_box(UiTheme.SLOT_BG, UiTheme.BORDER, 1, 3, 6))
	_refresh_status()


func _refresh_status() -> void:
	if selected.is_empty() or not visible:
		return
	var st := Recipes.status(selected, player)
	_status.text = st["text"]
	_status.add_theme_color_override("font_color", Color("#6FD08C") if st["ok"] else UiTheme.TEXT_2)
	_craft_btn.disabled = not st["ok"]


func _process(_delta: float) -> void:
	if visible and not selected.is_empty() and selected.get("needs_fire", false):
		_refresh_status()


func _on_craft_pressed() -> void:
	if selected.is_empty():
		return
	craft(selected["id"])


## Public: craft by recipe id (also used by the smoke test). The client checks with its inventory mirror and
## asks the server (`request_craft`), which validates again with the authoritative inventory.
func craft(recipe_id: StringName) -> bool:
	var r := Recipes.by_id(recipe_id)
	if r.is_empty():
		return false
	var st := Recipes.status(r, player)
	if not st["ok"]:
		Events.craft_failed.emit(st["text"])
		Events.notify.emit(st["text"], 2.0)
		return false
	if r.has("place"):
		if player != null:
			player.placement.begin(r["place"], r)
		close()
		return true
	Net.rpc_server(NetWorld.instance, &"request_craft", [recipe_id])
	_refresh_status()
	return true
