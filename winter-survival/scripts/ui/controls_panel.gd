class_name ControlsPanel
extends PanelContainer
## Controls summary (GDD §4.2) with a "Volver" button.

signal back()

const ROWS := [
	["Moverse", "W A S D / flechas · Stick izquierdo"],
	["Correr", "Mayús (mantener) · L3"],
	["Interactuar / atacar bajo el cursor", "Clic izquierdo (R: lo más cercano) · X"],
	["Golpe cargado (arma en mano)", "Mantener clic / Espacio · mantener RT"],
	["Atacar al más cercano (zombi, lobo)", "Espacio · RT"],
	["Empujar", "V · LT"],
	["Pisotear / ejecutar", "Clic sobre un zombi derribado / con cuchillo por la espalda"],
	["Agacharse (sigilo)", "Ctrl · R3"],
	["Reanimar a un compañero", "Mantener R · mantener X"],
	["Rendirse (derribado)", "Mantener X · mantener Y"],
	["Cancelar / cerrar panel", "Clic derecho, Esc · B"],
	["Pausa", "Esc · Start"],
	["Girar cámara", "Q / E · LB / RB"],
	["Zoom", "Rueda del ratón · D-pad arriba/abajo"],
	["Ranura de la barra", "Teclas 1–9 · D-pad izq/der + A"],
	["Fabricación", "Tab · Y"],
	["Equipar/guardar antorcha", "T · D-pad abajo (mantener)"],
	["Comer lo mejor disponible", "F"],
	["Chat / comandos", "Intro"],
]


func _ready() -> void:
	theme = UiTheme.get_theme()
	add_theme_stylebox_override("panel", UiTheme.flat_box(UiTheme.PANEL_BG_SOLID, UiTheme.BORDER, 1, 5, 20))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var title := UiTheme.label("CONTROLES", 22, UiTheme.TEXT, false, true, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)
	for r in ROWS:
		grid.add_child(UiTheme.label(r[0], 12, UiTheme.TEXT, true))
		grid.add_child(UiTheme.label(r[1], 12, UiTheme.TEXT_2))
	vb.add_child(UiTheme.spacer(4, 6))
	var b := UiTheme.menu_button("Volver")
	b.pressed.connect(func() -> void: back.emit())
	vb.add_child(b)
	UiTheme.add_ice_edge(self)
