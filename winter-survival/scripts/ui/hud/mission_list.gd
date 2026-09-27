class_name MissionList
extends Control
## Missions on demand (docs/research/10_hud_ux.md §V.4.8, mockup v2_f): while Info is held (Tab / D‑pad ↑), a
## light overlay — a side veil (74 % → 0 at 58 % of the width), not a panel — with the groups "misiones",
## "encargos" and "en la radio" (small caps + hairline). The tracked mission carries the amber diamond and
## "seguida"; its done step (✓, struck), the current one with its count and its targets with distances, the hint,
## and the next step dimmed. Other missions take one line with their count / distance / countdown. Footer with
## the input glyphs of the current device.

const EL := &"info.missions"
const X := 32.0
const TOP := 98.0
const W := 640.0

var vis: HudVisibility
var mlog: MissionLog
var _veil: Scrim
var _rows: Array = []   # [[kind, data…]] built on show / change
var _dirty: bool = true
var _acc: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil = Scrim.new()
	_veil.name = "Veil"
	_veil.linear = true
	_veil.show_behind_parent = true
	add_child(_veil)
	Events.mission_state.connect(func(_m: Array) -> void: _dirty = true)


func setup(v: HudVisibility, l: MissionLog) -> void:
	vis = v
	mlog = l
	vis.register(EL, self, UiTokens.T_INFO, true, &"")


func _process(delta: float) -> void:
	if not visible:
		return
	_acc += delta
	if _acc > 0.5 or delta == 0.0:   # distances change as the player walks
		_acc = 0.0
		_dirty = true
	# the veil covers the whole screen width (the root), starting at the screen's left edge
	var root_w := get_parent_area_size().x if get_parent() is Control else size.x
	_veil.position = Vector2(-position.x - 64.0, -position.y - 64.0)
	_veil.size = Vector2(maxf(root_w, 1280.0) + 64.0, size.y + position.y + 200.0)
	if _dirty:
		_dirty = false
		queue_redraw()


func _player_pos() -> Vector3:
	var p := GameFlow.local_player() as Node3D
	return p.global_position if p != null else Vector3.ZERO


func _dist_text(step: Dictionary) -> String:
	if mlog == null:
		return ""
	var t := mlog.targets_of(step, _player_pos(), 1)
	if t.is_empty():
		return ""
	var pp := _player_pos()
	var d := Vector2((t[0]["pos"] as Vector3).x - pp.x, (t[0]["pos"] as Vector3).z - pp.z).length()
	return UiTokens.distance(d)


func _draw() -> void:
	if mlog == null:
		return
	var y := TOP
	var right := X + W
	var tracked := mlog.tracked()
	var groups_drawn := 0
	for g: Array in Missions.GROUPS:
		var kind: String = g[0]
		var list: Array = []
		for m: Dictionary in mlog.missions:
			if str(m.get("kind", "")) == kind and not Missions.is_done(m):
				list.append(m)
		if list.is_empty():
			continue
		if groups_drawn > 0:
			y += 30.0
		groups_drawn += 1
		# header: small caps + hairline (+ day and time on the first group)
		var head := str(g[1])
		UiStyle.draw_text(self, &"smallcaps", Vector2(X, y + 12.0), head, UiTokens.INK_70)
		var hw := UiStyle.text_width(&"smallcaps", head)
		var rtext := ""
		if groups_drawn == 1:
			rtext = "día %d · %s" % [WorldState.day_now(), UiTokens.clock(WorldState.hour_now())]
		var rw := UiStyle.text_width(&"smallcaps", rtext) if rtext != "" else 0.0
		Whisper.hair(self, Vector2(X + hw + 12.0, y + 7.0), Vector2(right - rw - (16.0 if rtext != "" else 0.0), y + 7.0), UiTokens.HAIR, 1)
		if rtext != "":
			UiStyle.draw_text(self, &"smallcaps", Vector2(right - rw, y + 12.0), rtext, UiTokens.INK_50)
		y += 26.0
		for m: Dictionary in list:
			var is_tracked := str(m.get("id")) == str(tracked.get("id", ""))
			if is_tracked:
				y = _draw_tracked(m, y, right)
			else:
				y = _draw_other(m, y, right)
	if groups_drawn == 0:
		UiStyle.draw_text(self, &"smallcaps", Vector2(X, y + 12.0), "misiones", UiTokens.INK_70)
		Whisper.hair(self, Vector2(X + UiStyle.text_width(&"smallcaps", "misiones") + 12.0, y + 7.0), Vector2(right, y + 7.0), UiTokens.HAIR, 1)
		UiStyle.draw_text(self, &"list_step", Vector2(X + 36.0, y + 52.0), "Sin misiones activas", UiTokens.INK_50)
		y += 60.0
	# the footer follows the list (the vitals and the thermal breakdown own the bottom-left corner)
	_draw_footer(minf(y + 64.0, size.y - 300.0))


func _draw_tracked(m: Dictionary, y: float, right: float) -> float:
	y += 14.0
	Whisper.diamond(self, Vector2(X + 7.0, y + 18.0), UiTokens.DIAMOND, UiTokens.ACCENT, true)
	UiStyle.draw_text(self, &"list_mission", Vector2(X + 36.0, y + 26.0), str(m.get("title", "")), UiTokens.INK_RGB)
	var st := "seguida"
	UiStyle.draw_text(self, &"smallcaps", Vector2(right - UiStyle.text_width(&"smallcaps", st), y + 24.0), st, UiTokens.INK_70)
	y += 36.0
	var steps: Array = m.get("steps", [])
	var cur := Missions.current_index(m)
	# the last done step (struck), the current one with targets and hint, the next one dimmed
	if cur > 0 and cur - 1 < steps.size():
		var d: Dictionary = steps[cur - 1]
		y += 10.0
		Whisper.draw_icon(self, "check", Vector2(X + 43.0, y + 12.0), 16.0, UiTokens.INK_50)
		var t := str(d.get("title", ""))
		UiStyle.draw_text(self, &"list_step", Vector2(X + 72.0, y + 19.0), t, UiTokens.INK_50)
		var tw := UiStyle.text_width(&"list_step", t)
		draw_line(Vector2(X + 72.0, y + 12.0), Vector2(X + 72.0 + tw, y + 12.0), Color(UiTokens.INK_RGB, 0.35), 1.0)
		y += 26.0
	if cur < steps.size():
		var s: Dictionary = steps[cur]
		y += 10.0
		Whisper.diamond(self, Vector2(X + 43.0, y + 12.0), 9.0, UiTokens.ACCENT, false)
		UiStyle.draw_text(self, &"list_step", Vector2(X + 72.0, y + 19.0), str(s.get("title", "")), UiTokens.INK_RGB)
		var pt := Missions.progress_text(s)
		if pt != "":
			UiStyle.draw_text(self, &"list_step", Vector2(right - UiStyle.text_width(&"list_step", pt), y + 19.0), pt, UiTokens.ACCENT)
		y += 26.0
		# targets with distances (nearest first)
		var pp := _player_pos()
		for t: Dictionary in mlog.targets_of(s, pp, 3):
			var d := Vector2((t["pos"] as Vector3).x - pp.x, (t["pos"] as Vector3).z - pp.z).length()
			var label := str(t.get("label", ""))
			var dist := UiTokens.distance(d)
			UiStyle.draw_text(self, &"list_detail", Vector2(X + 108.0, y + 18.0), label, UiTokens.INK)
			UiStyle.draw_text(self, &"list_detail", Vector2(right - UiStyle.text_width(&"list_detail", dist), y + 18.0), dist, UiTokens.INK)
			y += 24.0
		var hint := str(s.get("hint", ""))
		if hint != "":
			y += 6.0
			UiStyle.draw_text(self, &"list_detail", Vector2(X + 108.0, y + 18.0), "«%s»" % hint, UiTokens.INK_70)
			y += 26.0
		if cur + 1 < steps.size():
			var n: Dictionary = steps[cur + 1]
			y += 6.0
			UiStyle.draw_text(self, &"list_detail", Vector2(X + 72.0, y + 18.0), "después: " + str(n.get("title", "")), UiTokens.INK_50)
			y += 24.0
	return y


func _draw_other(m: Dictionary, y: float, right: float) -> float:
	y += 12.0
	var kind := str(m.get("kind", ""))
	if kind == Missions.DYNAMIC:
		Whisper.draw_icon(self, "radio", Vector2(X + 7.0, y + 12.0), 16.0, UiTokens.INK_70)
	else:
		Whisper.diamond(self, Vector2(X + 7.0, y + 13.0), 9.0, UiTokens.INK_70, false)
	var title := str(m.get("title", ""))
	UiStyle.draw_text(self, &"list_step", Vector2(X + 36.0, y + 20.0), title, UiTokens.INK)
	var giver := str(m.get("giver", ""))
	if giver != "":
		UiStyle.draw_text(self, &"list_step", Vector2(X + 36.0 + UiStyle.text_width(&"list_step", title), y + 20.0), " · " + giver, UiTokens.INK_50)
	var s := Missions.current_step(m)
	var parts: Array = []
	var pt := Missions.progress_text(s)
	if pt != "":
		parts.append(pt)
	var exp_at := float(m.get("expires_at", -1.0))
	if exp_at > 0.0 and WorldState.instance != null:
		parts.push_front("quedan " + UiTokens.countdown(exp_at - Time.get_ticks_msec() / 1000.0))
	var dist := _dist_text(s)
	if dist != "":
		parts.append(dist)
	var rt := " · ".join(parts)
	if rt != "":
		UiStyle.draw_text(self, &"list_detail", Vector2(right - UiStyle.text_width(&"list_detail", rt), y + 19.0), rt, UiTokens.INK_70)
	return y + 26.0


func _draw_footer(fy: float) -> void:
	var x := X
	var pad := HudInput.gamepad
	if mlog != null and mlog.active_count() > 1:
		x += Whisper.glyph(self, Vector2(x + 13.0, fy), "Y" if pad else "R", pad) + 10.0
		UiStyle.draw_text(self, &"list_detail", Vector2(x, fy + 6.0), "seguir otra", UiTokens.INK_70)
		x += UiStyle.text_width(&"list_detail", "seguir otra") + 26.0
	var close := ("suelta %s para cerrar" if not bool(UiSettings.get_value("info_toggle")) else "mantén %s para cerrar") % ("↑" if pad else "Tab")
	if pad:
		close = "suelta la cruceta para cerrar" if not bool(UiSettings.get_value("info_toggle")) else "mantén la cruceta para cerrar"
	UiStyle.draw_text(self, &"list_detail", Vector2(x, fy + 6.0), close, UiTokens.INK_50)
