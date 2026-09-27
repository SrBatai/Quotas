class_name Vitals
extends Control
## Survival constants of the HUD v2 (docs/research/10_hud_ux.md §V.3, §V.4.2, mockups v2_b / v2_d): bottom left,
## ONLY the one that matters — a thin 40 px ring (2 px, no disc), the number in 22 px Regular with its trend,
## and one small-caps word in the semantic colour ("sangrando", "te estás congelando").
##   Salud  shows below 50 or after a change ≥ 2 in 2 s; hides 4 s after it is stable and ≥ 50.
##   Calor  shows below 40, while dropping ≥ 1/s, or when the feels-like temperature moves ≥ 5 °C.
##   Hambre shows below 30 or when eating.
## Holding Info shows the three numbers and the thermal breakdown in one column of text. Below 25 % a ring pulses
## (1 Hz; 1.6 Hz below 10 %). Status words also come from `Events.status_changed` (bleeding, wet: the simulation
## will send them with M8; the words are ready).
## Order when several show at once: Calor, Salud, Hambre (the cold is the core system).

const ORDER := [&"warmth", &"health", &"hunger"]
const ICONS := {&"warmth": "thermo", &"health": "heart", &"hunger": "bowl"}
const RING_COLORS := {&"warmth": UiTokens.COLD, &"health": UiTokens.BLOOD, &"hunger": UiTokens.WARN}
const MAX := {&"warmth": Balance.WARMTH_MAX, &"health": Balance.HEALTH_MAX, &"hunger": Balance.HUNGER_MAX}

var vis: HudVisibility
var values: Dictionary = {&"warmth": Balance.WARMTH_START, &"health": Balance.HEALTH_MAX, &"hunger": Balance.HUNGER_START}
var statuses: Dictionary = {}          # &"bleeding" / &"wet" -> severity 0..1
var rate: Dictionary = {&"warmth": 0.0, &"health": 0.0, &"hunger": 0.0}   # units / s (smoothed)
var feels: float = 0.0
var breakdown: Dictionary = {}
var _hist: Dictionary = {}             # stat -> [[t, v], …] (last 2.5 s)
var _clock: float = 0.0
var _acc: float = 0.0
var _feels_ref: float = INF
var _t: float = 0.0
var _ready_values: bool = false
var _scrim: Scrim


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.stat_changed.connect(_on_stat)
	Events.status_changed.connect(_on_status)
	Events.item_consumed.connect(func(_id: StringName) -> void: _poke(&"hunger"))


func setup(v: HudVisibility) -> void:
	vis = v
	for s: StringName in ORDER:
		vis.register(_el(s), null, UiTokens.T_VITAL, true, &"vitals")
	_scrim = Scrim.new()
	_scrim.name = "Scrim"
	_scrim.show_behind_parent = true
	add_child(_scrim)


static func _el(s: StringName) -> StringName:
	return StringName("vitals." + String(s))


func _poke(s: StringName) -> void:
	if vis != null:
		vis.poke(_el(s))


func _on_stat(stat: StringName, value: float, _max: float) -> void:
	if not values.has(stat):
		return
	var old := float(values[stat])
	values[stat] = value
	var h: Array = _hist.get(stat, [])
	h.append([_clock, value])
	while h.size() > 1 and _clock - float(h[0][0]) > 2.5:
		h.pop_front()
	_hist[stat] = h
	if not _ready_values:
		return
	match stat:
		&"health":
			var ref := value
			for e: Array in h:
				if _clock - float(e[0]) <= UiTokens.HEALTH_DELTA_WINDOW:
					ref = float(e[1])
					break
			if absf(value - ref) >= UiTokens.HEALTH_DELTA:
				_poke(stat)
		&"hunger":
			if value > old + 0.5:
				_poke(stat)
	queue_redraw()


func _on_status(status: StringName, severity: float) -> void:
	if severity <= 0.0:
		statuses.erase(status)
	else:
		var was := float(statuses.get(status, 0.0))
		statuses[status] = severity
		if severity > was:
			_poke(&"health" if status == &"bleeding" else &"warmth")
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	_t += delta
	_acc += delta
	if _acc >= 0.1:
		var dt := _acc
		_acc = 0.0
		_update(dt)
	if _any_visible():
		queue_redraw()
	if _scrim != null:
		var m := 0.0
		for st: StringName in ORDER:
			m = maxf(m, vis.alpha_of(_el(st)) if vis != null else 0.0)
		_scrim.modulate.a = m
		_scrim.visible = m > 0.002
		_scrim.position = Vector2(-124.0, size.y - 150.0 - (140.0 if vis != null and vis.info_active else 0.0))
		_scrim.size = Vector2(620.0, 260.0 + (140.0 if vis != null and vis.info_active else 0.0))


func _update(_dt: float) -> void:
	var st: PlayerState = GameFlow.local_state()
	if st != null:
		values[&"health"] = st.health
		values[&"warmth"] = st.warmth
		values[&"hunger"] = st.hunger
		_ready_values = true
	for s: StringName in ORDER:
		var h: Array = _hist.get(s, [])
		if h.size() >= 2 and _clock - float(h[0][0]) > 0.3:
			var span := maxf(_clock - float(h[0][0]), 0.5)
			rate[s] = (float(values[s]) - float(h[0][1])) / span
		elif h.size() >= 1 and _clock - float(h[-1][0]) > 1.5:
			rate[s] = 0.0
	if vis == null:
		return
	vis.set_hold(_el(&"health"), float(values[&"health"]) < UiTokens.HEALTH_SHOW_BELOW or statuses.has(&"bleeding"))
	vis.set_hold(_el(&"warmth"), float(values[&"warmth"]) < UiTokens.WARMTH_SHOW_BELOW or statuses.has(&"wet") or float(rate[&"warmth"]) <= -UiTokens.WARMTH_DROP_RATE)
	vis.set_hold(_el(&"hunger"), float(values[&"hunger"]) < UiTokens.HUNGER_SHOW_BELOW)
	# feels-like moves ≥ 5 °C (leaving the house, a blizzard) → Calor for 4 s
	var p := GameFlow.local_player() as Player
	if p != null:
		breakdown = UiClimate.breakdown(p)
		feels = float(breakdown["feels"])
		if _feels_ref == INF:
			_feels_ref = feels
		elif absf(feels - _feels_ref) >= UiTokens.FEELS_DELTA:
			_feels_ref = feels
			_poke(&"warmth")


func _any_visible() -> bool:
	if vis == null:
		return true
	for s: StringName in ORDER:
		if vis.alpha_of(_el(s)) > 0.002:
			return true
	return false


## Word under a vital (semantic, small caps), or "".
func word_of(s: StringName) -> String:
	var v := float(values[s])
	match s:
		&"health":
			if statuses.has(&"bleeding"):
				return "sangrando"
			if v < Balance.HEALTH_MAX * UiTokens.LOW_FRACTION:
				return "grave"
			if v < UiTokens.HEALTH_SHOW_BELOW:
				return "herido"
		&"warmth":
			if v < Balance.FREEZING_SLOW_BELOW:
				return "te estás congelando"
			if statuses.has(&"wet"):
				return "mojado %d %%" % int(round(float(statuses[&"wet"]) * 100.0))
			if v < Balance.COLD_VIGNETTE_START:
				return "tienes frío"
		&"hunger":
			if v <= 0.0:
				return "inanición"
			if v < Balance.HUNGRY_WARN:
				return "hambre"
	return ""


func _word_color(s: StringName) -> Color:
	match s:
		&"health": return UiTokens.BLOOD
		&"warmth": return UiTokens.COLD_TEXT if float(values[s]) < Balance.FREEZING_SLOW_BELOW else UiTokens.COLD
		&"hunger": return UiTokens.WARN
	return UiTokens.INK


## Which vitals are showing (alpha > 0.1), for tests.
func shown() -> Array:
	var out: Array = []
	for s: StringName in ORDER:
		if vis != null and vis.alpha_of(_el(s)) > 0.1:
			out.append(s)
	return out


func _draw() -> void:
	if vis == null:
		return
	var x := 0.0
	var base_y := size.y
	var info := vis.info_active
	for s: StringName in ORDER:
		var a := vis.alpha_of(_el(s))
		if a <= 0.002:
			continue
		var v := float(values[s])
		var frac := clampf(v / float(MAX[s]), 0.0, 1.0)
		var c := Vector2(x + UiTokens.RING * 0.5, base_y - UiTokens.RING * 0.5)
		var ra := a
		if frac < UiTokens.LOW_FRACTION:
			var hz := 1.6 if frac < 0.10 else 1.0
			var pl := UiMotion.pulse(_t, hz)
			ra = a * (0.65 + 0.35 * pl)
			draw_circle(c, UiTokens.RING * 0.5 + 4.0, Color(RING_COLORS[s], 0.10 * pl * a))
		Whisper.ring(self, c, UiTokens.RING, frac, RING_COLORS[s], UiTokens.RING_STROKE, ra)
		var icol: Color = UiTokens.COLD_TEXT if s == &"warmth" else (UiTokens.BLOOD_TEXT if s == &"health" else UiTokens.WARN)
		Whisper.draw_icon(self, ICONS[s], c, 16.0, icol, a)
		var tx := x + UiTokens.RING + 12.0
		var num := str(int(round(v)))
		var ncol: Color = UiTokens.BLOOD_TEXT if s == &"health" and v < UiTokens.HEALTH_SHOW_BELOW else UiTokens.INK
		var word := word_of(s)
		var ny := base_y - UiTokens.RING * 0.5 + (2.0 if word == "" else -4.0)
		UiStyle.draw_text(self, &"main_num", Vector2(tx, ny), num, ncol, HORIZONTAL_ALIGNMENT_LEFT, -1.0, a)
		var nw := UiStyle.text_width(&"main_num", num)
		var r := float(rate[s])
		if absf(r) >= (0.25 if s == &"warmth" else 0.4):
			Whisper.trend(self, Vector2(tx + nw + 10.0, ny - 7.0), r > 0.0, UiTokens.COLD if s == &"warmth" else UiTokens.INK_70, 11.0, a)
		var ww := nw + 24.0
		if word != "":
			UiStyle.draw_text(self, &"smallcaps", Vector2(tx, ny + 20.0), word, _word_color(s), HORIZONTAL_ALIGNMENT_LEFT, -1.0, a)
			ww = maxf(ww, UiStyle.text_width(&"smallcaps", word))
		x = tx + ww + 28.0
	# thermal breakdown (Info): one column of text above the rings
	var ia := vis.alpha_of(_el(&"warmth")) if info else 0.0
	if ia > 0.002 and not breakdown.is_empty():
		var y := base_y - UiTokens.RING - 24.0
		var lines: Array = []
		for row: Array in breakdown["rows"]:
			var val := float(row[1])
			lines.append([str(row[0]), UiTokens.temperature(val) if str(row[0]) == "ambiente" else ("%+d °C" % int(round(val))).replace("-", "−")])
		lines.append(["sentida", UiTokens.temperature(feels)])
		var wr := float(rate[&"warmth"])
		lines.append(["calor", ("%+.1f/s" % wr).replace(".", ",").replace("-", "−")])
		for i in range(lines.size() - 1, -1, -1):
			var l: Array = lines[i]
			var strong := str(l[0]) == "sentida" or str(l[0]) == "calor"
			UiStyle.draw_text(self, &"meta", Vector2(0.0, y), str(l[0]), UiTokens.INK_70 if not strong else UiTokens.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ia)
			UiStyle.draw_text(self, &"meta", Vector2(92.0, y), str(l[1]), UiTokens.INK if strong else UiTokens.INK_70, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ia)
			y -= 22.0
