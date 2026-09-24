class_name PauseMenu
extends Control
## PAUSA overlay.


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
	var b2 := UiTheme.menu_button("Reiniciar")
	b2.pressed.connect(func() -> void: GameState.restart())
	vb.add_child(b2)
	var b3 := UiTheme.menu_button("Menú principal")
	b3.pressed.connect(func() -> void: GameState.to_main_menu())
	vb.add_child(b3)
	var b4 := UiTheme.menu_button("Salir del juego")
	b4.pressed.connect(func() -> void: get_tree().quit())
	vb.add_child(b4)
	UiTheme.add_ice_edge(panel)
	visible = false


func open() -> void:
	visible = true
	GameState.set_paused(true)


func resume() -> void:
	visible = false
	GameState.set_paused(false)
