class_name PauseMenu
extends Control
## PAUSA overlay (+ "Interfaz y accesibilidad": HUD preset, scale, Info hold / toggle, motion, colour-blind).

var _panel: PanelContainer
var _hud_settings: HudSettingsPanel
var _audio_settings: AudioSettingsPanel   # S1: "Sonido" (volumes)


func _ready() -> void:
	theme = UiTheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color("#0B1220", 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.flat_box(UiTheme.PANEL_BG_SOLID, UiTheme.BORDER, 1, 5, 24))
	center.add_child(panel)
	_panel = panel
	_hud_settings = HudSettingsPanel.new()
	_hud_settings.visible = false
	_hud_settings.back.connect(func() -> void:
		_hud_settings.visible = false
		_panel.visible = true)
	center.add_child(_hud_settings)
	_audio_settings = AudioSettingsPanel.new()
	_audio_settings.visible = false
	_audio_settings.back.connect(func() -> void:
		_audio_settings.visible = false
		_panel.visible = true)
	center.add_child(_audio_settings)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := UiTheme.label("PAUSA", 26, UiTheme.TEXT, false, true, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	vb.add_child(UiTheme.spacer(4, 6))
	var b1 := UiTheme.menu_button("Continuar")
	b1.pressed.connect(func() -> void: resume())
	vb.add_child(b1)
	var hint := UiTheme.label("El mundo sigue en el servidor mientras estás en pausa", 10, UiTheme.TEXT_2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.visible = not Net.is_offline
	vb.add_child(hint)
	var b2 := UiTheme.menu_button("Interfaz y accesibilidad")
	b2.pressed.connect(func() -> void:
		_panel.visible = false
		_hud_settings.visible = true)
	vb.add_child(b2)
	var b_snd := UiTheme.menu_button("Sonido")
	b_snd.pressed.connect(func() -> void:
		_panel.visible = false
		_audio_settings.visible = true)
	vb.add_child(b_snd)
	var b3 := UiTheme.menu_button("Menú principal")
	b3.pressed.connect(func() -> void:
		resume()
		GameFlow.to_main_menu())
	vb.add_child(b3)
	var b4 := UiTheme.menu_button("Salir del juego")
	b4.pressed.connect(func() -> void: get_tree().quit())
	vb.add_child(b4)
	UiTheme.add_ice_edge(panel)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	# game.gd is pausable, so the resume key is handled here (process_mode ALWAYS)
	if visible and event.is_action_pressed("pause"):
		resume()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	_panel.visible = true
	_hud_settings.visible = false
	_audio_settings.visible = false
	GameFlow.set_paused(true)


func resume() -> void:
	visible = false
	GameFlow.set_paused(false)
