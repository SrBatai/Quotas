class_name RegionBanner
extends Control
## Top-center "REGIÓN / NOMBRE" banner with a mountain icon riding on the top edge.
## Full opacity for 3 s after a change, then dimmed.

var panel: PanelContainer
var _name_label: Label
var _tween: Tween


func _ready() -> void:
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiTheme.flat_box(Color("#1E2A3A", 0.94), UiTheme.BORDER, 1, 3, 8)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 6
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_top = 10
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)
	var small := UiTheme.label("REGIÓN", 8, UiTheme.TEXT_2, false, true, true)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(small)
	_name_label = UiTheme.label("CLARO", 18, UiTheme.TEXT, false, true, true)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_name_label)
	UiTheme.add_ice_edge(panel)
	var icon := UiIcons.make("mountain", 24, Color("#DCEBFA"))
	icon.set_anchors_preset(Control.PRESET_CENTER_TOP)
	icon.offset_left = -12
	icon.offset_right = 12
	icon.offset_top = 0
	icon.offset_bottom = 24
	add_child(icon)
	panel.minimum_size_changed.connect(_update_min)
	_update_min()
	modulate.a = 0.8
	Events.region_changed.connect(show_region)


func _update_min() -> void:
	custom_minimum_size = panel.get_combined_minimum_size() + Vector2(0, 10)


func show_region(region_name: String) -> void:
	_name_label.text = region_name
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(3.0)
	_tween.tween_property(self, "modulate:a", 0.8, 0.6)
