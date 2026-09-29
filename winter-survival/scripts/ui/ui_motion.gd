class_name UiMotion
## Motion helpers of the HUD (docs/research/10_hud_ux.md §V.2.4): enter with sine ease-out, leave with sine
## ease-in-out; no bounces, no scale, no flashes; slides of 6 px at most. "Movimiento reducido" turns every
## transition into a 200 ms fade and removes the slides and the tracking animation.


static func reduced() -> bool:
	return bool(UiSettings.get_value("reduced_motion"))


## Sine ease-out (enter) on 0..1.
static func ease_in_curve(t: float) -> float:
	return sin(clampf(t, 0.0, 1.0) * PI * 0.5)


## Sine ease-in-out (leave) on 0..1.
static func ease_out_curve(t: float) -> float:
	return 0.5 - 0.5 * cos(clampf(t, 0.0, 1.0) * PI)


## Duration honouring reduced motion.
static func dur(seconds: float) -> float:
	return UiTokens.T_REDUCED if reduced() and seconds > 0.0 else seconds


## Slide offset honouring reduced motion (0 when reduced).
static func slide(px: float) -> float:
	return 0.0 if reduced() else clampf(px, -UiTokens.MOVE_MAX, UiTokens.MOVE_MAX)


## Fades a CanvasItem's modulate alpha with the enter / leave curves; returns the Tween.
static func fade(node: CanvasItem, to_alpha: float, seconds: float) -> Tween:
	var tw := node.create_tween()
	tw.set_trans(UiTokens.CURVE_TRANS)
	tw.set_ease(UiTokens.CURVE_IN if to_alpha > node.modulate.a else UiTokens.CURVE_OUT)
	tw.tween_property(node, "modulate:a", to_alpha, dur(seconds))
	return tw


## Pulse factor 0..1 at `hz` (a flat 1 with reduced flashes).
static func pulse(t: float, hz: float) -> float:
	if bool(UiSettings.get_value("reduced_flashes")):
		return 1.0
	return 0.5 + 0.5 * sin(t * TAU * hz)
