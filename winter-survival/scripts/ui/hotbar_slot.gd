class_name HotbarSlot
extends Control
## One inventory / container slot: icon, count, MANO caption, "+" when empty, food bonus badge.

signal pressed(index: int, shift: bool)

var index: int = 0
var is_hand: bool = false
var show_bonus: bool = false
var _hover: bool = false
var _icon: Control
var _count: Label
var _caption: Label
var _plus: Label
var _bonus: Label
var _item: StringName = &""


func _ready() -> void:
	custom_minimum_size = Vector2(52, 52)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_plus = UiTheme.label("+", 20, Color("#93A6BF", 0.6))
	_plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_plus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_plus)
	_caption = UiTheme.label("MANO", 7, UiTheme.TEXT_2, true, true)
	_caption.position = Vector2(4, 2)
	_caption.add_theme_font_override("font", UiTheme.title_font())
	_caption.visible = false
	add_child(_caption)
	_count = UiTheme.label("", 11, UiTheme.TEXT, true)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.position = Vector2(20, 33)
	_count.size = Vector2(28, 16)
	_count.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_count.add_theme_constant_override("shadow_offset_x", 1)
	_count.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_count)
	_bonus = UiTheme.label("", 9, UiTheme.ACCENT, true)
	_bonus.position = Vector2(3, 2)
	_bonus.visible = false
	add_child(_bonus)
	mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hover = false; queue_redraw())
	gui_input.connect(_on_gui_input)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(index, event.shift_pressed)
		accept_event()


func set_item(entry: Dictionary) -> void:
	if _icon != null:
		_icon.queue_free()
		_icon = null
	if entry.is_empty():
		_item = &""
		_plus.visible = not is_hand
		_count.text = ""
		_bonus.visible = false
		tooltip_text = "Mano vacía" if is_hand else ""
	else:
		_item = entry["id"]
		_plus.visible = false
		# Rendered 3D icons read best filling ~75 % of the 52 px slot, like the reference hotbar.
		_icon = UiIcons.item_icon(_item, 40)
		_icon.position = Vector2(6, 5)
		_icon.size = Vector2(40, 40)
		add_child(_icon)
		move_child(_icon, 0)
		var n := int(entry["count"])
		_count.text = str(n) if n > 1 or not Items.is_tool_item(_item) else ""
		if is_hand and n <= 1:
			_count.text = ""
		tooltip_text = Items.describe(_item)
		var bonus := int(Items.food_delta(_item, "hunger"))
		_bonus.visible = show_bonus and bonus != 0
		_bonus.text = "%+d" % bonus
	_caption.visible = is_hand
	queue_redraw()


func _draw() -> void:
	var bg := UiTheme.SLOT_HOVER if _hover else UiTheme.SLOT_BG
	var border := UiTheme.ICE if _hover else UiTheme.BORDER
	var sb := UiTheme.flat_box(bg, border, 1, 3, 0)
	if is_hand:
		sb.bg_color = Color("#16202E", 0.85)
		sb.border_color = Color("#DCEBFA", 0.55)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
