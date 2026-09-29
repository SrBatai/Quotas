class_name ZoneSign
extends Control
## Highway sign (H2, PLAN C35; docs/research/10_hud_ux.md §V.4.4, appendix §6.1 and §7.1; mockup v2_c, "en
## vehículo"): shown instead of the zone title when the player moves faster than 40 km/h on a road (a vehicle, M7;
## today any fast mover) and on the first visit of a road zone. Top right for 3 s, in the style of Spanish signage —
## blue with white text on the autovía, white with black text on conventional roads and avenues, the red «N‑140»
## plate on the nacional — and one line of facts below it («A‑14 · sin electricidad · −8 °C»). The only box of the
## HUD, because it imitates a real sign (§V.1 rule 6). Content (`compose`):
##   row 1   the destination and its distance: the city / town ahead on the road (never one the player is already in)
##           when the zone is a road; else the top-level place of the zone entered («Altavega»)
##   row 2   «SALIDA n» (kilometre point of the exit on that road) + where it goes: the next junction ahead with
##           another named road («SALIDA 1 · Gran Vía →»), else that place's nearest district / POI; when the zone
##           entered is itself a district / POI, that zone («Las Torres →»)
## Listens to `Events.location_entered` with card = "sign".

const PAD := 22.0

var info: Dictionary = {}
var t: float = -1.0
var shown_count: int = 0
## Extra top offset (the hazard line above it).
var top_offset: float = 0.0
var _line: String = ""
var _sb: StyleBoxFlat
## Soft veil behind the facts line (the plate itself is opaque; the line sits on snow).
var _scrim: Scrim


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_scrim = Scrim.new()
	_scrim.name = "Scrim"
	_scrim.show_behind_parent = true
	_scrim.visible = false
	add_child(_scrim)
	Events.location_entered.connect(func(i: Dictionary) -> void:
		if str(i.get("card", "")) == "sign":
			show_sign(i))


## Starts the sign now (public: screenshots / tests; `at` = start the timeline at that second).
func show_sign(i: Dictionary, at: float = 0.0) -> void:
	info = i
	t = at
	shown_count += 1
	visible = true
	var facts: Array = (i.get("sign", {}) as Dictionary).get("facts", [])
	_line = "  ·  ".join(PackedStringArray(facts.map(func(v: Variant) -> String: return str(v))))
	_place_scrim()
	if bool(i.get("first_visit", false)) and at == 0.0:
		AudioManager.play(&"ui_zone_discover")
	queue_redraw()


func duration() -> float:
	return float(UiTokens.T_SIGN[0]) + float(UiTokens.T_SIGN[1]) + float(UiTokens.T_SIGN[2])


func is_showing() -> bool:
	return t >= 0.0 and t < duration()


func _process(delta: float) -> void:
	if t < 0.0:
		return
	t += delta
	if t >= duration():
		t = -1.0
		visible = false
		return
	_place_scrim()
	queue_redraw()


func _place_scrim() -> void:
	if _scrim == null:
		return
	var has_exit := str((info.get("sign", {}) as Dictionary).get("exit", "")) != ""
	var h := UiTokens.SIGN_H if has_exit else UiTokens.SIGN_H - 36.0
	_scrim.visible = _line != "" and t >= 0.0
	_scrim.position = Vector2(size.x - UiTokens.SIGN_W - 40.0, top_offset + h - 10.0)
	_scrim.size = Vector2(UiTokens.SIGN_W + 80.0, 76.0)
	_scrim.strength = alpha_at(maxf(t, 0.0))
	_scrim.queue_redraw()


## Alpha and slide (0..1 of the 6 px) at time `tt`.
func alpha_at(tt: float) -> float:
	var tin := UiMotion.dur(float(UiTokens.T_SIGN[0]))
	var tout := UiMotion.dur(float(UiTokens.T_SIGN[2]))
	var hold_end := float(UiTokens.T_SIGN[0]) + float(UiTokens.T_SIGN[1])
	if tt < tin:
		return UiMotion.ease_in_curve(tt / tin)
	if tt < hold_end:
		return 1.0
	return 1.0 - UiMotion.ease_out_curve((tt - hold_end) / tout)


# ------------------------------------------------------------------ content
## Sign content for a zone entered at `pos` moving along `dir` (unit, world x/z): {style, plate, road, dest, dist,
## exit, exit_no, facts}.
static func compose(e: Dictionary, pos: Vector3, dir: Vector2) -> Dictionary:
	var p := Vector2(pos.x, pos.z)
	var road := Locations.road_at(pos.x, pos.z, 16.0)
	var banner := str(road.get("name", ""))
	var is_road_zone := str(e.get("kind", "")) == "road" and int(e.get("tier", 0)) == LocationInfo.Tier.ROAD
	if banner == "" and is_road_zone:
		banner = str(e.get("banner", ""))
	var st := Locations.road_style(banner) if banner != "" else {"kind": "road", "plate": "", "style": "convencional", "display": ""}
	if banner == "" and str(road.get("kind", "")) == "highway":
		st["style"] = "autovia"
	if dir == Vector2.ZERO and road.has("dir"):
		dir = road["dir"]
	var out := {"style": str(st["style"]), "plate": str(st["plate"]), "road": str(st["display"]), "dest": "", "dist": "",
		"exit": "", "exit_no": 0, "facts": []}
	var power_of: Dictionary = e
	if is_road_zone:
		# the next city / town / village ahead on this road (not one the player is in), ≤ 8 km, within ±60°
		var best := {}
		var best_d := 8000.0
		for c: Dictionary in Locations.all():
			if not str(c["kind"]) in ["city", "town", "village"]:
				continue
			var cc := Locations.center(c)
			if cc == Vector2.INF or Locations.depth(c, pos.x, pos.z) > 0.0:
				continue
			var v := cc - p
			var d := v.length()
			if d < best_d and (dir == Vector2.ZERO or v.normalized().dot(dir) > 0.5):
				best_d = d
				best = c
		if best.is_empty():
			out["dest"] = str(e["name"])
		else:
			out["dest"] = str(best["name"])
			out["dist"] = distance_text(best_d)
			power_of = best
			# the exit: the next junction ahead with another named road («SALIDA 1 · Gran Vía»), else the district /
			# POI of that place closest to the road ahead
			var j := Locations.next_junction(banner, pos.x, pos.z, dir) if banner != "" else {}
			if not j.is_empty():
				out["exit"] = str(Locations.road_style(str(j["banner"]))["display"])
				out["exit_no"] = maxi(1, int(round(float(j["km"]))))
			else:
				var ex := {}
				var ex_score := INF
				for c: Dictionary in Locations.all():
					if not str(c["kind"]) in ["district", "poi"] or not Locations.chain_ids(c).has(str(best["id"])):
						continue
					var cc := Locations.center(c)
					if cc == Vector2.INF:
						continue
					var v := cc - p
					var along := v.dot(dir) if dir != Vector2.ZERO else v.length()
					if along < 0.0:
						continue
					var score := along + absf(v.cross(dir)) * 2.0 if dir != Vector2.ZERO else along
					if score < ex_score:
						ex_score = score
						ex = c
				if not ex.is_empty():
					out["exit"] = str(ex["name"])
					var ec := Locations.center(ex)
					out["exit_no"] = maxi(1, int(round(Locations.road_km(banner, ec.x, ec.y)))) if banner != "" else 0
	else:
		var chain := Locations.chain_ids(e)
		var top := e if chain.is_empty() else Locations.by_id(str(chain[-1]))
		if top.is_empty():
			top = e
		out["dest"] = str(top["name"])
		if str(top["id"]) != str(e["id"]):
			out["exit"] = str(e["name"])
			out["exit_no"] = maxi(1, int(round(float(road.get("km", 0.0))))) if banner != "" else 0
	var facts: Array = []
	var plate := str(st["plate"])
	if plate != "":
		facts.append(plate)
	elif str(st["display"]) != "" and str(st["display"]) != str(out["dest"]):
		facts.append(str(st["display"]))
	var power := str(power_of.get("power", ""))
	if Locations.POWER_NAMES.has(power):
		facts.append(Locations.POWER_NAMES[power])
	facts.append(UiTokens.temperature(UiClimate.air_now() + float(e.get("temp", 0.0))))
	out["facts"] = facts
	return out


## Road sign distances: whole kilometres from 1 km («4 km»), hundreds of metres below («800 m»).
static func distance_text(m: float) -> String:
	if m >= 950.0:
		return "%d km" % int(round(m / 1000.0))
	return "%d m" % (maxi(int(round(m / 100.0)), 1) * 100)


# ------------------------------------------------------------------ drawing
func _draw() -> void:
	if t < 0.0 or info.is_empty():
		return
	var s: Dictionary = info.get("sign", {})
	if s.is_empty():
		return
	var a := alpha_at(t)
	if a <= 0.002:
		return
	var slide := UiMotion.slide(UiTokens.MOVE_MAX) * (1.0 - a)
	var style := str(s.get("style", "autovia"))
	var blue := style == "autovia"
	var bg: Color = UiTokens.SIGN_BLUE if blue else UiTokens.SIGN_WHITE
	var fg: Color = Color.WHITE if blue else UiTokens.SIGN_INK
	var has_exit := str(s.get("exit", "")) != ""
	var h := UiTokens.SIGN_H if has_exit else UiTokens.SIGN_H - 36.0
	var r := Rect2(size.x - UiTokens.SIGN_W + slide, top_offset, UiTokens.SIGN_W, h)
	# soft drop shadow (three widening layers), the plate and its inner border
	for k in 3:
		var g := 1.0 + 3.0 * k
		_box(Rect2(r.position + Vector2(0.0, 3.0), r.size).grow(g), Color(0, 0, 0, 0.11 * a), 8.0 + g, 0.0, Color.TRANSPARENT)
	_box(r, Color(bg, a), 8.0, 0.0, Color.TRANSPARENT)
	_box(r.grow(-5.0), Color.TRANSPARENT, 5.0, 2.0, Color(fg, 0.92 * a))
	var f_big := UiStyle.font(&"medium", ["tnum"])
	var f_mid := UiStyle.font(&"regular", ["tnum"])
	var x0 := r.position.x + PAD
	var x1 := r.end.x - PAD
	# row 1: destination · distance
	var dest := str(s.get("dest", ""))
	var dist := str(s.get("dist", ""))
	var y1 := r.position.y + 42.0
	var fit := x1 - x0 - (f_big.get_string_size(dist, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x + 16.0 if dist != "" else 0.0)
	draw_string(f_big, Vector2(x0, y1), dest, HORIZONTAL_ALIGNMENT_LEFT, fit, 27, Color(fg, a))
	if dist != "":
		draw_string(f_big, Vector2(x1 - f_big.get_string_size(dist, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x, y1), dist, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color(fg, a))
	# row 2: exit badge · district →
	if has_exit:
		var y2 := r.position.y + 78.0
		var bx := x0
		var n := int(s.get("exit_no", 0))
		if n > 0:
			var badge := "SALIDA %d" % n
			var bw := f_mid.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14.0
			var br := Rect2(bx, y2 - 16.0, bw, 21.0)
			_box(br, Color(fg, a), 3.0, 0.0, Color.TRANSPARENT)
			draw_string(f_mid, Vector2(bx + 7.0, y2), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(bg, a))
			bx += bw + 12.0
		var aw := 22.0   # the arrow is drawn (Barlow has no U+2192)
		draw_string(f_mid, Vector2(bx, y2), str(s.get("exit", "")), HORIZONTAL_ALIGNMENT_LEFT, x1 - aw - 12.0 - bx, 20, Color(fg, a))
		var ay := y2 - 6.5
		var tip := Vector2(x1, ay)
		draw_line(Vector2(x1 - aw, ay), tip - Vector2(2.0, 0.0), Color(fg, a), 2.5, true)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-9.0, -6.5), tip + Vector2(-9.0, 6.5)]), Color(fg, a))
	# the red N plate (conventional road sign with a nacional number)
	var plate := str(s.get("plate", ""))
	if style == "nacional" and plate != "":
		var pw := f_mid.get_string_size(plate, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 16.0
		var pr := Rect2(r.end.x - pw - 12.0, r.position.y - 11.0, pw, 23.0)
		_box(pr, Color(UiTokens.SIGN_RED, a), 3.0, 1.5, Color(1, 1, 1, a))
		draw_string(f_mid, Vector2(pr.position.x + 8.0, pr.position.y + 17.0), plate, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, a))
	# the facts line under the sign (whisper style, right aligned)
	if _line == "":
		return
	var line := _line
	var w := UiStyle.text_width(&"zone_facts", line)
	UiStyle.draw_text(self, &"zone_facts", Vector2(r.end.x - w - 4.0, r.end.y + 28.0), line, UiTokens.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, a)


## One StyleBoxFlat reused for every box (StyleBoxFlat.draw emits its polygons at once; no allocation per frame).
func _box(r: Rect2, fill: Color, radius: float, border: float, border_color: Color) -> void:
	if _sb == null:
		_sb = StyleBoxFlat.new()
	var sb := _sb
	sb.bg_color = fill
	sb.draw_center = fill.a > 0.0
	sb.set_corner_radius_all(int(radius))
	sb.corner_detail = 6
	sb.anti_aliasing = true
	sb.set_border_width_all(int(round(border)))
	sb.border_color = border_color
	draw_style_box(sb, r)
