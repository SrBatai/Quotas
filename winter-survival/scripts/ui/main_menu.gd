extends Node3D
## Main menu: decorative world at dusk + title, buttons (play = hosted local server, join = remote server),
## controls, best score and the last connection message.

var _controls: ControlsPanel
var _menu_box: VBoxContainer
var _join_box: VBoxContainer
var _address: LineEdit
var _password: LineEdit
var _name_edit: LineEdit
var _message: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameFlow.in_game = false
	var layer := $UI as CanvasLayer
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_menu_box = VBoxContainer.new()
	_menu_box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_menu_box.offset_left = 80
	_menu_box.offset_top = -190
	_menu_box.add_theme_constant_override("separation", 10)
	root.add_child(_menu_box)
	var title := UiTheme.label("VENTISCA", 64, UiTheme.TEXT, false, true, true)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("shadow_offset_y", 3)
	_menu_box.add_child(title)
	var sub := UiTheme.label("Sobrevive en el bosque helado, solo o con amigos", 16, Color("#DCEBFA"))
	sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	sub.add_theme_constant_override("shadow_offset_y", 1)
	_menu_box.add_child(sub)
	_menu_box.add_child(UiTheme.spacer(4, 14))
	var play := UiTheme.menu_button("Jugar")
	play.pressed.connect(func() -> void:
		_set_message("Arrancando el servidor local…" if GameFlow.can_host_process() else "")
		GameFlow.play_solo())
	_menu_box.add_child(play)
	if GameFlow.can_join_network():
		var join := UiTheme.menu_button("Unirse a servidor")
		join.pressed.connect(_show_join)
		_menu_box.add_child(join)
	var controls := UiTheme.menu_button("Controles")
	controls.pressed.connect(_show_controls)
	_menu_box.add_child(controls)
	if not OS.has_feature("web"):
		var quit := UiTheme.menu_button("Salir")
		quit.pressed.connect(func() -> void: get_tree().quit())
		_menu_box.add_child(quit)
	if GameFlow.best_days > 0:
		_menu_box.add_child(UiTheme.spacer(4, 10))
		var best := UiTheme.label("Mejor marca: %d %s" % [GameFlow.best_days, "día" if GameFlow.best_days == 1 else "días"], 13, Color("#DCEBFA"), true)
		best.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		best.add_theme_constant_override("shadow_offset_x", 1)
		best.add_theme_constant_override("shadow_offset_y", 1)
		best.add_theme_constant_override("shadow_outline_size", 2)
		_menu_box.add_child(best)
	_message = UiTheme.label(GameFlow.last_message, 12, UiTheme.ACCENT, true)
	_message.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_message.add_theme_constant_override("shadow_offset_y", 1)
	_menu_box.add_child(_message)
	GameFlow.last_message = ""
	GameFlow.flow_message.connect(_set_message)
	# join panel
	_join_box = VBoxContainer.new()
	_join_box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_join_box.offset_left = 80
	_join_box.offset_top = -120
	_join_box.add_theme_constant_override("separation", 8)
	_join_box.visible = false
	root.add_child(_join_box)
	_join_box.add_child(UiTheme.label("UNIRSE A UN SERVIDOR", 18, UiTheme.TEXT, false, true, true))
	_join_box.add_child(UiTheme.label("Nombre", 11, UiTheme.TEXT_2))
	_name_edit = LineEdit.new()
	_name_edit.text = Identity.player_name
	_name_edit.max_length = 24
	_name_edit.custom_minimum_size = Vector2(260, 0)
	_join_box.add_child(_name_edit)
	_join_box.add_child(UiTheme.label("Dirección (ip:puerto)", 11, UiTheme.TEXT_2))
	_address = LineEdit.new()
	_address.text = str(Identity.recent[0]) if not Identity.recent.is_empty() else "127.0.0.1:%d" % Net.DEFAULT_PORT
	_address.custom_minimum_size = Vector2(260, 0)
	_join_box.add_child(_address)
	_join_box.add_child(UiTheme.label("Contraseña", 11, UiTheme.TEXT_2))
	_password = LineEdit.new()
	_password.secret = true
	_password.custom_minimum_size = Vector2(260, 0)
	_join_box.add_child(_password)
	_join_box.add_child(UiTheme.spacer(4, 6))
	var connect_btn := UiTheme.primary_button("CONECTAR")
	connect_btn.pressed.connect(_on_connect)
	_join_box.add_child(connect_btn)
	var back := UiTheme.menu_button("Volver")
	back.pressed.connect(func() -> void:
		_join_box.visible = false
		_menu_box.visible = true)
	_join_box.add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_controls = ControlsPanel.new()
	_controls.visible = false
	_controls.back.connect(func() -> void: _controls.visible = false; _menu_box.visible = true)
	center.add_child(_controls)
	var version := UiTheme.label("Godot 4.7 · %s · protocolo %d" % [Net.GAME_VERSION, Net.NET_PROTOCOL], 10, Color("#DCEBFA", 0.85))
	version.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	version.add_theme_constant_override("shadow_offset_x", 1)
	version.add_theme_constant_override("shadow_offset_y", 1)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -260
	version.offset_top = -24
	version.offset_right = -12
	version.offset_bottom = -8
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(version)


func _set_message(text: String) -> void:
	if _message != null:
		_message.text = text


func _show_controls() -> void:
	_controls.visible = true
	_menu_box.visible = false


func _show_join() -> void:
	_join_box.visible = true
	_menu_box.visible = false


func _on_connect() -> void:
	Identity.set_player_name(_name_edit.text)
	var addr := _address.text.strip_edges()
	var host := addr
	var port := Net.DEFAULT_PORT
	var colon := addr.rfind(":")
	if colon > 0:
		host = addr.substr(0, colon)
		port = int(addr.substr(colon + 1))
	if host == "":
		host = "127.0.0.1"
	GameFlow.join(host, port, _password.text)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		if _controls.visible:
			_controls.visible = false
			_menu_box.visible = true
		elif _join_box.visible:
			_join_box.visible = false
			_menu_box.visible = true
