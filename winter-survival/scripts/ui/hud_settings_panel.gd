class_name HudSettingsPanel
extends PanelContainer
## "Interfaz y accesibilidad" (docs/research/10_hud_ux.md §V.7, appendix §5.7–5.8): HUD preset (Mínimo /
## Estándar / Completo), UI scale 80–150 %, screen margin, HUD width on wide screens, Info as hold or toggle,
## reduced motion, reduced flashes, text weight, text background and colour-blind marker shapes. Every change is
## saved at once (UiSettings, user://settings.cfg [hud]) and the HUD follows live.

signal back()

var _settings: UiSettings
var _rows: VBoxContainer


func _ready() -> void:
	theme = UiTheme.get_theme()
	_settings = UiSettings.get_instance()
	add_theme_stylebox_override("panel", UiTheme.flat_box(UiTheme.PANEL_BG_SOLID, UiTheme.BORDER, 1, 5, 20))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)
	var title := UiTheme.label("INTERFAZ Y ACCESIBILIDAD", 20, UiTheme.TEXT, false, true, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	vb.add_child(_rows)
	_option("HUD", "preset", [[&"minimo", "Mínimo (recomendado)"], [&"estandar", "Estándar"], [&"completo", "Completo"]])
	_slider("Escala de la interfaz", "ui_scale", UiTokens.UI_SCALE_MIN, UiTokens.UI_SCALE_MAX, 0.05, true)
	_slider("Margen de pantalla", "screen_margin", 0.0, UiTokens.SCREEN_MARGIN_MAX, 0.005, true)
	_option("Ancho del HUD (pantallas anchas)", "hud_width", [[&"16:9", "16:9"], [&"21:9", "21:9"], [&"full", "Completo"]])
	_toggle("Info: pulsar para abrir y cerrar (en vez de mantener)", "info_toggle")
	_toggle("Movimiento reducido", "reduced_motion")
	_toggle("Destellos reducidos", "reduced_flashes")
	_toggle("Texto reforzado (más grueso)", "text_bold")
	_option("Fondo del texto", "text_bg", [[&"auto", "Automático"], [&"opaque", "Opaco"]])
	_toggle("Marcadores y colores para daltonismo", "colorblind")
	vb.add_child(UiTheme.spacer(4, 6))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	var reset := UiTheme.menu_button("Restablecer", 160)
	reset.pressed.connect(func() -> void:
		_settings.reset(true)
		_refresh())
	hb.add_child(reset)
	var b := UiTheme.menu_button("Volver", 160)
	b.pressed.connect(func() -> void: back.emit())
	hb.add_child(b)
	UiTheme.add_ice_edge(self)
	# gamepad: the first control takes the focus when the panel shows
	visibility_changed.connect(func() -> void:
		if visible and _rows.get_child_count() > 0:
			var first: Node = _rows.get_child(0)
			var target: Control = first.get_child(1) if first is HBoxContainer and first.get_child_count() > 1 else first as Control
			if target != null:
				target.call_deferred("grab_focus"))


func _label(text: String) -> Label:
	var l := UiTheme.label(text, 13, UiTheme.TEXT)
	l.custom_minimum_size = Vector2(300, 0)
	return l


func _option(text: String, key: String, options: Array) -> void:
	var hb := HBoxContainer.new()
	hb.add_child(_label(text))
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(220, 30)
	for i in options.size():
		ob.add_item(str(options[i][1]), i)
		ob.set_item_metadata(i, options[i][0])
	ob.item_selected.connect(func(i: int) -> void: _settings.set_value(key, ob.get_item_metadata(i)))
	ob.set_meta("key", key)
	hb.add_child(ob)
	_rows.add_child(hb)
	_sync_option(ob)


func _sync_option(ob: OptionButton) -> void:
	var v: Variant = _settings.values.get(str(ob.get_meta("key")))
	for i in ob.item_count:
		if str(ob.get_item_metadata(i)) == str(v):
			ob.select(i)


func _slider(text: String, key: String, lo: float, hi: float, step: float, percent: bool) -> void:
	var hb := HBoxContainer.new()
	hb.add_child(_label(text))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(160, 24)
	s.value = float(_settings.values.get(key, lo))
	s.set_meta("key", key)
	var val := UiTheme.label("", 13, UiTheme.TEXT_2)
	val.custom_minimum_size = Vector2(56, 0)
	var fmt := func(v: float) -> void: val.text = ("%d %%" % int(round(v * 100.0))) if percent else str(v)
	fmt.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		fmt.call(v)
		_settings.set_value(key, v))
	hb.add_child(s)
	hb.add_child(val)
	_rows.add_child(hb)


func _toggle(text: String, key: String) -> void:
	var cb := CheckButton.new()
	cb.text = text
	cb.button_pressed = bool(_settings.values.get(key, false))
	cb.set_meta("key", key)
	cb.toggled.connect(func(on: bool) -> void: _settings.set_value(key, on))
	_rows.add_child(cb)


## Re-reads every control from the settings (after "Restablecer").
func _refresh() -> void:
	for row in _rows.get_children():
		var nodes: Array = [row] + row.get_children()
		for n: Node in nodes:
			if not n.has_meta("key"):
				continue
			var key := str(n.get_meta("key"))
			if n is OptionButton:
				_sync_option(n)
			elif n is HSlider:
				(n as HSlider).set_value_no_signal(float(_settings.values.get(key, 0.0)))
			elif n is CheckButton:
				(n as CheckButton).set_pressed_no_signal(bool(_settings.values.get(key, false)))
