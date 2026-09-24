extends Node3D
## Main menu: decorative world at dusk + title, buttons, best score.

var _controls: ControlsPanel
var _menu_box: VBoxContainer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.is_running = false
	GameState.is_game_over = false
	GameState.set_time(1, 19.3)
	var layer := $UI as CanvasLayer
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_menu_box = VBoxContainer.new()
	_menu_box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_menu_box.offset_left = 80
	_menu_box.offset_top = -170
	_menu_box.add_theme_constant_override("separation", 10)
	root.add_child(_menu_box)
	var title := UiTheme.label("VENTISCA", 64, UiTheme.TEXT, false, true, true)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("shadow_offset_y", 3)
	_menu_box.add_child(title)
	var sub := UiTheme.label("Sobrevive 5 días en el bosque helado", 16, Color("#DCEBFA"))
	sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	sub.add_theme_constant_override("shadow_offset_y", 1)
	_menu_box.add_child(sub)
	_menu_box.add_child(UiTheme.spacer(4, 14))
	var play := UiTheme.menu_button("Jugar")
	play.pressed.connect(func() -> void: GameState.start_game())
	_menu_box.add_child(play)
	var controls := UiTheme.menu_button("Controles")
	controls.pressed.connect(_show_controls)
	_menu_box.add_child(controls)
	var quit := UiTheme.menu_button("Salir")
	quit.pressed.connect(func() -> void: get_tree().quit())
	_menu_box.add_child(quit)
	if GameState.best_days > 0:
		_menu_box.add_child(UiTheme.spacer(4, 10))
		_menu_box.add_child(UiTheme.label("Mejor marca: %d %s" % [GameState.best_days, "día" if GameState.best_days == 1 else "días"], 13, UiTheme.TEXT_2))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_controls = ControlsPanel.new()
	_controls.visible = false
	_controls.back.connect(func() -> void: _controls.visible = false; _menu_box.visible = true)
	center.add_child(_controls)
	var version := UiTheme.label("Godot 4.7 · vertical slice", 10, Color("#93A6BF", 0.7))
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -220
	version.offset_top = -24
	version.offset_right = -12
	version.offset_bottom = -8
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(version)


func _show_controls() -> void:
	_controls.visible = true
	_menu_box.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") and _controls.visible:
		_controls.visible = false
		_menu_box.visible = true
