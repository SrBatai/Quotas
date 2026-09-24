class_name RegionBanner
extends PanelContainer
## Top-center "REGIÓN / NOMBRE" banner; full opacity for 3 s after a change, then 55 %.

var _name_label: Label
var _timer: float = 0.0
var _tween: Tween


func _ready() -> void:
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiTheme.flat_box(UiTheme.PANEL_BG, UiTheme.BORDER, 1, 3, 8))
	custom_minimum_size = Vector2(190, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vb)
	var small := UiTheme.label("REGIÓN", 8, UiTheme.TEXT_2, false, true, true)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(small)
	_name_label = UiTheme.label("CLARO", 18, UiTheme.TEXT, false, true, true)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_name_label)
	var icon := UiIcons.make("mountain", 22, Color("#DCEBFA"))
	icon.position = Vector2(-11, -14)
	icon.size = Vector2(22, 22)
	icon.set_anchors_preset(Control.PRESET_CENTER_TOP)
	icon.offset_left = -11
	icon.offset_right = 11
	icon.offset_top = -13
	icon.offset_bottom = 9
	add_child(icon)
	UiTheme.add_ice_edge(self)
	modulate.a = 0.55
	Events.region_changed.connect(show_region)


func show_region(region_name: String) -> void:
	_name_label.text = region_name
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 1.0
	scale = Vector2(1.0, 1.0)
	_tween = create_tween()
	_tween.tween_interval(3.0)
	_tween.tween_property(self, "modulate:a", 0.55, 0.6)
