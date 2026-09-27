class_name MapScreen
extends Control
## The paper map and the journal (docs/research/10_hud_ux.md §V.4.10, appendix §6.11–6.12): a full screen on
## demand (M / Back), NOT part of the HUD — the world keeps running behind a dark veil. Tabs "mapa · diario" in
## small caps with an amber underline (v2 tab bar, no box); Q / E or LB / RB switch tab, the wheel or D‑pad ↑/↓
## zooms (3 km, 1 km, 400 m around you), M / Esc / B closes.
## - MAPA: a paper sheet (assets/ui/paper_map.gdshader) inked from the macro map (height contours, forest, water,
##   villages) only where you have been (MapFog, 8 m cells, charcoal edge); roads, the names of the places you
##   know, the cabin, your amber arrow, teammates, the tracked objective, a 500 m grid with letters and numbers,
##   the scale and the north.
## - DIARIO: notebook paper with ruled lines and a red margin: the missions (done ✓, current with its count and
##   hint, the rest), and the places discovered.

const ZOOMS := [1.0, 1.0 / 3.0, 400.0 / 3072.0]
const PAPER := Color("#E9E1CD")
const INK := Color(0.20, 0.18, 0.16)
const INK_SOFT := Color(0.20, 0.18, 0.16, 0.62)
const RULE := Color(0.45, 0.60, 0.78, 0.35)
const MARGIN := Color(0.78, 0.30, 0.30, 0.55)

## True while a map screen is open (HudInput leaves Tab / D-pad to it).
static var any_open: bool = false

var hud: Node
var fog: MapFog
var is_open: bool = false
var tab: StringName = &"map"
var zoom: int = 0
var opened_count: int = 0
var _sheet: ColorRect
var _overlay: Control
var _veil: ColorRect
var _land: ImageTexture
var _land_range: float = 160.0
var _acc: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_veil = ColorRect.new()
	_veil.color = Color(0.02, 0.04, 0.07, 0.72)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	_sheet = ColorRect.new()
	_sheet.name = "Sheet"
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/ui/paper_map.gdshader")
	_sheet.material = m
	add_child(_sheet)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	fog = MapFog.new()   # keeps revealing while the map is closed (hidden Controls still process)
	fog.name = "Fog"
	add_child(fog)


func open_map(which: StringName = &"map") -> void:
	tab = which
	is_open = true
	any_open = true
	visible = true
	opened_count += 1
	_ensure_land()
	_layout()
	AudioManager.play(&"ui_map_open")
	_overlay.queue_redraw()


func close_map() -> void:
	is_open = false
	any_open = false
	visible = false
	AudioManager.play(&"ui_map_close")


func _unhandled_input(event: InputEvent) -> void:
	if is_open or event.is_echo():
		return
	if event.is_action_pressed("map") and GameFlow.in_game and not GameFlow.is_paused:
		open_map()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not is_open or event.is_echo():
		return
	var handled := true
	if event.is_action_pressed("map") or event.is_action_pressed("cancel") or event.is_action_pressed("pause"):
		close_map()
	elif event.is_action_pressed("zoom_in"):   # wheel / D-pad ↑ (D-pad ↑ is also hud_info: zoom wins here)
		zoom = mini(zoom + 1, ZOOMS.size() - 1)
	elif event.is_action_pressed("zoom_out"):
		zoom = maxi(zoom - 1, 0)
	elif event.is_action_pressed("rotate_cam_left") or event.is_action_pressed("rotate_cam_right") \
			or (event.is_action_pressed("hud_info") and event is InputEventKey):
		tab = &"journal" if tab == &"map" else &"map"
		_layout()
	elif event.is_action("zoom_in") or event.is_action("zoom_out") or event.is_action("rotate_cam_left") or event.is_action("rotate_cam_right") or event.is_action("hud_info"):
		pass
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()
		_overlay.queue_redraw()


func _process(delta: float) -> void:
	if not is_open:
		return
	_acc += delta
	if _acc >= 0.25:
		_acc = 0.0
		_update_view()
		_overlay.queue_redraw()


func _layout() -> void:
	_veil.position = Vector2.ZERO
	_veil.size = size
	var side := minf(size.y - 200.0, size.x - 480.0)
	_sheet.size = Vector2(side, side)
	_sheet.position = Vector2((size.x - side) * 0.5, 110.0)
	_sheet.visible = tab == &"map"
	_overlay.position = Vector2.ZERO
	_overlay.size = size
	_update_view()


# ------------------------------------------------------------------ land texture from the macro map
func _ensure_land() -> void:
	if _land != null:
		return
	var mm: MacroMap = World.instance.hf.macro if World.instance != null and World.instance.hf != null else null
	var n := MacroMap.SIZE
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	if mm != null and mm.ok:
		var lo := INF
		var hi := -INF
		for v in mm.rel:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		_land_range = maxf(hi - lo, 1.0)
		var data := PackedByteArray()
		data.resize(n * n * 4)
		for k in n * n:
			var b := int(mm.biome[k])
			var dens := float(mm.density[k]) / 255.0
			var forest := dens if b == MacroMap.Biome.DENSE_FOREST else (dens * 0.7 if b == MacroMap.Biome.FOREST else 0.0)
			var i := k % n
			var j := k / n
			var wx := -MapFog.HALF + (float(i) + 0.5) * MacroMap.PX
			var wz := -MapFog.HALF + (float(j) + 0.5) * MacroMap.PX
			var water := 1.0 if b == MacroMap.Biome.LAKE or PoiRegistry.lake_sdf(wx, wz) < 0.0 else 0.0
			data[k * 4] = clampi(int((mm.rel[k] - lo) / _land_range * 255.0), 0, 255)
			data[k * 4 + 1] = int(forest * 255.0)
			data[k * 4 + 2] = int(water * 255.0)
			data[k * 4 + 3] = 255 if b == MacroMap.Biome.SETTLEMENT else 0
		img.set_data(n, n, false, Image.FORMAT_RGBA8, data)
	_land = ImageTexture.create_from_image(img)
	var m := _sheet.material as ShaderMaterial
	m.set_shader_parameter("land", _land)
	m.set_shader_parameter("fog", fog.texture)
	m.set_shader_parameter("height_range", _land_range)


## The part of the map shown (uv offset + size): the whole world, or centred on the player.
func view_rect() -> Rect2:
	var s := float(ZOOMS[zoom])
	if s >= 0.999:
		return Rect2(0, 0, 1, 1)
	var p := GameFlow.local_player() as Node3D
	var c := world_to_uv(p.global_position) if p != null else Vector2(0.5, 0.5)
	var o := (c - Vector2(s, s) * 0.5).clamp(Vector2.ZERO, Vector2(1.0 - s, 1.0 - s))
	return Rect2(o, Vector2(s, s))


func _update_view() -> void:
	var v := view_rect()
	(_sheet.material as ShaderMaterial).set_shader_parameter("view", Vector4(v.position.x, v.position.y, v.size.x, v.size.y))


static func world_to_uv(p: Vector3) -> Vector2:
	return Vector2((p.x + MapFog.HALF) / (MapFog.HALF * 2.0), (p.z + MapFog.HALF) / (MapFog.HALF * 2.0))


func uv_to_screen(uv: Vector2) -> Vector2:
	var v := view_rect()
	return _sheet.position + (uv - v.position) / v.size * _sheet.size


func world_to_screen(p: Vector3) -> Vector2:
	return uv_to_screen(world_to_uv(p))


# ------------------------------------------------------------------ drawing
func _ink_text(ci: CanvasItem, font: Font, pos: Vector2, text: String, size_px: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	ci.draw_string(font, pos, text, align, width, size_px, color)


func _draw_overlay() -> void:
	var ci := _overlay
	# tab bar (v2: small caps, amber underline, no box) + status on the right
	var x := _sheet.position.x
	var y := 70.0
	for t: Array in [[&"map", "mapa"], [&"journal", "diario"]]:
		var active: bool = tab == t[0]
		var label := str(t[1])
		UiStyle.draw_text(ci, &"smallcaps_wide", Vector2(x, y), label, UiTokens.INK if active else UiTokens.INK_50)
		var w := UiStyle.text_width(&"smallcaps_wide", label)
		if active:
			ci.draw_rect(Rect2(x, y + 10.0, w, 2.0), UiTokens.ACCENT)
		x += w + 36.0
	var right := _sheet.position.x + _sheet.size.x
	var status := "explorado %d %% · Día %d · %s · %s" % [int(round(fog.explored_fraction() * 100.0)), WorldState.day_now(),
		UiTokens.clock(WorldState.hour_now()), UiTokens.temperature(UiClimate.air_now())]
	UiStyle.draw_text(ci, &"text_num", Vector2(right - UiStyle.text_width(&"text_num", status), y), status, UiTokens.INK_70)
	if tab == &"map":
		_draw_map(ci)
	else:
		_draw_journal(ci)
	# footer with the device glyphs
	var pad := HudInput.gamepad
	var fy := _sheet.position.y + _sheet.size.y + 44.0
	var fx := _sheet.position.x
	for g: Array in [["B" if pad else "M", "cerrar"], ["LB RB" if pad else "Q E", "pestaña"], ["↑↓" if pad else "rueda", "zoom"]]:
		var gw := Whisper.glyph(ci, Vector2(fx + 18.0, fy - 6.0), str(g[0]), pad and str(g[0]).length() == 1)
		fx += gw + 12.0
		UiStyle.draw_text(ci, &"list_detail", Vector2(fx, fy), str(g[1]), UiTokens.INK_70)
		fx += UiStyle.text_width(&"list_detail", str(g[1])) + 28.0


func _draw_map(ci: CanvasItem) -> void:
	var r := Rect2(_sheet.position, _sheet.size)
	var v := view_rect()
	var cond := UiStyle.font_file(&"cond_semibold")
	var body := UiStyle.font(&"regular")
	# frame + 500 m grid with letters / numbers
	ci.draw_rect(r, Color(INK, 0.8), false, 2.0)
	var step := 500.0 / (MapFog.HALF * 2.0)
	var g0 := int(floor(v.position.x / step))
	var g1 := int(ceil(v.end.x / step))
	for i in range(g0, g1 + 1):
		var u := float(i) * step
		var sx := uv_to_screen(Vector2(u, 0)).x
		if sx > r.position.x + 1.0 and sx < r.end.x - 1.0:
			ci.draw_line(Vector2(sx, r.position.y), Vector2(sx, r.end.y), Color(INK, 0.12), 1.0)
		if i < g1:
			var cx := uv_to_screen(Vector2(u + step * 0.5, 0)).x
			if cx > r.position.x and cx < r.end.x:
				_ink_text(ci, body, Vector2(cx - 5.0, r.position.y - 8.0), char(65 + posmod(i, 26)), 14, UiTokens.INK_70)
	var h0 := int(floor(v.position.y / step))
	var h1 := int(ceil(v.end.y / step))
	for j in range(h0, h1 + 1):
		var vv := float(j) * step
		var sy := uv_to_screen(Vector2(0, vv)).y
		if sy > r.position.y + 1.0 and sy < r.end.y - 1.0:
			ci.draw_line(Vector2(r.position.x, sy), Vector2(r.end.x, sy), Color(INK, 0.12), 1.0)
		if j < h1:
			var cy := uv_to_screen(Vector2(0, vv + step * 0.5)).y
			if cy > r.position.y and cy < r.end.y:
				_ink_text(ci, body, Vector2(r.position.x - 22.0, cy + 5.0), str(j + 1), 14, UiTokens.INK_70)
	# roads (known stretches only)
	var mm: MacroMap = World.instance.hf.macro if World.instance != null and World.instance.hf != null else null
	if mm != null:
		for road: Dictionary in mm.roads:
			var pts: PackedVector2Array = road["points"]
			var hw := 3.0 if str(road["kind"]) == "highway" else 1.6
			for k in pts.size() - 1:
				var a := Vector3(pts[k].x, 0, pts[k].y)
				var b := Vector3(pts[k + 1].x, 0, pts[k + 1].y)
				if not (fog.is_revealed(a.x, a.z) or fog.is_revealed(b.x, b.z) or fog.is_revealed((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)):
					continue
				var sa := world_to_screen(a)
				var sb := world_to_screen(b)
				if not r.grow(20.0).has_point(sa) and not r.grow(20.0).has_point(sb):
					continue
				sa = sa.clamp(r.position, r.end)
				sb = sb.clamp(r.position, r.end)
				ci.draw_line(sa, sb, Color(0.45, 0.28, 0.18, 0.85), hw + 1.5, true)
				ci.draw_line(sa, sb, Color(PAPER, 0.9), maxf(hw - 1.0, 0.8), true)
	# places you know (discovered by the zone tracker, or ground you have seen)
	var known: Dictionary = hud.zones.discovered if hud != null else {}
	for e: Dictionary in Locations.all():
		var shape: Dictionary = e["shape"]
		var c2 := Vector2.INF
		if shape.has("circle"):
			c2 = shape["circle"][0]
		elif shape.has("rect"):
			c2 = shape["rect"][0]
		if c2 == Vector2.INF:
			continue
		if not known.has(str(e["id"])) and not fog.is_revealed(c2.x, c2.y):
			continue
		# small places only when zoomed in (they crowd the clearing otherwise)
		if shape.has("circle") and float(shape["circle"][1]) < 40.0 and zoom < 2:
			continue
		var sp := world_to_screen(Vector3(c2.x, 0, c2.y))
		if not r.has_point(sp):
			continue
		var name := str(e["name"]).to_upper()
		var fs := 15 if str(e.get("kind")) in ["town", "village", "city", "district"] else 12
		var w := cond.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_ink_text(ci, cond, sp + Vector2(-w * 0.5, -6.0), name, fs, INK)
	# the cabin (base)
	var w0 := World.instance
	if w0 != null and w0.cabin != null:
		var cp := world_to_screen(w0.cabin.global_position)
		if r.has_point(cp):
			Whisper.draw_icon(ci, "house", cp + Vector2(0, 12), 18.0, INK)
	# tracked objective
	var me := GameFlow.local_player() as Player
	if hud != null and me != null:
		var t: Dictionary = hud.mlog.tracked_target(me.global_position)
		if not t.is_empty():
			var tp := world_to_screen(t["pos"])
			if r.has_point(tp):
				Whisper.diamond(ci, tp, 12.0, UiTokens.ACCENT, true, 1.0, false)
				ci.draw_arc(tp, 9.0, 0.0, TAU, 20, Color(INK, 0.8), 1.0, true)
		# teammates
		for mt: Dictionary in hud.team.mates:
			var o := TeamTracker.player_of(mt)
			if o == null:
				continue
			var op := world_to_screen(o.global_position)
			if r.has_point(op):
				ci.draw_circle(op, 5.0, UiTokens.player_color(int(mt["color"]), bool(UiSettings.get_value("colorblind"))))
				ci.draw_arc(op, 5.0, 0.0, TAU, 16, INK, 1.0, true)
				_ink_text(ci, body, op + Vector2(8.0, 4.0), str(mt["name"]), 12, INK)
	# you: an amber arrow along your facing
	if me != null:
		var pp := world_to_screen(me.global_position)
		var f3 := me.facing()
		var d := Vector2(f3.x, f3.z).normalized()
		if d.length() < 0.5:
			d = Vector2(0, -1)
		var n := Vector2(-d.y, d.x)
		var tri := PackedVector2Array([pp + d * 11.0, pp - d * 7.0 + n * 7.0, pp - d * 3.0, pp - d * 7.0 - n * 7.0])
		ci.draw_colored_polygon(tri, UiTokens.ACCENT)
		tri.append(tri[0])
		ci.draw_polyline(tri, INK, 1.2, true)
	# scale bar + north
	var span_m := v.size.x * MapFog.HALF * 2.0
	var bar_m := 500.0 if span_m > 1500.0 else (200.0 if span_m > 600.0 else 100.0)
	var bar_px := bar_m / span_m * r.size.x
	var bp := r.end - Vector2(bar_px + 24.0, 24.0)
	ci.draw_line(bp, bp + Vector2(bar_px, 0), INK, 2.0)
	ci.draw_line(bp + Vector2(0, -5), bp + Vector2(0, 3), INK, 1.5)
	ci.draw_line(bp + Vector2(bar_px, -5), bp + Vector2(bar_px, 3), INK, 1.5)
	_ink_text(ci, body, bp + Vector2(0, -9), "%d m" % int(bar_m), 13, INK)
	var np := r.position + Vector2(r.size.x - 30.0, 44.0)
	ci.draw_colored_polygon(PackedVector2Array([np + Vector2(0, -18), np + Vector2(7, 6), np + Vector2(0, 1), np + Vector2(-7, 6)]), INK)
	_ink_text(ci, cond, np + Vector2(-5, 24), "N", 15, INK)


func _draw_journal(ci: CanvasItem) -> void:
	var side := _sheet.size.x
	var r := Rect2(Vector2((size.x - side) * 0.5, 110.0), Vector2(side, side))
	ci.draw_rect(r, PAPER)
	var ly := r.position.y + 70.0
	while ly < r.end.y - 10.0:
		ci.draw_line(Vector2(r.position.x, ly), Vector2(r.end.x, ly), RULE, 1.0)
		ly += 30.0
	ci.draw_line(Vector2(r.position.x + 70.0, r.position.y), Vector2(r.position.x + 70.0, r.end.y), MARGIN, 1.5)
	var cond := UiStyle.font_file(&"cond_semibold")
	var body := UiStyle.font(&"regular", ["tnum"])
	var x := r.position.x + 86.0
	var y := r.position.y + 58.0
	_ink_text(ci, cond, Vector2(x, y), "DIARIO", 30, INK)
	y += 42.0
	if hud == null:
		return
	var tracked: Dictionary = hud.mlog.tracked()
	for g: Array in Missions.GROUPS:
		var list: Array = []
		for m: Dictionary in hud.mlog.missions:
			if str(m.get("kind")) == str(g[0]):
				list.append(m)
		if list.is_empty():
			continue
		_ink_text(ci, cond, Vector2(x, y), str(g[1]).to_upper(), 18, INK_SOFT)
		y += 30.0
		for m: Dictionary in list:
			var mark := "◆ " if str(m.get("id")) == str(tracked.get("id", "")) else ""
			_ink_text(ci, body, Vector2(x, y), mark.replace("◆ ", "") + str(m.get("title", "")) + ("  (completada)" if Missions.is_done(m) else ""), 20, INK)
			if mark != "":
				Whisper.diamond(ci, Vector2(x - 14.0, y - 7.0), 8.0, UiTokens.ACCENT, true, 1.0, false)
			y += 30.0
			var steps: Array = m.get("steps", [])
			var cur := Missions.current_index(m)
			for i in steps.size():
				if y > r.end.y - 60.0:
					break
				var s: Dictionary = steps[i]
				var t := str(s.get("title", ""))
				var col := INK
				if i < cur:
					col = INK_SOFT
				elif i > cur:
					col = Color(INK, 0.45)
				_ink_text(ci, body, Vector2(x + 26.0, y), t, 17, col)
				var tw := body.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
				if i < cur:
					ci.draw_line(Vector2(x + 26.0, y - 6.0), Vector2(x + 26.0 + tw, y - 6.0), Color(INK, 0.5), 1.0)
					Whisper.draw_icon(ci, "check", Vector2(x + 12.0, y - 6.0), 14.0, Color(INK, 0.7))
				elif i == cur:
					Whisper.diamond(ci, Vector2(x + 12.0, y - 6.0), 8.0, UiTokens.ACCENT, false, 1.0, false)
					var pt := Missions.progress_text(s)
					if pt != "":
						_ink_text(ci, body, Vector2(r.end.x - 40.0 - body.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x, y), pt, 17, INK)
					var hint := str(s.get("hint", ""))
					if hint != "":
						y += 30.0
						_ink_text(ci, body, Vector2(x + 26.0, y), "— " + hint, 15, INK_SOFT)
				y += 30.0
			y += 8.0
	# places discovered
	var names: Array = []
	for id: String in hud.zones.discovered:
		var e := Locations.by_id(id)
		if not e.is_empty():
			names.append(str(e["name"]))
	if not names.is_empty() and y < r.end.y - 90.0:
		y += 10.0
		_ink_text(ci, cond, Vector2(x, y), "LUGARES", 18, INK_SOFT)
		y += 30.0
		_ink_text(ci, body, Vector2(x, y), " · ".join(names), 17, INK, HORIZONTAL_ALIGNMENT_LEFT, r.end.x - x - 30.0)
