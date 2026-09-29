class_name HazardLine
extends Control
## Weather / environment hazards as ONE short line, top right (docs/research/10_hud_ux.md §V.4.6, appendix §6.7,
## mockup v2_d): "❄ VENTISCA · visibilidad 6 m · 2:40" with a 260 px hairline; after 5 s it shrinks to the icon
## and the time ("❄ 2:40") until it ends. H3: the line is the view of a `HazardStack` (forecast → soon → active →
## end for blizzard and Gran Ventisca; the E1 / E2 kinds through the same API): the top entry in full, a second one
## compact under it ("máximo 2 visibles"), the rest of the forecasts as "+1 previsto". The last 15 s of a countdown
## pulse. Transitions: imminent → `ui_warn` (P1, once), active → `ui_hazard` (P1), a P0 kind (thin ice underfoot, an
## avalanche) → a P0 of the NotifyRouter in the world with its sound caption; end → "la ventisca amaina" for 3 s.
## Fed by `Events.hazard_changed(kind, state, data)`; adapters: `blizzard_warning` (server / offline),
## `weather_changed` and the "Se acerca una ventisca…" / "La ventisca amaina" notices (NotifyRouter). Remote clients
## get the countdown from the server through HudNet (`source = server`).

const EL := &"hazard"
## Kept for callers of H1 (names / icons now live in HazardStack.SPECS).
const NAMES := {&"blizzard": "ventisca", &"great_blizzard": "gran ventisca", &"ice_storm": "tormenta de hielo",
	&"blackout": "sin electricidad", &"thin_ice": "hielo fino", &"extreme_cold": "frío extremo", &"cold_wave": "ola de frío",
	&"avalanche": "alud", &"fire": "incendio"}
const BLIZZARD_VISIBILITY := 6
const LINE_Y := 18.0
const ROW_H := 30.0

var vis: HudVisibility
## Set by the HUD: P0 hazards go through it (world indicator + caption).
var router: Node
var stack := HazardStack.new()
## The top entry (H1 names, read by tests): kind / state of what the full line shows.
var kind: StringName = &""
var state: StringName = &""
var detail: String = ""
var ends_at: float = -1.0
var changes: int = 0
## Sounds / notices raised (tests): [kind, state, what]
var raised: Array = []
var _clock: float = 0.0
var _scrim: Scrim
var _drawn_key: String = ""
## Effective alpha of the line (the info block moves under it).
var shown_alpha: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = Scrim.new()
	_scrim.name = "Scrim"
	_scrim.show_behind_parent = true
	add_child(_scrim)
	visible = false
	stack.changed.connect(_on_changed)
	Events.hazard_changed.connect(set_hazard)
	Events.blizzard_warning.connect(func(s: float) -> void: set_hazard(&"blizzard", &"soon", {"seconds": s}))
	Events.weather_changed.connect(_on_weather)


func setup(v: HudVisibility) -> void:
	vis = v
	vis.register(EL, null, UiTokens.T_HAZARD, true, &"")
	if WorldState.weather_now() == &"blizzard":
		_on_weather(&"blizzard")


func _on_weather(w: StringName) -> void:
	if w == &"blizzard":
		set_hazard(&"blizzard", &"active", {"seconds": _blizzard_left()})
	elif stack.state_of(&"blizzard") == &"active" or stack.state_of(&"blizzard") == &"soon":
		set_hazard(&"blizzard", &"end", {})


## Seconds of blizzard left when this process runs the server (offline / host); -1 when unknown (remote client:
## HudNet sends it).
func _blizzard_left() -> float:
	if not Net.is_server or get_tree() == null or get_tree().current_scene == null:
		return -1.0
	var w := get_tree().current_scene.get_node_or_null("World/Weather")
	if w == null:
		return -1.0
	var left: Variant = w.get("_time_left")
	return float(left) if left != null and float(left) > 0.0 else -1.0


## API (H1 signature): forecast | soon (imminent) | active | end, data {seconds, detail, pos, source}.
func set_hazard(k: StringName, s: StringName, data: Dictionary = {}) -> void:
	if stack.set_hazard(k, s, data):
		_sync_top()
		if vis != null and HazardStack.norm_state(s) != &"end":
			vis.poke(EL)
		visible = true
		queue_redraw()


func _on_changed(k: StringName, s: StringName, _old: StringName) -> void:
	changes += 1
	if vis != null:
		vis.poke(EL, HazardStack.END_HOLD if s == &"end" else -1.0)
	var lvl := HazardStack.level_of(k, s)
	match s:
		&"soon":
			if lvl <= 1:
				AudioManager.play(&"ui_warn")
				raised.append([k, s, &"ui_warn"])
		&"active":
			if lvl <= 1:
				AudioManager.play(&"ui_hazard")
				raised.append([k, s, &"ui_hazard"])
		&"end":
			_end_p0(k)
	if lvl == 0 and (s == &"active" or s == &"soon"):
		_raise_p0(k)
	elif s != &"end" and lvl > 0:
		_end_p0(k)
	_sync_top()


## A P0 hazard (thin ice underfoot, an avalanche): in the world at its point (or the player's feet), with a caption.
func _raise_p0(k: StringName) -> void:
	if router == null:
		return
	var e: Dictionary = stack.entries.get(k, {})
	var parts := stack.parts_of(e)
	var body := " · ".join(parts.slice(0, 2)) if parts.size() >= 2 else HazardStack.name_of(k)
	var pos: Variant = e.get("pos", null)
	var n := {"priority": 0, "key": "hazard:" + String(k), "title": HazardStack.name_of(k), "body": body,
		"target": &"world", "icon": HazardStack.icon_of(k), "seconds": 0.0, "tone": &"warn",
		"sound": &"ice_crack" if k == &"thin_ice" else &"ui_hazard"}
	if pos is Vector3 and (pos as Vector3) != Vector3.INF:
		n["pos"] = pos
	router.call("push", n)
	raised.append([k, &"active", &"p0"])


func _end_p0(k: StringName) -> void:
	if router != null:
		router.call("end_p0", "hazard:" + String(k))


func _sync_top() -> void:
	var t := stack.top()
	kind = t.get("kind", &"")
	state = t.get("state", &"")
	detail = str(t.get("detail", ""))
	var l := stack.left(kind) if kind != &"" else -1.0
	ends_at = _clock + l if l >= 0.0 else -1.0


func _process(delta: float) -> void:
	_clock += delta
	stack.tick(delta)
	# the offline / host blizzard: learn its duration once the Weather has it
	if stack.state_of(&"blizzard") == &"active" and stack.left(&"blizzard") < 0.0 and _clock - float(int(_clock)) < delta:
		var left := _blizzard_left()
		if left > 0.0:
			stack.set_hazard(&"blizzard", &"active", {"seconds": left})
	_sync_top()
	var full := vis.alpha_of(EL) if vis != null else 1.0
	var compact := 1.0 if state == &"soon" or state == &"active" else 0.0
	var a := maxf(full, compact)
	visible = a > 0.002 and state != &""
	shown_alpha = a
	_scrim.modulate.a = a
	var rows := mini(stack.entries.size(), UiTokens.HAZARD_VISIBLE)
	_scrim.position = Vector2(size.x - 470.0, -60.0)
	_scrim.size = Vector2(600.0, 150.0 + ROW_H * float(maxi(rows - 1, 0)))
	_scrim.strength = 1.2
	var key := "%s|%s|%d|%.2f|%d|%d" % [kind, state, int(_left()), full, stack.entries.size(), int(_clock * 2.0) if _ending() else 0]
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


func _left() -> float:
	return ends_at - _clock if ends_at > 0.0 else -1.0


func _ending() -> bool:
	var l := _left()
	return state == &"active" and l >= 0.0 and l <= UiTokens.HAZARD_ENDING


## Full line text parts of the top entry (for tests): [name, detail, time].
func line_parts() -> Array:
	return stack.parts_of(stack.top())


func _draw() -> void:
	if state == &"":
		return
	var full := vis.alpha_of(EL) if vis != null else 1.0
	var right := size.x
	var y := LINE_Y
	var list := stack.ordered()
	if list.is_empty():
		return
	var top: Dictionary = list[0]
	var icon := HazardStack.icon_of(kind)
	var col_name := UiTokens.COLD if HazardStack.level_of(kind, state) > 0 else UiTokens.WARN
	var pulse := 0.55 + 0.45 * UiMotion.pulse(_clock, 1.0) if _ending() else 1.0
	# compact form (icon + time) under the full line's fade
	var ca := (1.0 - full) if state == &"soon" or state == &"active" else 0.0
	if ca > 0.002:
		_draw_compact(top, right, y, ca, pulse)
	if full > 0.002:
		var parts := line_parts()
		var more := stack.forecasts_beyond(UiTokens.HAZARD_VISIBLE)
		if more > 0:
			parts.append("+%d %s" % [more, "previsto" if more == 1 else "previstos"])
		_draw_full(parts, icon, col_name, right, y, full, pulse)
	# the second entry, compact, under it (2 visible at most)
	if list.size() >= 2:
		var second: Dictionary = list[1]
		var sa := maxf(full, 1.0 if second["state"] == &"soon" or second["state"] == &"active" else 0.0)
		if sa > 0.002:
			_draw_compact(second, right, y + ROW_H, sa, 1.0)


func _draw_compact(e: Dictionary, right: float, y: float, a: float, pulse: float) -> void:
	var k: StringName = e["kind"]
	var l := stack.left(k)
	var t := UiTokens.countdown(l) if l >= 0.0 else ""
	if t == "" and e["state"] != &"end":
		t = HazardStack.name_of(k)
	var style := &"text_num" if l >= 0.0 else &"smallcaps"
	var tw := UiStyle.text_width(style, t)
	if t != "":
		UiStyle.draw_text(self, style, Vector2(right - tw, y), t, UiTokens.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, a * pulse)
	var col := UiTokens.COLD if HazardStack.level_of(k, e["state"]) > 0 else UiTokens.WARN
	Whisper.draw_icon(self, HazardStack.icon_of(k), Vector2(right - tw - (14.0 if t != "" else 8.0), y - 6.0), 16.0, col, a)


func _draw_full(parts: Array, icon: String, col_name: Color, right: float, y: float, full: float, pulse: float) -> void:
	# icon, NAME in cold small caps, the rest in ink with ink-70 separators
	var sep_w := UiStyle.text_width(&"whisper", " · ")
	var widths: Array = []
	var total := 0.0
	for i in parts.size():
		var w := UiStyle.text_width(&"smallcaps_wide" if i == 0 else &"whisper", str(parts[i]))
		widths.append(w)
		total += w + (sep_w if i > 0 else 0.0)
	var x := right - total
	Whisper.draw_icon(self, icon, Vector2(x - 18.0, y - 6.0), 16.0, col_name, full)
	for i in parts.size():
		if i > 0:
			UiStyle.draw_text(self, &"whisper", Vector2(x, y), " · ", UiTokens.INK_70, HORIZONTAL_ALIGNMENT_LEFT, -1.0, full)
			x += sep_w
		var style := &"smallcaps_wide" if i == 0 else &"whisper"
		var col := col_name if i == 0 else UiTokens.INK
		var a := full * (pulse if i == parts.size() - 1 else 1.0)
		UiStyle.draw_text(self, style, Vector2(x, y), str(parts[i]), col, HORIZONTAL_ALIGNMENT_LEFT, -1.0, a)
		x += float(widths[i])
	Whisper.hair(self, Vector2(right - UiTokens.HAZARD_RULE, y + 11.0), Vector2(right, y + 11.0), UiTokens.HAIR, 2, full)
