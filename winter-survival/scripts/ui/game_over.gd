class_name GameOverScreen
extends Control
## Death and victory screens (GDD §14).

var _title: Label
var _line1: Label
var _line2: Label
var _retry: Button


func _ready() -> void:
	theme = UiTheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color("#0B1220", 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.flat_box(UiTheme.PANEL_BG_SOLID, UiTheme.BORDER, 1, 5, 28))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	_title = UiTheme.label("HAS MUERTO", 30, UiTheme.TEXT, false, true, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)
	_line1 = UiTheme.label("", 14, UiTheme.TEXT)
	_line1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_line1)
	_line2 = UiTheme.label("", 13, UiTheme.TEXT_2)
	_line2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_line2)
	vb.add_child(UiTheme.spacer(4, 10))
	_retry = UiTheme.menu_button("Reaparecer")
	_retry.pressed.connect(_on_retry)
	vb.add_child(_retry)
	var menu := UiTheme.menu_button("Menú principal")
	menu.pressed.connect(func() -> void: GameFlow.to_main_menu())
	vb.add_child(menu)
	UiTheme.add_ice_edge(panel)
	visible = false


static func cause_text(cause: StringName) -> String:
	match cause:
		&"frio": return "Frío"
		&"hambre": return "Hambre"
		&"lobo": return "Lobos"
	return "Frío"


var _won_mode: bool = false


## Death: the world keeps running (persistent server); "Reaparecer" asks the server for a respawn.
func show_death(days: int, hours: int, cause: StringName) -> void:
	_won_mode = false
	_title.text = "HAS MUERTO"
	_title.add_theme_color_override("font_color", UiTheme.DANGER)
	_line1.text = "Sobreviviste %d %s y %d %s" % [days, "día" if days == 1 else "días", hours, "hora" if hours == 1 else "horas"]
	_line2.text = "Causa: %s" % cause_text(cause)
	_retry.text = "Reaparecer"
	visible = true


## Five days survived: an achievement in the persistent world, not an end.
func show_win(_days: int) -> void:
	_won_mode = true
	_title.text = "¡HAS SOBREVIVIDO!"
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_line1.text = "Cinco días en el bosque helado."
	_line2.text = "Mejor marca: %d días" % GameFlow.best_days
	_retry.text = "Seguir jugando"
	visible = true


func _on_retry() -> void:
	if _won_mode:
		visible = false
	else:
		GameFlow.request_respawn()
