class_name AudioSettingsPanel
extends PanelContainer
## "Sonido" (S1): Volumen general / Efectos / Ambiente / Interfaz / Música, 0–100 %, saved at once (AudioSettings,
## user://settings.cfg [audio]) and heard live: moving a slider plays a short sample on that bus.

signal back()

const SAMPLE := {"master": &"ui_click", "effects": &"chop_hit", "ambience": &"amb_house_creak", "ui": &"ui_click", "music": &""}

var _settings: AudioSettings
var _rows: VBoxContainer
var _sample_t: float = 0.0


func _ready() -> void:
	theme = UiTheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_settings = AudioSettings.get_instance()
	add_theme_stylebox_override("panel", UiTheme.flat_box(UiTheme.PANEL_BG_SOLID, UiTheme.BORDER, 1, 5, 20))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)
	var title := UiTheme.label("SONIDO", 20, UiTheme.TEXT, false, true, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	vb.add_child(_rows)
	for key: String in ["master", "effects", "ambience", "ui", "music"]:
		_slider(str(AudioSettings.LABELS[key]), key)
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
	visibility_changed.connect(func() -> void:
		if visible and _rows.get_child_count() > 0:
			var first: Node = _rows.get_child(0)
			if first.get_child_count() > 1:
				(first.get_child(1) as Control).call_deferred("grab_focus"))


func _slider(text: String, key: String) -> void:
	var hb := HBoxContainer.new()
	var l := UiTheme.label(text, 13, UiTheme.TEXT)
	l.custom_minimum_size = Vector2(220, 0)
	hb.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(200, 24)
	s.value = _settings.get_value(key)
	s.set_meta("key", key)
	var val := UiTheme.label("", 13, UiTheme.TEXT_2)
	s.set_meta("val", val)
	val.custom_minimum_size = Vector2(56, 0)
	var fmt := func(v: float) -> void: val.text = "%d %%" % int(round(v * 100.0))
	fmt.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		fmt.call(v)
		_settings.set_value(key, v)
		var now := Time.get_ticks_msec() / 1000.0
		if now - _sample_t > 0.25 and SAMPLE[key] != &"":
			_sample_t = now
			AudioManager.play(SAMPLE[key]))
	hb.add_child(s)
	hb.add_child(val)
	_rows.add_child(hb)


func _refresh() -> void:
	for row in _rows.get_children():
		for n in row.get_children():
			if n is HSlider and n.has_meta("key"):
				var v := _settings.get_value(str(n.get_meta("key")))
				(n as HSlider).set_value_no_signal(v)
				(n.get_meta("val") as Label).text = "%d %%" % int(round(v * 100.0))
