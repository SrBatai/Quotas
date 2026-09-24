class_name Hud
extends Control
## In-game HUD: vignettes, region banner + toasts, clock + rings, quest panel, category bar, context label, hotbar.

const FROST_SHADER := preload("res://assets/shaders/frost_vignette.gdshader")

var frost: ColorRect
var red: ColorRect
var region_banner: RegionBanner
var toasts: ToastStack
var day_clock: DayClock
var rings: Dictionary = {}
var weather_label: Label
var coat_icon: Control
var quest_panel: QuestPanel
var category_bar: CategoryBar
var context_label: Label
var hotbar: Hotbar
var _hover_text: String = ""
var _placement_text: String = ""
var _blink: float = 0.0


func _ready() -> void:
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_vignettes()
	_build_top_center()
	_build_top_right()
	_build_quests()
	_build_left()
	_build_bottom()
	Events.stat_changed.connect(_on_stat)
	Events.hover_changed.connect(_on_hover)
	Events.placement_mode.connect(_on_placement)
	Events.weather_changed.connect(func(_w: StringName) -> void: _update_weather())
	Events.inventory_changed.connect(func() -> void: coat_icon.visible = Inventory.has_coat)
	_update_weather()


func _build_vignettes() -> void:
	frost = ColorRect.new()
	frost.name = "Vignette"
	frost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = FROST_SHADER
	m.set_shader_parameter("strength", 0.0)
	m.set_shader_parameter("tint", Color("#BFE3F0"))
	frost.material = m
	add_child(frost)
	red = ColorRect.new()
	red.name = "RedVignette"
	red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	red.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m2 := ShaderMaterial.new()
	m2.shader = FROST_SHADER
	m2.set_shader_parameter("strength", 0.0)
	m2.set_shader_parameter("tint", Color("#B0202A"))
	m2.set_shader_parameter("inner", 0.8)
	red.material = m2
	add_child(red)


func _build_top_center() -> void:
	var vb := VBoxContainer.new()
	vb.name = "TopCenter"
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.set_anchors_preset(Control.PRESET_CENTER_TOP)
	vb.offset_left = -150
	vb.offset_right = 150
	vb.offset_top = 14
	vb.alignment = BoxContainer.ALIGNMENT_BEGIN
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(center)
	region_banner = RegionBanner.new()
	region_banner.name = "RegionBanner"
	center.add_child(region_banner)
	toasts = ToastStack.new()
	toasts.name = "Toasts"
	vb.add_child(toasts)


func _build_top_right() -> void:
	var vb := VBoxContainer.new()
	vb.name = "TopRight"
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	vb.offset_left = -200
	vb.offset_right = -16
	vb.offset_top = 12
	vb.alignment = BoxContainer.ALIGNMENT_BEGIN
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var c1 := CenterContainer.new()
	c1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(c1)
	day_clock = DayClock.new()
	day_clock.name = "DayClock"
	c1.add_child(day_clock)
	var c2 := CenterContainer.new()
	c2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(c2)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 8)
	c2.add_child(hb)
	for spec in [[&"hunger", "drumstick", UiTheme.HUNGER], [&"health", "heart", UiTheme.HEALTH], [&"warmth", "thermometer", UiTheme.WARMTH]]:
		var r := RingMeter.new()
		r.stat = spec[0]
		r.icon_name = spec[1]
		r.color = spec[2]
		r.name = String(spec[0]).capitalize()
		hb.add_child(r)
		rings[spec[0]] = r
	weather_label = UiTheme.label("VENTISCA", 12, UiTheme.DANGER, false, true, true)
	weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weather_label.visible = false
	vb.add_child(weather_label)
	var c3 := CenterContainer.new()
	c3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(c3)
	coat_icon = UiIcons.make("coat", 22, Color("#DCEBFA"))
	coat_icon.tooltip_text = "Abrigo de piel"
	coat_icon.visible = false
	c3.add_child(coat_icon)


func _build_quests() -> void:
	quest_panel = QuestPanel.new()
	quest_panel.name = "QuestPanel"
	quest_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	quest_panel.offset_left = -266
	quest_panel.offset_right = -16
	quest_panel.offset_top = -120
	quest_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(quest_panel)


func _build_left() -> void:
	category_bar = CategoryBar.new()
	category_bar.name = "CategoryBar"
	category_bar.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	category_bar.offset_left = 16
	category_bar.offset_top = -160
	add_child(category_bar)


func _build_bottom() -> void:
	var vb := VBoxContainer.new()
	vb.name = "Bottom"
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	vb.offset_left = -300
	vb.offset_right = 300
	vb.offset_bottom = -12
	vb.offset_top = -100
	vb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	context_label = UiTheme.label("", 12, UiTheme.TEXT, true)
	context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	context_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	context_label.add_theme_constant_override("shadow_offset_y", 1)
	context_label.add_theme_constant_override("shadow_offset_x", 1)
	vb.add_child(context_label)
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(c)
	hotbar = Hotbar.new()
	hotbar.name = "Hotbar"
	c.add_child(hotbar)


func _on_stat(stat: StringName, value: float, _max: float) -> void:
	if stat == &"warmth":
		var s := clampf(1.0 - value / Balance.COLD_VIGNETTE_START, 0.0, 1.0)
		(frost.material as ShaderMaterial).set_shader_parameter("strength", s)
	elif stat == &"health":
		var s := clampf(1.0 - value / Balance.LOW_HEALTH, 0.0, 1.0) * 0.6
		(red.material as ShaderMaterial).set_shader_parameter("strength", s)


func _on_hover(text: String) -> void:
	_hover_text = text
	_update_context()


func _on_placement(active: bool) -> void:
	_placement_text = "Clic: colocar · Clic derecho: cancelar" if active else ""
	_update_context()


func _update_context() -> void:
	context_label.text = _placement_text if _placement_text != "" else _hover_text


func _update_weather() -> void:
	weather_label.visible = GameState.weather == &"blizzard"


func _process(delta: float) -> void:
	if weather_label.visible:
		_blink += delta
		weather_label.modulate.a = 0.6 + 0.4 * absf(sin(_blink * 3.0))
