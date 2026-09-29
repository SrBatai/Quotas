class_name Hotbar
extends Control
## HUD v2 hotbar (docs/research/10_hud_ux.md §V.4.1, mockups v2_a / v2_b): at rest it folds into 10 strokes of
## 22 × 2 px (28 %, the slot in hand at 85 %), 40 px above the bottom edge. Using it (1–9, D‑pad ←/→ + A, a click,
## a weapon change, a pickup that lands in the bar, an open container) unfolds it into 40 px rendered icons
## WITHOUT slots, lifted 6 px; the selected slot gets a 1 px underline and its name above ("Bate con clavos 12 %",
## the % in `warn` below 20 % durability). Empty slots are a dot, counts are 16 px tabular figures. 3 s after the
## last use it folds back (600 ms). Slot 0 = MANO. Actions are server requests (unchanged).
## Audit fix (§1.3.1): the gamepad selection (`selected`) is drawn — it was invisible before.
## H3 (M5 hook): with a firearm in hand, the ammo sits on the bar's line, right of the strip / the icons —
## "12/15 · 44" in tabular figures (warn at a quarter of the magazine, blood when empty, «recargando» /
## «encasquillada» in small caps). It shows on a shot, a reload, a jam or a weapon change for 3 s (element
## `hotbar.ammo`), stays while jammed, reloading or low, and with Info (Events.weapon_state_changed).

signal slot_used(index: int)

const EL := &"hotbar"
const EL_NAME := &"hotbar.name"
const EL_AMMO := &"hotbar.ammo"

var open_storage: Storage
var selected: int = 0
var vis: HudVisibility
var _items: Array = []            # [{id, count, dur}] mirror of the local slots
var _textures: Dictionary = {}
var _hover: int = -1
var _hold_time: float = 0.0
var _held: bool = false
var _prev_counts: Dictionary = {}
var _prev_hand: StringName = &""
var _name_text: String = ""
var _name_pct: String = ""
var _name_warn: bool = false
var _select_hand_next: bool = false
var _drawn: Vector3 = Vector3(-1, -1, -1)
## Set by the owner when there is no HudVisibility (legacy placement / tests): the icons stay unfolded.
var always_open: bool = false
## H3: the owner's weapon mirror (Events.weapon_state_changed) and the ammo text drawn on the bar's line.
var gun: Dictionary = {}
var ammo_text: String = ""
var _ammo_key: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(_icons_width(), UiTokens.HOTBAR_CELL + 40.0)
	gui_input.connect(_on_gui_input)
	mouse_exited.connect(func() -> void:
		_hover = -1
		queue_redraw())
	Events.inventory_changed.connect(refresh)
	GameFlow.local_player_changed.connect(func(_p: Node) -> void: refresh())
	Events.weapon_state_changed.connect(_on_gun)
	refresh()


## Wires the visibility machine (called by the HUD).
func setup(v: HudVisibility) -> void:
	vis = v
	vis.register(EL, null, UiTokens.T_HOTBAR, true, &"hotbar")
	vis.register(EL_NAME, null, UiTokens.T_ITEM_NAME, true, &"hotbar")
	vis.register(EL_AMMO, null, UiTokens.T_HOTBAR, true, &"hotbar")


# ------------------------------------------------------------------ H3: ammo on the bar's line (M5 hook)
func _hand_is_gun() -> bool:
	if _items.is_empty() or (_items[0] as Dictionary).is_empty():
		return false
	var id: StringName = _items[0]["id"]
	return Firearms.is_firearm(id) or Firearms.is_bow(id)


func _on_gun(d: Dictionary) -> void:
	gun = d
	var t := ammo_line(d)
	var key := "%s|%s" % [str(d.get("w", "")), t]
	if key != _ammo_key:
		_ammo_key = key
		ammo_text = t
		if vis != null and t != "" and _hand_is_gun():
			vis.poke(EL_AMMO)
	queue_redraw()


## "12/15 · 44", «recargando», «encasquillada» (or "" without a firearm).
static func ammo_line(d: Dictionary) -> String:
	if d.is_empty() or str(d.get("w", "")) == "":
		return ""
	if bool(d.get("jammed", false)):
		return "encasquillada"
	if float(d.get("reload_left", -1.0)) >= 0.0:
		return "recargando"
	return "%d/%d · %d" % [int(d.get("ammo", 0)), int(d.get("mag", 0)), int(d.get("reserve", 0))]


func _ammo_low() -> bool:
	var mag := int(gun.get("mag", 0))
	return mag > 0 and float(int(gun.get("ammo", 0))) <= float(mag) * UiTokens.AMMO_LOW_FRACTION


func _icons_width() -> float:
	var n := float(Balance.HOTBAR_SLOTS)
	return n * UiTokens.HOTBAR_CELL + (n - 1.0) * UiTokens.HOTBAR_GAP


func _strip_width() -> float:
	var n := float(Balance.HOTBAR_SLOTS)
	return n * UiTokens.HOTBAR_STROKE.x + (n - 1.0) * UiTokens.HOTBAR_STROKE_GAP


## Unfolds the bar for its read time (and the item name when `name_too`).
func poke(name_too: bool = false) -> void:
	if vis != null:
		vis.poke(EL)
		if name_too:
			_update_name()
			vis.poke(EL_NAME)
	queue_redraw()


func refresh() -> void:
	var st: PlayerState = GameFlow.local_state()
	var old := _items
	_items = []
	for i in Balance.HOTBAR_SLOTS:
		var e: Dictionary = st.slots[i] if st != null and i < st.slots.size() else {}
		_items.append(e.duplicate())
	# a pickup that lands in the bar, a weapon change → unfold (V.3)
	var counts := {}
	for e: Dictionary in _items:
		if not e.is_empty():
			counts[e["id"]] = int(counts.get(e["id"], 0)) + int(e["count"])
	var grew := false
	for id in counts:
		if int(counts[id]) > int(_prev_counts.get(id, 0)):
			grew = true
	var hand: StringName = _items[0].get("id", &"") if not _items.is_empty() else &""
	var hand_changed := hand != _prev_hand
	var first := _prev_counts.is_empty() and old.is_empty()
	_prev_counts = counts
	_prev_hand = hand
	if _select_hand_next:
		_select_hand_next = false
		if selected != 0 and (_items[selected] as Dictionary).is_empty():
			selected = 0
	if not first and (grew or hand_changed):
		if hand_changed:
			selected = 0
		poke(hand_changed)
	elif not first:
		_update_name()
	queue_redraw()


func _update_name() -> void:
	var e: Dictionary = _items[selected] if selected < _items.size() else {}
	if _hover >= 0 and _hover < _items.size():
		e = _items[_hover]
	if e.is_empty():
		_name_text = "Mano vacía" if selected == 0 and _hover < 0 else ""
		_name_pct = ""
		_name_warn = false
		return
	_name_text = Items.display_name(e["id"])
	_name_pct = ""
	_name_warn = false
	if e.has("dur"):
		var d := int(e["dur"])
		_name_warn = d < 20
		if d < 100:
			_name_pct = "%d %%" % d


## Durability < 20 % keeps the name visible (V.3 "Objeto en mano / durabilidad").
func _low_durability() -> bool:
	return not _items.is_empty() and not (_items[0] as Dictionary).is_empty() and (_items[0] as Dictionary).has("dur") and int(_items[0]["dur"]) < 20


func _texture_of(id: StringName) -> Texture2D:
	if not _textures.has(id):
		_textures[id] = UiIcons.tex(Items.icon_name(id), true)
	return _textures[id]


func _on_slot_pressed(i: int, shift: bool) -> void:
	AudioManager.play(&"ui_click")
	selected = i
	_select_hand_next = true
	poke(true)
	slot_used.emit(i)
	if NetWorld.instance == null:
		return
	if open_storage != null and is_instance_valid(open_storage) and open_storage.is_open:
		Net.rpc_server(NetWorld.instance, &"request_deposit", [open_storage.wid(), i, shift])
		return
	Net.rpc_server(NetWorld.instance, &"request_use_slot", [i])


func _active() -> bool:
	var p: Player = GameFlow.local_player()
	return GameFlow.in_game and p != null and not p.dead


func _unhandled_input(event: InputEvent) -> void:
	if not _active():
		return
	for i in range(1, 10):
		if event.is_action_pressed("hotbar_%d" % i):
			_on_slot_pressed(i - 1, false)
			return
	if event.is_action_pressed("hotbar_prev"):
		selected = wrapi(selected - 1, 0, Balance.HOTBAR_SLOTS)
		poke(true)
	elif event.is_action_pressed("hotbar_next"):
		selected = wrapi(selected + 1, 0, Balance.HOTBAR_SLOTS)
		poke(true)
	elif event.is_action_pressed("hotbar_use"):
		_on_slot_pressed(selected, false)


## Slot rectangles in local coordinates (icons layout).
func slot_rect(i: int) -> Rect2:
	var x0 := (size.x - _icons_width()) * 0.5
	var y0 := size.y - UiTokens.HOTBAR_CELL
	return Rect2(x0 + float(i) * (UiTokens.HOTBAR_CELL + UiTokens.HOTBAR_GAP), y0, UiTokens.HOTBAR_CELL, UiTokens.HOTBAR_CELL)


func _slot_at(p: Vector2) -> int:
	for i in Balance.HOTBAR_SLOTS:
		if slot_rect(i).grow(UiTokens.HOTBAR_GAP * 0.5).has_point(p):
			return i
	return -1


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _slot_at((event as InputEventMouseMotion).position)
		if h != _hover:
			_hover = h
			if h >= 0:
				poke(true)
		elif vis != null:
			vis.poke(EL)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _slot_at(event.position)
		if i >= 0:
			_on_slot_pressed(i, event.shift_pressed)
			accept_event()


func _process(delta: float) -> void:
	# D-pad down held 0.4 s toggles the torch (joypad button 12 is also zoom_out; the hold is separate)
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN):
		_hold_time += delta
		if _hold_time >= 0.4 and not _held:
			_held = true
			if NetWorld.instance != null:
				Net.rpc_server(NetWorld.instance, &"request_toggle_torch", [])
	else:
		_hold_time = 0.0
		_held = false
	if vis != null:
		var storage_open := open_storage != null and is_instance_valid(open_storage) and open_storage.is_open
		vis.set_hold(EL, storage_open or _hover >= 0)
		vis.set_hold(EL_NAME, _low_durability() and vis.is_on(EL))
		var gun_in_hand := _hand_is_gun() and ammo_text != ""
		vis.set_hold(EL_AMMO, gun_in_hand and (bool(gun.get("jammed", false)) or float(gun.get("reload_left", -1.0)) >= 0.0 or _ammo_low()))
		if not gun_in_hand and vis.is_on(EL_AMMO):
			vis.release(EL_AMMO)
	var key := Vector3(expand(), vis.alpha_of(EL_NAME) if vis != null else 0.0, vis.alpha_of(EL_AMMO) if vis != null else 0.0)
	if key != _drawn:
		_drawn = key
		queue_redraw()


## 0 = strip, 1 = icons.
func expand() -> float:
	if always_open or vis == null:
		return 1.0
	return vis.alpha_of(EL)


func _draw() -> void:
	var k := expand()
	var name_a := vis.alpha_of(EL_NAME) if vis != null else 0.0
	_draw_ammo(k)
	# folded strip (fades out as the icons come in)
	var sa := 1.0 - k
	if sa > 0.002:
		var x0 := (size.x - _strip_width()) * 0.5
		var y := size.y - UiTokens.HOTBAR_BOTTOM * 0.0 - UiTokens.HOTBAR_STROKE.y
		for i in Balance.HOTBAR_SLOTS:
			var r := Rect2(x0 + float(i) * (UiTokens.HOTBAR_STROKE.x + UiTokens.HOTBAR_STROKE_GAP), y, UiTokens.HOTBAR_STROKE.x, UiTokens.HOTBAR_STROKE.y)
			var on := i == 0 or i == selected
			var c: Color = UiTokens.STRIP_ON if i == 0 else (Color(UiTokens.INK_RGB, 0.6) if on else UiTokens.STRIP)
			draw_rect(r.grow(1.0), Color(0, 0, 0, 0.18 * sa))
			draw_rect(r, Color(c, c.a * sa))
	if k <= 0.002:
		return
	var lift := UiMotion.slide(UiTokens.HOTBAR_LIFT) * k
	var gamepad := HudInput.gamepad
	for i in Balance.HOTBAR_SLOTS:
		var r := slot_rect(i)
		r.position.y -= lift - UiMotion.slide(UiTokens.HOTBAR_LIFT)
		var e: Dictionary = _items[i] if i < _items.size() else {}
		var c := r.get_center()
		if e.is_empty():
			draw_circle(c + Vector2(0, 1), 2.6, Color(0, 0, 0, 0.3 * k))
			draw_circle(c, 2.0, Color(UiTokens.INK_30, UiTokens.INK_30.a * k))
		else:
			var tex := _texture_of(e["id"])
			var ir := Rect2(c - Vector2(UiTokens.HOTBAR_ICON, UiTokens.HOTBAR_ICON) * 0.5, Vector2(UiTokens.HOTBAR_ICON, UiTokens.HOTBAR_ICON))
			var ia := (1.0 if i == selected or i == _hover else 0.9) * k
			if tex != null:
				draw_texture_rect(tex, Rect2(ir.position + Vector2(0, 2), ir.size), false, Color(0, 0, 0, 0.35 * k))
				draw_texture_rect(tex, ir, false, Color(1, 1, 1, ia))
			else:
				UiStyle.draw_text(self, &"item_name", c + Vector2(-6, 6), Items.display_name(e["id"]).substr(0, 1), Color(0, 0, 0, 0), HORIZONTAL_ALIGNMENT_LEFT, -1.0, k)
			var n := int(e["count"])
			var show_n := n > 1 or (not Items.is_tool_item(e["id"]) and n >= 1)
			if i == 0 and n <= 1:
				show_n = false
			if show_n:
				var q := str(n)
				UiStyle.draw_text(self, &"meta", Vector2(r.end.x + 4.0 - UiStyle.text_width(&"meta", q), r.end.y + 2.0), q, UiTokens.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, k)
			if e.has("dur") and int(e["dur"]) < 20:
				draw_rect(Rect2(r.position.x + 6.0, r.end.y + 5.0, (r.size.x - 12.0) * clampf(float(e["dur"]) / 100.0, 0.05, 1.0), 1.0), Color(UiTokens.WARN, 0.9 * k))
		# selection: 1 px underline (drawn for the gamepad cursor too — audit §1.3.1)
		if i == selected or (i == _hover and not gamepad):
			var ua := k * (1.0 if i == selected else 0.5)
			var ux := Rect2(r.position.x + 4.0, r.end.y + 8.0, r.size.x - 8.0, 1.0)
			draw_rect(ux.grow(1.5), Color(1, 1, 1, 0.12 * ua))
			draw_rect(ux, Color(UiTokens.INK_RGB, ua))
	# item name above the bar (1.5 s after a selection; kept while durability < 20 %)
	if name_a > 0.002 and _name_text != "":
		var total := UiStyle.text_width(&"item_name", _name_text) + (12.0 + UiStyle.text_width(&"item_name", _name_pct) if _name_pct != "" else 0.0)
		var x := size.x * 0.5 - total * 0.5
		var by := size.y - UiTokens.HOTBAR_CELL - 30.0 - lift
		UiStyle.draw_text(self, &"item_name", Vector2(x, by), _name_text, UiTokens.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, name_a * k)
		if _name_pct != "":
			UiStyle.draw_text(self, &"item_name", Vector2(x + UiStyle.text_width(&"item_name", _name_text) + 12.0, by), _name_pct,
				UiTokens.WARN if _name_warn else UiTokens.INK_70, HORIZONTAL_ALIGNMENT_LEFT, -1.0, name_a * k)


## The ammo text right of the strip (folded) or of the icons (unfolded), on the bar's baseline.
func _draw_ammo(k: float) -> void:
	var a := vis.alpha_of(EL_AMMO) if vis != null else (1.0 if ammo_text != "" else 0.0)
	if a <= 0.002 or ammo_text == "" or not _hand_is_gun():
		return
	var words := not ammo_text.contains("/")
	var style := &"smallcaps" if words else &"text_num"
	var col := UiTokens.INK_70
	if bool(gun.get("jammed", false)):
		col = UiTokens.WARN
	elif not words and int(gun.get("ammo", 0)) == 0:
		col = UiTokens.BLOOD_TEXT
	elif not words and _ammo_low():
		col = UiTokens.WARN
	var right_strip := (size.x + _strip_width()) * 0.5
	var right_icons := (size.x + _icons_width()) * 0.5
	var x := lerpf(right_strip + 16.0, right_icons + 12.0, k)
	var y := lerpf(size.y + 5.0, size.y - UiTokens.HOTBAR_CELL * 0.5 + 6.0 - UiMotion.slide(UiTokens.HOTBAR_LIFT) * k, k)
	UiStyle.draw_text(self, style, Vector2(x, y), ammo_text, col, HORIZONTAL_ALIGNMENT_LEFT, -1.0, a)
