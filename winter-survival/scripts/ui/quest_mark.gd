extends Control
## Small circle marker for quest rows: filled check (done), hollow (current), dim (next).

var kind: int = 0


func _draw() -> void:
	var c := size * 0.5
	match kind:
		2:
			draw_circle(c, 5.0, UiTheme.TEXT_2)
			draw_polyline(PackedVector2Array([c + Vector2(-2.5, 0), c + Vector2(-0.5, 2), c + Vector2(2.5, -2)]), Color("#1E2A3A"), 1.5, true)
		1:
			draw_arc(c, 5.0, 0, TAU, 24, UiTheme.TEXT, 1.5, true)
		_:
			draw_arc(c, 5.0, 0, TAU, 24, Color("#93A6BF", 0.5), 1.2, true)
