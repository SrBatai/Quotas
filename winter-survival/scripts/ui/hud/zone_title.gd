class_name ZoneTitle
extends Control
## Cinematic zone title (docs/research/10_hud_ux.md §V.4.4, mockup v2_c): no box, over a 46 % radial veil.
## Eyebrow in small caps ("zona descubierta", .50 em), the name in Barlow Condensed ExtraLight 76 px whose
## tracking closes from .78 em to .42 em while it fades in, ONE 520 px hairline and ONE line of facts
## ("Altavega · sin electricidad · −18 °C · peligro alto"). First visit: 1.4 s in, read until t = 4.0 s, 1.6 s
## out (5.6 s). Re-entry: only the name at 60 % for 2.5 s. Reduced motion: 200 ms fades, no tracking animation.
## Listens to `Events.location_entered` (card = full | compact; H2: "sign" is ZoneSign's); `is_showing()` makes
## banners wait. Sound (appendix §5.6): `ui_zone_discover` on a first visit only — a re-entry is silent.

const TOP := 268.0
const TITLE_COLOR := Color("#F6FAFE")

var info: Dictionary = {}
var t: float = -1.0
var shown_count: int = 0
var _title_font: FontVariation
var _veil: Scrim
var _duration: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_font = FontVariation.new()
	_title_font.base_font = UiStyle.font_file(&"cond_extralight")
	_veil = Scrim.new()
	_veil.name = "Veil"
	_veil.fixed_alpha = 0.46
	add_child(_veil)
	visible = false
	Events.location_entered.connect(_on_location)


func _on_location(i: Dictionary) -> void:
	var card := str(i.get("card", "none"))
	if card != "full" and card != "compact":
		return
	show_card(i)


## Starts the card now (public: screenshots / tests; `at` = start the timeline at that second).
func show_card(i: Dictionary, at: float = 0.0) -> void:
	info = i
	t = at
	shown_count += 1
	_duration = _total()
	visible = true
	_update_veil()
	if bool(i.get("first_visit", false)) and at == 0.0:
		AudioManager.play(&"ui_zone_discover")
	queue_redraw()


func is_showing() -> bool:
	return t >= 0.0 and t < _duration


func is_full() -> bool:
	return str(info.get("card", "")) == "full"


func _total() -> float:
	if UiMotion.reduced():
		return UiTokens.T_REDUCED * 2.0 + (UiTokens.T_ZONE_FIRST[1] if is_full() else UiTokens.T_ZONE_REENTRY[1])
	if is_full():
		return float(UiTokens.T_ZONE_FIRST[1]) + float(UiTokens.T_ZONE_FIRST[2])
	return float(UiTokens.T_ZONE_REENTRY[0]) + float(UiTokens.T_ZONE_REENTRY[1]) + float(UiTokens.T_ZONE_REENTRY[2])


func _process(delta: float) -> void:
	if t < 0.0:
		return
	t += delta
	if t >= _duration:
		t = -1.0
		visible = false
		return
	_update_veil()
	queue_redraw()


func _update_veil() -> void:
	var f := frame(t)
	var full := is_full()
	_veil.position = Vector2(size.x * 0.08, TOP - 78.0 if full else TOP - 10.0)
	_veil.size = Vector2(size.x * 0.84, 330.0 if full else 200.0)
	_veil.modulate.a = float(f["veil"])


## Timeline values at time `tt`: {title_a, em, eyebrow_a, facts_a, rule, veil}.
func frame(tt: float) -> Dictionary:
	var f := {"title_a": 0.0, "em": UiTokens.ZONE_TITLE_EM, "eyebrow_a": 0.0, "facts_a": 0.0, "rule": 0.0, "veil": 0.0}
	if UiMotion.reduced():
		var r := UiTokens.T_REDUCED
		var hold := float(UiTokens.T_ZONE_FIRST[1]) if is_full() else float(UiTokens.T_ZONE_REENTRY[1])
		var a := clampf(tt / r, 0.0, 1.0) * clampf((r * 2.0 + hold - tt) / r, 0.0, 1.0)
		f["title_a"] = a * (1.0 if is_full() else 0.6)
		f["veil"] = a * (1.0 if is_full() else 0.6)
		if is_full():
			f["eyebrow_a"] = a
			f["facts_a"] = a
			f["rule"] = UiTokens.ZONE_RULE * a
		return f
	if not is_full():
		var tin: float = UiTokens.T_ZONE_REENTRY[0]
		var hold: float = UiTokens.T_ZONE_REENTRY[1]
		var tout: float = UiTokens.T_ZONE_REENTRY[2]
		var a := UiMotion.ease_in_curve(tt / tin) if tt < tin else (1.0 if tt < tin + hold else 1.0 - UiMotion.ease_out_curve((tt - tin - hold) / tout))
		f["title_a"] = 0.6 * a
		f["veil"] = 0.55 * a
		return f
	var tin_f: float = UiTokens.T_ZONE_FIRST[0]
	var until: float = UiTokens.T_ZONE_FIRST[1]
	var out_f: float = UiTokens.T_ZONE_FIRST[2]
	if tt < until:
		var k := clampf(tt / tin_f, 0.0, 1.0)
		f["title_a"] = UiMotion.ease_in_curve(k)
		f["em"] = lerpf(UiTokens.ZONE_TITLE_EM_FROM, UiTokens.ZONE_TITLE_EM, UiMotion.ease_out_curve(k))   # letters stay open early (mockup frame 1)
		f["eyebrow_a"] = UiMotion.ease_in_curve(clampf((tt - 0.6) / 0.8, 0.0, 1.0))
		f["facts_a"] = UiMotion.ease_in_curve(clampf((tt - 0.8) / 0.8, 0.0, 1.0))
		f["rule"] = UiTokens.ZONE_RULE * UiMotion.ease_in_curve(clampf((tt - 0.2) / 1.4, 0.0, 1.0))
		f["veil"] = UiMotion.ease_in_curve(clampf(tt / 0.6, 0.0, 1.0))
	else:
		var k := clampf((tt - until) / out_f, 0.0, 1.0)
		var o := 1.0 - UiMotion.ease_out_curve(k)
		f["title_a"] = o
		f["em"] = lerpf(UiTokens.ZONE_TITLE_EM, 0.46, k)
		f["eyebrow_a"] = 1.0 - UiMotion.ease_out_curve(clampf(k * 1.6, 0.0, 1.0))
		f["facts_a"] = 1.0 - UiMotion.ease_out_curve(clampf(k * 1.4, 0.0, 1.0))
		f["rule"] = UiTokens.ZONE_RULE * o
		f["veil"] = o
	return f


func _draw() -> void:
	if t < 0.0 or info.is_empty():
		return
	var f := frame(t)
	var cx := size.x * 0.5
	var full := is_full()
	var y := TOP
	# eyebrow
	if full and float(f["eyebrow_a"]) > 0.001:
		var eb := "zona descubierta" if bool(info.get("first_visit", false)) else "de vuelta en"
		var w := UiStyle.text_width(&"zone_eyebrow", eb)
		UiStyle.draw_text(self, &"zone_eyebrow", Vector2(cx - w * 0.5 + UiTokens.tracking(UiTokens.ZONE_EYEBROW_SIZE, UiTokens.ZONE_EYEBROW_EM) * 0.5, y + 12.0), eb, Color(0, 0, 0, 0), HORIZONTAL_ALIGNMENT_LEFT, -1.0, float(f["eyebrow_a"]))
	y += 16.0 + 20.0 if full else 0.0
	# title (tracking animated; shrinks if it would not fit)
	var title := str(info.get("name", "")).to_upper()
	var size_px := UiTokens.ZONE_TITLE_SIZE
	var em := float(f["em"])
	var max_w := size.x - UiTokens.SAFE_X * 2.0
	_title_font.spacing_glyph = UiTokens.tracking(size_px, em)
	var tw := _title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x - float(_title_font.spacing_glyph)
	while tw > max_w and _title_font.spacing_glyph > 4:
		_title_font.spacing_glyph -= 4
		tw = _title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x - float(_title_font.spacing_glyph)
	var ta := float(f["title_a"])
	if ta > 0.001:
		var base := Vector2(cx - tw * 0.5, y + size_px * 0.80)
		# cold glow + drop shadow (CSS: 0 2px 6px rgba(0,0,0,.45), 0 0 34px rgba(150,200,240,.22))
		for layer: Array in [[20, Color(0.59, 0.78, 0.94, 0.05)], [10, Color(0.59, 0.78, 0.94, 0.06)], [6, Color(0, 0, 0, 0.10)], [3, Color(0, 0, 0, 0.16)]]:
			draw_string_outline(_title_font, base + Vector2(0, 2), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, int(layer[0]), Color(layer[1], (layer[1] as Color).a * ta))
		draw_string(_title_font, base, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(TITLE_COLOR, ta))
	y += float(size_px) + 26.0
	if not full:
		return
	# one hairline
	var rw := float(f["rule"])
	if rw > 1.0:
		Whisper.hair(self, Vector2(cx - rw * 0.5, y), Vector2(cx + rw * 0.5, y), UiTokens.HAIR, 0, 1.0)
	y += 18.0
	# facts: "a · b · c" with ink-30 separators and 12 px margins
	var fa := float(f["facts_a"])
	if fa <= 0.001:
		return
	var facts: Array = info.get("facts", [])
	var sep := "·"
	var sep_w := UiStyle.text_width(&"zone_facts", sep) + 24.0
	var total := 0.0
	for i in facts.size():
		total += UiStyle.text_width(&"zone_facts", str(facts[i]))
		if i < facts.size() - 1:
			total += sep_w
	var x := cx - total * 0.5
	var by := y + 16.0
	for i in facts.size():
		var s := str(facts[i])
		UiStyle.draw_text(self, &"zone_facts", Vector2(x, by), s, Color(0, 0, 0, 0), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fa)
		x += UiStyle.text_width(&"zone_facts", s)
		if i < facts.size() - 1:
			UiStyle.draw_text(self, &"zone_facts", Vector2(x + 12.0, by), sep, UiTokens.INK_30, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fa)
			x += sep_w
