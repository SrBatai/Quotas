class_name HazardLine
extends Control
## Weather / environment hazard as ONE short line, top right (docs/research/10_hud_ux.md §V.4.6, appendix §6.7,
## mockup v2_d): "❄ VENTISCA · visibilidad 6 m · 2:40" with a 260 px hairline; after 5 s it shrinks to the icon
## and the time ("❄ 2:40") until it ends. States: forecast (prevista) → soon (se acerca, countdown) → active →
## end ("la ventisca amaina", 3 s). The red blinking "VENTISCA" label of the slice is gone: the colour is `cold`.
## Fed by `Events.hazard_changed(kind, state, data)`; adapters: `blizzard_warning` (server / offline),
## `weather_changed` and the "Se acerca una ventisca…" / "La ventisca amaina" notices (NotifyRouter).

const EL := &"hazard"
const NAMES := {&"blizzard": "ventisca", &"great_blizzard": "gran ventisca", &"ice_storm": "tormenta de hielo",
	&"blackout": "sin electricidad", &"thin_ice": "hielo fino", &"extreme_cold": "frío extremo"}
const ICONS := {&"blizzard": "snow", &"great_blizzard": "storm", &"ice_storm": "storm", &"blackout": "boltoff",
	&"thin_ice": "crack", &"extreme_cold": "thermo"}
const BLIZZARD_VISIBILITY := 6

var vis: HudVisibility
var kind: StringName = &""
var state: StringName = &""
var detail: String = ""
## World clock (s, HUD time) when the countdown ends; -1 = unknown.
var ends_at: float = -1.0
var changes: int = 0
var _clock: float = 0.0
var _end_hide_at: float = -1.0
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
	elif kind == &"blizzard" and (state == &"active" or state == &"soon"):
		set_hazard(&"blizzard", &"end", {})


## Seconds of blizzard left when this process runs the server (offline / host); -1 when unknown (remote client).
func _blizzard_left() -> float:
	if not Net.is_server or get_tree().current_scene == null:
		return -1.0
	var w := get_tree().current_scene.get_node_or_null("World/Weather")
	if w == null:
		return -1.0
	var left: Variant = w.get("_time_left")
	return float(left) if left != null and float(left) > 0.0 else -1.0


func set_hazard(k: StringName, s: StringName, data: Dictionary = {}) -> void:
	if s == state and k == kind and s != &"soon":
		return
	kind = k
	state = s
	changes += 1
	var secs := float(data.get("seconds", -1.0))
	ends_at = _clock + secs if secs > 0.0 else -1.0
	detail = str(data.get("detail", ""))
	if detail == "" and k == &"blizzard" and s == &"active":
		detail = "visibilidad %d m" % BLIZZARD_VISIBILITY
	_end_hide_at = _clock + 3.0 if s == &"end" else -1.0
	if vis != null:
		vis.poke(EL, 3.0 if s == &"end" else -1.0)
	AudioManager.play(&"ui_warn" if s == &"soon" else &"ui_hazard")
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	if state == &"end" and _clock > _end_hide_at + float(UiTokens.T_HAZARD[2]):
		state = &""
		kind = &""
	if state == &"active" and ends_at < 0.0 and _clock - float(int(_clock)) < delta:
		var left := _blizzard_left()
		if left > 0.0:
			ends_at = _clock + left
	var full := vis.alpha_of(EL) if vis != null else 1.0
	var compact := 1.0 if state == &"soon" or state == &"active" else 0.0
	var a := maxf(full, compact)
	visible = a > 0.002 and state != &""
	shown_alpha = a
	_scrim.modulate.a = a
	_scrim.position = Vector2(size.x - 470.0, -60.0)
	_scrim.size = Vector2(600.0, 150.0)
	_scrim.strength = 1.2
	var key := "%s|%s|%d|%.2f" % [kind, state, int(_left()), full]
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


func _left() -> float:
	return ends_at - _clock if ends_at > 0.0 else -1.0


## Full line text parts (for tests): [name, detail, time].
func line_parts() -> Array:
	var parts: Array = [String(NAMES.get(kind, String(kind)))]
	match state:
		&"forecast":
			parts[0] += " prevista"
			parts.append(detail if detail != "" else "en unas horas")
		&"soon":
			parts.append("se acerca")
		&"active":
			if detail != "":
				parts.append(detail)
		&"end":
			parts[0] = "la %s amaina" % String(NAMES.get(kind, String(kind)))
	var left := _left()
	if left > 0.0 and state != &"end":
		parts.append(UiTokens.countdown(left))
	return parts


func _draw() -> void:
	if state == &"":
		return
	var full := vis.alpha_of(EL) if vis != null else 1.0
	var right := size.x
	var y := 18.0
	var icon := String(ICONS.get(kind, "snow"))
	var parts := line_parts()
	var sep_w := UiStyle.text_width(&"whisper", " · ")
	# compact form (icon + time) under the full line's fade
	var ca := (1.0 - full) if state == &"soon" or state == &"active" else 0.0
	if ca > 0.002:
		var left := _left()
		var t := UiTokens.countdown(left) if left > 0.0 else ""
		var tw := UiStyle.text_width(&"text_num", t)
		if t != "":
			UiStyle.draw_text(self, &"text_num", Vector2(right - tw, y), t, UiTokens.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ca)
		Whisper.draw_icon(self, icon, Vector2(right - tw - (14.0 if t != "" else 8.0), y - 6.0), 16.0, UiTokens.COLD, ca)
	if full <= 0.002:
		return
	# full line: icon, NAME in cold small caps, the rest in ink with ink-70 separators
	var widths: Array = []
	var total := 0.0
	for i in parts.size():
		var w := UiStyle.text_width(&"smallcaps_wide" if i == 0 else &"whisper", str(parts[i]))
		widths.append(w)
		total += w + (sep_w if i > 0 else 0.0)
	var x := right - total
	Whisper.draw_icon(self, icon, Vector2(x - 18.0, y - 6.0), 16.0, UiTokens.COLD, full)
	for i in parts.size():
		if i > 0:
			UiStyle.draw_text(self, &"whisper", Vector2(x, y), " · ", UiTokens.INK_70, HORIZONTAL_ALIGNMENT_LEFT, -1.0, full)
			x += sep_w
		var style := &"smallcaps_wide" if i == 0 else &"whisper"
		var col := UiTokens.COLD if i == 0 else UiTokens.INK
		UiStyle.draw_text(self, style, Vector2(x, y), str(parts[i]), col, HORIZONTAL_ALIGNMENT_LEFT, -1.0, full)
		x += float(widths[i])
	Whisper.hair(self, Vector2(right - UiTokens.HAZARD_RULE, y + 11.0), Vector2(right, y + 11.0), UiTokens.HAIR, 2, full)
