class_name RingMeter
extends Control
## Circular stat meter: value arc + centered icon; pulses when low; number on hover.

@export var color: Color = Color("#E8A33C")
@export var icon_name: String = "heart"
@export var stat: StringName = &"hunger"

var value: float = 1.0
var _max: float = 100.0
var _raw: float = 100.0
var _t: float = 0.0
var _hover: bool = false
var _icon: Control
var _num: Label


func _ready() -> void:
	custom_minimum_size = Vector2(56, 56)
	mouse_filter = Control.MOUSE_FILTER_PASS
	pivot_offset = custom_minimum_size * 0.5
	_icon = UiIcons.make(icon_name, 24, Color.WHITE)
	_icon.position = Vector2(16, 16)
	_icon.size = Vector2(24, 24)
	add_child(_icon)
	_num = UiTheme.label("100", 12, UiTheme.TEXT, true)
	_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_num.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_num.visible = false
	add_child(_num)
	mouse_entered.connect(func() -> void: _hover = true; _num.visible = true; _icon.visible = false)
	mouse_exited.connect(func() -> void: _hover = false; _num.visible = false; _icon.visible = true)
	Events.stat_changed.connect(_on_stat)


func _on_stat(s: StringName, v: float, m: float) -> void:
	if s != stat:
		return
	_raw = v
	_max = m
	value = clampf(v / m, 0.0, 1.0) if m > 0.0 else 0.0
	_num.text = str(int(round(v)))
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if value < 0.25:
		var s := 1.0 + 0.08 * maxf(sin(_t * TAU * 1.2), 0.0)
		scale = Vector2(s, s)
	elif scale != Vector2.ONE:
		scale = Vector2.ONE


func _draw() -> void:
	var c := size * 0.5
	var r := 23.0
	draw_circle(c, r + 3.0, Color("#101826", 0.75))
	draw_arc(c, r, 0.0, TAU, 48, Color("#101826", 0.9), 6.0, true)
	if value > 0.0:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * value, 48, color, 6.0, true)
	draw_arc(c, r + 3.0, 0.0, TAU, 48, Color("#DCEBFA", 0.25), 1.0, true)
