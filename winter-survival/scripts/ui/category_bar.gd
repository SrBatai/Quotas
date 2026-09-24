class_name CategoryBar
extends PanelContainer
## Vertical toolbar with the six crafting categories.

signal category_pressed(category: StringName)

var _buttons: Dictionary = {}
var active: StringName = &""


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.flat_box(UiTheme.PANEL_BG, UiTheme.BORDER, 1, 5, 5))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	add_child(col)
	for cat in Recipes.CATEGORIES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(42, 42)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = Recipes.TITLES[cat].capitalize()
		var icon := UiIcons.make(Recipes.CATEGORY_ICONS[cat], 22, Color.WHITE)
		icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		icon.position = Vector2(10, 10)
		icon.size = Vector2(22, 22)
		b.add_child(icon)
		b.pressed.connect(func() -> void: category_pressed.emit(cat))
		col.add_child(b)
		_buttons[cat] = b
	UiTheme.add_ice_edge(self)


func set_active(cat: StringName) -> void:
	active = cat
	for c in _buttons:
		var b: Button = _buttons[c]
		if c == cat:
			b.add_theme_stylebox_override("normal", UiTheme.flat_box(Color("#2A3A50", 0.95), UiTheme.ICE, 1, 4, 8))
		else:
			b.remove_theme_stylebox_override("normal")
