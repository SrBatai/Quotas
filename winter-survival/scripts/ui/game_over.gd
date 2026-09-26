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
		&"zombi": return "Zombis"
		&"jugador": return "Otro superviviente"
		&"rendirse": return "Te rendiste"
	return "Frío"


## One-line tip per cause (GDD v2 §13 "Muerte: causa, consejo de 1 línea").
static func tip(cause: StringName) -> String:
	match cause:
		&"zombi": return "Los congelados despiertan con el ruido: usa el cuchillo."
		&"lobo": return "El fuego y la antorcha mantienen lejos a los lobos."
		&"hambre": return "Come antes de salir: la carne asada llena más."
		&"rendirse": return "Un compañero puede reanimarte si aguantas."
	return "Vuelve a la estufa antes de que caiga la noche."


var _respawn_at: float = 0.0


var _won_mode: bool = false


## Death: the world keeps running (persistent server); "Reaparecer" asks the server for a respawn.
func show_death(days: int, hours: int, cause: StringName) -> void:
	_won_mode = false
	_title.text = "HAS MUERTO"
	_title.add_theme_color_override("font_color", UiTheme.DANGER)
	_line1.text = "Sobreviviste %d %s y %d %s" % [days, "día" if days == 1 else "días", hours, "hora" if hours == 1 else "horas"]
	_line2.text = "Causa: %s · %s\nTu mochila se queda en tu cadáver." % [cause_text(cause), tip(cause)]
	_respawn_at = Time.get_ticks_msec() / 1000.0 + StatsComponent.respawn_delay
	_update_retry()
	visible = true


func _update_retry() -> void:
	if _won_mode:
		return
	var left := _respawn_at - Time.get_ticks_msec() / 1000.0
	_retry.disabled = left > 0.0
	_retry.text = "Reaparecer en la base (%d s)" % int(ceil(left)) if left > 0.0 else "Reaparecer en la base"


func _process(_delta: float) -> void:
	if visible and not _won_mode:
		_update_retry()


## Five days survived: an achievement in the persistent world, not an end.
func show_win(_days: int) -> void:
	_won_mode = true
	_title.text = "¡HAS SOBREVIVIDO!"
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_line1.text = "Cinco días en el bosque helado."
	_line2.text = "Mejor marca: %d días" % GameFlow.best_days
	_retry.disabled = false
	_retry.text = "Seguir jugando"
	visible = true


func _on_retry() -> void:
	if _won_mode:
		visible = false
	else:
		GameFlow.request_respawn()
