class_name Whisper
## Drawing primitives of the HUD v2 «Susurro» (docs/research/10_hud_ux.md §V.2.3): 1 px hairlines that fade at
## both ends, 10 px diamonds (filled = tracked, hollow = the rest), thin 40 px rings without a disc, the 6 px edge
## arrow, 1.5 px line icons (assets/icons/line/*.svg) and input glyphs (key cap / gamepad button). Everything is
## drawn from a `_draw()` with a soft drop shadow so it reads on snow and at night.

const ICON_DIR := "res://assets/icons/line/"
static var _icons: Dictionary = {}
static var _cap: StyleBoxFlat


static func icon(icon_name: String) -> Texture2D:
	if not _icons.has(icon_name):
		var path := ICON_DIR + icon_name + ".svg"
		_icons[icon_name] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _icons[icon_name]


## Hairline from `a` to `b` (horizontal), fading at 18 % / 82 % (`fade` = both ends), or only toward `b`
## (`fade_end`, like `.hair.l`), in `color` (default hair).
static func hair(ci: CanvasItem, a: Vector2, b: Vector2, color: Color = UiTokens.HAIR, fade: int = 0, alpha: float = 1.0) -> void:
	if a.distance_to(b) < 0.5:
		return
	var c := Color(color, color.a * alpha)
	var t0 := Color(c, 0.0)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	match fade:
		0:   # both ends
			pts = PackedVector2Array([a, a.lerp(b, UiTokens.HAIR_FADE_A), a.lerp(b, UiTokens.HAIR_FADE_B), b])
			cols = PackedColorArray([t0, c, c, t0])
		1:   # fades toward b (left-anchored rule)
			pts = PackedVector2Array([a, a.lerp(b, 0.6), b])
			cols = PackedColorArray([c, c, t0])
		2:   # fades toward a (right-anchored rule)
			pts = PackedVector2Array([a, a.lerp(b, 0.4), b])
			cols = PackedColorArray([t0, c, c])
		3:   # accent: solid then 60 % at 55 %, transparent at the end
			pts = PackedVector2Array([a, a.lerp(b, 0.55), b])
			cols = PackedColorArray([c, Color(c, c.a * 0.6), t0])
	ci.draw_polyline_colors(pts, cols, 1.0, false)


## Diamond of side `size` centred on `p` (rotated square). `filled` = tracked / accent.
static func diamond(ci: CanvasItem, p: Vector2, size: float, color: Color, filled: bool, alpha: float = 1.0, shadow: bool = true) -> void:
	var h := size * 0.7071
	var pts := PackedVector2Array([p + Vector2(0, -h), p + Vector2(h, 0), p + Vector2(0, h), p + Vector2(-h, 0)])
	var c := Color(color, color.a * alpha)
	if shadow:
		var sh := PackedVector2Array()
		for q in pts:
			sh.append(q + Vector2(0, 1))
		sh.append(sh[0])
		ci.draw_polyline(sh, Color(0, 0, 0, 0.45 * alpha), 3.0, true)
	if filled:
		ci.draw_colored_polygon(pts, c)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, c, 1.5, true)


## Colour-blind safe marker: a different shape per kind (§V.7): objective = diamond, heat = triangle,
## teammate = circle, downed = square, other = diamond.
static func marker(ci: CanvasItem, p: Vector2, kind: StringName, size: float, color: Color, filled: bool, alpha: float = 1.0) -> void:
	if not bool(UiSettings.get_value("colorblind")) or kind == &"objective" or kind == &"":
		diamond(ci, p, size, color, filled, alpha)
		return
	var c := Color(color, color.a * alpha)
	var pts := PackedVector2Array()
	match kind:
		&"heat":
			var h := size * 0.62
			pts = PackedVector2Array([p + Vector2(0, -h), p + Vector2(h, h * 0.8), p + Vector2(-h, h * 0.8)])
		&"downed":
			var h := size * 0.5
			pts = PackedVector2Array([p + Vector2(-h, -h), p + Vector2(h, -h), p + Vector2(h, h), p + Vector2(-h, h)])
		_:
			ci.draw_circle(p + Vector2(0, 1), size * 0.5 + 1.0, Color(0, 0, 0, 0.4 * alpha))
			if filled:
				ci.draw_circle(p, size * 0.5, c)
			ci.draw_arc(p, size * 0.5, 0.0, TAU, 20, c, 1.5, true)
			return
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, Color(0, 0, 0, 0.45 * alpha), 3.0, true)
	if filled:
		ci.draw_colored_polygon(pts, c)
	ci.draw_polyline(closed, c, 1.5, true)


## Thin ring (§V.2.3): track at 22 % ink, value arc from 12 o'clock clockwise, faint shadow disc behind.
static func ring(ci: CanvasItem, c: Vector2, diameter: float, value: float, color: Color, stroke: float = UiTokens.RING_STROKE, alpha: float = 1.0, track: bool = true) -> void:
	var r := diameter * 0.5 - stroke
	ci.draw_circle(c, r + 5.0, Color(UiTokens.SCRIM_RGB, 0.22 * alpha))
	if track:
		ci.draw_arc(c, r, 0.0, TAU, 48, Color(UiTokens.INK_RGB, 0.22 * alpha), stroke, true)
	var v := clampf(value, 0.0, 1.0)
	if v > 0.001:
		ci.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * v, maxi(int(48.0 * v), 4), Color(color, color.a * alpha), stroke, true)


## Edge arrow (6 px) at `p` pointing along `dir` (unit vector, screen space).
static func arrow(ci: CanvasItem, p: Vector2, dir: Vector2, color: Color, alpha: float = 1.0) -> void:
	var d := dir.normalized()
	var n := Vector2(-d.y, d.x)
	var s := UiTokens.EDGE_ARROW
	var pts := PackedVector2Array([p + d * s, p - d * s * 0.33 + n * s, p - d * s * 0.33 - n * s])
	var sh := PackedVector2Array()
	for q in pts:
		sh.append(q + Vector2(0, 1))
	ci.draw_colored_polygon(sh, Color(0, 0, 0, 0.5 * alpha))
	ci.draw_colored_polygon(pts, Color(color, color.a * alpha))


## Line icon centred on `c` at `size` px, tinted, with a drop shadow.
static func draw_icon(ci: CanvasItem, icon_name: String, c: Vector2, size: float, color: Color, alpha: float = 1.0) -> void:
	var t := icon(icon_name)
	if t == null:
		return
	var r := Rect2(c - Vector2(size, size) * 0.5, Vector2(size, size))
	ci.draw_texture_rect(t, Rect2(r.position + Vector2(0, 1), r.size), false, Color(0, 0, 0, 0.55 * alpha))
	ci.draw_texture_rect(t, r, false, Color(color, color.a * alpha))


## Small arrow glyph (↓ / ↑) drawn with lines (Barlow has no arrows): `up` = rising.
static func trend(ci: CanvasItem, p: Vector2, up: bool, color: Color, h: float = 11.0, alpha: float = 1.0) -> void:
	var c := Color(color, color.a * alpha)
	var top := p + Vector2(0, -h * 0.5)
	var bot := p + Vector2(0, h * 0.5)
	var tip := top if up else bot
	var dy := 4.0 if up else -4.0
	for off in [Vector2(0, 1), Vector2.ZERO]:
		var col := Color(0, 0, 0, 0.5 * alpha) if off != Vector2.ZERO else c
		ci.draw_line(top + off, bot + off, col, 1.5, true)
		ci.draw_line(tip + off, tip + Vector2(-3.5, dy) + off, col, 1.5, true)
		ci.draw_line(tip + off, tip + Vector2(3.5, dy) + off, col, 1.5, true)


## Input glyph: key cap (rounded square, 26 px) for keyboard, circle for a gamepad button. Returns its width.
static func glyph(ci: CanvasItem, p: Vector2, text: String, gamepad: bool, alpha: float = 1.0, size: float = 26.0) -> float:
	var f := UiStyle.font(&"regular", ["tnum"])
	var fs := 16 if size >= 24.0 else 14
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if not text.contains("↑") and not text.contains("↓") else 10.0
	var w := size if gamepad else maxf(size, tw + 12.0)
	var r := Rect2(p - Vector2(w, size) * 0.5, Vector2(w, size))
	var border := Color(UiTokens.INK_RGB, 0.70 * alpha)
	if gamepad:
		ci.draw_circle(p + Vector2(0, 1), size * 0.5, Color(0, 0, 0, 0.35 * alpha))
		ci.draw_arc(p, size * 0.5 - 0.6, 0.0, TAU, 32, border, 1.2, true)
	else:
		if _cap == null:
			_cap = StyleBoxFlat.new()
			_cap.bg_color = Color(0, 0, 0, 0.0)
			_cap.set_border_width_all(1)
			_cap.set_corner_radius_all(5)
			_cap.shadow_size = 3
			_cap.shadow_offset = Vector2(0, 1)
			_cap.anti_aliasing = true
		_cap.border_color = border
		_cap.shadow_color = Color(0, 0, 0, 0.35 * alpha)
		ci.draw_style_box(_cap, r)
	if text == "↑" or text == "↓" or text == "↑↓":
		# Barlow has no arrows: drawn
		if text == "↑↓":
			trend(ci, p + Vector2(-3.5, 0), true, UiTokens.INK_RGB, 10.0, alpha)
			trend(ci, p + Vector2(3.5, 0), false, UiTokens.INK_RGB, 10.0, alpha)
		else:
			trend(ci, p, text == "↑", UiTokens.INK_RGB, 11.0, alpha)
		return w
	var asc := f.get_ascent(fs)
	var desc := f.get_descent(fs)
	var base := Vector2(p.x - tw * 0.5, p.y + (asc - desc) * 0.5 - 1.0)
	ci.draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiTokens.INK_RGB, alpha))
	return w


## Hold ring (§6.9): accent arc of `diameter` filling with `value` around a glyph.
static func hold_ring(ci: CanvasItem, c: Vector2, value: float, alpha: float = 1.0, diameter: float = UiTokens.HOLD_RING) -> void:
	var r := diameter * 0.5
	ci.draw_arc(c, r, 0.0, TAU, 48, Color(UiTokens.INK_RGB, 0.18 * alpha), 2.0, true)
	if value > 0.001:
		ci.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * clampf(value, 0.0, 1.0), 48, Color(UiTokens.ACCENT, alpha), 2.0, true)


## Ellipse arc on the ground plane (screen ratio sin 48°): centre, half-width, from / to angle (rad, 0 = right).
static func ground_arc(ci: CanvasItem, c: Vector2, rx: float, a0: float, a1: float, color: Color, width: float) -> void:
	var n := 24
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / float(n))
		pts.append(c + Vector2(cos(a) * rx, sin(a) * rx * UiTokens.GROUND_RATIO))
	ci.draw_polyline(pts, color, width, true)


static func ground_ellipse(ci: CanvasItem, c: Vector2, rx: float, color: Color, width: float) -> void:
	ground_arc(ci, c, rx, 0.0, TAU, color, width)
