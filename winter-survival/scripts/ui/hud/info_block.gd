class_name InfoBlock
extends Control
## Time, temperature and the group, top right (docs/research/10_hud_ux.md §V.3 "Hora y temperatura", §V.4.8,
## mockup v2_f): "Día 9 · 15:20 · anochece 20:00" / "−19 °C · sentida −12 °C", a 300 px hairline and, with Info,
## the group on one line ("● Ana 84 m · ● Leo 212 m"). Shows with Info, 4 s at dawn / dusk, and 4 s when the
## feels-like temperature moves ≥ 5 °C (element `clock`; the "Completo" preset keeps it). Right-aligned to the
## safe edge; it moves down under the hazard line when both show.

const EL := &"clock"

var vis: HudVisibility
var team: TeamTracker
var vitals: Vitals
var hazard: HazardLine
var _feels_ref: float = INF
var _scrim: Scrim
var _acc: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = Scrim.new()
	_scrim.name = "Scrim"
	_scrim.show_behind_parent = true
	add_child(_scrim)
	Events.day_started.connect(func(_d: int) -> void: _poke())
	Events.night_started.connect(func(_d: int) -> void: _poke())


func setup(v: HudVisibility, t: TeamTracker, vt: Vitals, hz: HazardLine) -> void:
	vis = v
	team = t
	vitals = vt
	hazard = hz
	vis.register(EL, self, UiTokens.T_CLOCK, true, &"clock")


func _poke() -> void:
	if vis != null:
		vis.poke(EL)


func _process(delta: float) -> void:
	_acc += delta
	if _acc >= 0.25 or delta == 0.0:
		_acc = 0.0
		if vitals != null and not vitals.breakdown.is_empty():
			if _feels_ref == INF:
				_feels_ref = vitals.feels
			elif absf(vitals.feels - _feels_ref) >= UiTokens.FEELS_DELTA:
				_feels_ref = vitals.feels
				_poke()
		if visible:
			queue_redraw()
	# below the hazard line when both show
	var off := 0.0
	if hazard != null and hazard.visible:
		off = 44.0 * hazard.shown_alpha
	position.y = off
	_scrim.position = Vector2(size.x - 560.0, -80.0)
	_scrim.size = Vector2(700.0, 250.0)


func _draw() -> void:
	var right := size.x
	var hour := WorldState.hour_now()
	var night := WorldState.is_night_now()
	var l1 := "Día %d · %s" % [WorldState.day_now(), UiTokens.clock(hour)]
	var l1b := " · amanece %s" % UiTokens.clock(Balance.NIGHT_END) if night else " · anochece %s" % UiTokens.clock(Balance.NIGHT_START)
	var w1 := UiStyle.text_width(&"item_name", l1)
	var w1b := UiStyle.text_width(&"whisper", l1b)
	UiStyle.draw_text(self, &"item_name", Vector2(right - w1 - w1b, 18.0), l1, UiTokens.INK_RGB)
	UiStyle.draw_text(self, &"whisper", Vector2(right - w1b, 18.0), l1b, UiTokens.INK_70)
	var air := UiClimate.air_now()
	var l2 := UiTokens.temperature(air)
	var l2b := " · sentida %s" % UiTokens.temperature(vitals.feels) if vitals != null and not vitals.breakdown.is_empty() else ""
	var w2 := UiStyle.text_width(&"text_num", l2)
	var w2b := UiStyle.text_width(&"text_num", l2b)
	UiStyle.draw_text(self, &"text_num", Vector2(right - w2 - w2b, 46.0), l2, UiTokens.INK)
	UiStyle.draw_text(self, &"text_num", Vector2(right - w2b, 46.0), l2b, UiTokens.INK_70)
	if vis == null or not vis.info_active or team == null or team.mates.is_empty():
		return
	Whisper.hair(self, Vector2(right - UiTokens.INFO_RULE, 64.0), Vector2(right, 64.0), UiTokens.HAIR, 2)
	var x := right
	var cb := bool(UiSettings.get_value("colorblind"))
	for i in range(team.mates.size() - 1, -1, -1):
		var m: Dictionary = team.mates[i]
		var d := UiTokens.distance(float(m["dist"]))
		var nm := str(m["name"])
		var wd := UiStyle.text_width(&"text_num", d)
		var wn := UiStyle.text_width(&"whisper", nm + " ")
		x -= wd
		UiStyle.draw_text(self, &"text_num", Vector2(x, 94.0), d, UiTokens.INK_70)
		x -= wn
		UiStyle.draw_text(self, &"whisper", Vector2(x, 94.0), nm + " ", UiTokens.INK)
		x -= 14.0
		draw_circle(Vector2(x + 3.5, 88.0), UiTokens.PLAYER_DOT * 0.5 + 1.0, Color(0, 0, 0, 0.4))
		draw_circle(Vector2(x + 3.5, 88.0), UiTokens.PLAYER_DOT * 0.5, UiTokens.player_color(int(m["color"]), cb))
		x -= 18.0
