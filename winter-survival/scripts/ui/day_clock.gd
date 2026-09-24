class_name DayClock
extends Control
## "Día N" disc with a progress ring (06:00 → 06:00) and a sun/moon icon.

var _label: Label
var _sun: Control
var _moon: Control
var _progress: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(64, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiTheme.label("Día 1", 12, UiTheme.TEXT, true)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.offset_top = 4
	add_child(_label)
	_sun = UiIcons.make("sun", 14, Color("#FFD166"))
	_sun.position = Vector2(25, -2)
	_sun.size = Vector2(14, 14)
	add_child(_sun)
	_moon = UiIcons.make("moon", 14, Color("#DCEBFA"))
	_moon.position = Vector2(25, -2)
	_moon.size = Vector2(14, 14)
	_moon.visible = false
	add_child(_moon)
	Events.time_changed.connect(_on_time)
	_on_time(GameState.day, GameState.hour, GameState.is_night)


func _on_time(day: int, hour: float, night: bool) -> void:
	_label.text = "Día %d" % day
	var h := hour - Balance.NIGHT_END
	if h < 0.0:
		h += 24.0
	_progress = h / 24.0
	_sun.visible = not night
	_moon.visible = night
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := 27.0
	draw_circle(c, r + 3.0, Color("#101826", 0.8))
	draw_arc(c, r, 0.0, TAU, 56, Color("#101826", 0.9), 4.0, true)
	if _progress > 0.0:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * _progress, 56, Color("#DCEBFA"), 4.0, true)
	draw_arc(c, r + 3.0, 0.0, TAU, 56, Color("#DCEBFA", 0.25), 1.0, true)
