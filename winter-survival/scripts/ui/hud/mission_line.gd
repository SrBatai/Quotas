class_name MissionLine
extends Control
## "Objetivo actualizado" line (docs/research/10_hud_ux.md §V.4.3, mockup v2_b), top left: an 8 px amber diamond,
## the small-caps amber eyebrow, the objective in 22 px Light with its count in ink-70, an amber hairline that
## grows to 300 px in 600 ms and the mission in 16 px. Shows on a new / updated / completed objective (5 s, 320 ms
## in, 1 s out). No strike-through, no list: the completed step is seen in the world (✓) and in the Info list.
## With the "Completo" preset (element `tracker` = always) it stays as a one-line tracker without the eyebrow.

const EL := &"mission"
const WHAT_TEXT := {&"mission_new": "nueva misión", &"progress": "objetivo actualizado",
	&"completed": "objetivo actualizado", &"mission_done": "misión completada"}

var vis: HudVisibility
var mlog: MissionLog
var what: StringName = &""
var objective: String = ""
var count: String = ""
var mission: String = ""
var updates: int = 0
var _since: float = 99.0
var _scrim: Scrim


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = Scrim.new()
	_scrim.name = "Scrim"
	_scrim.show_behind_parent = true
	_scrim.position = Vector2(-184.0, -96.0)
	_scrim.size = Vector2(820.0, 300.0)
	add_child(_scrim)
	Events.objective_updated.connect(_on_objective)
	Events.mission_state.connect(func(_m: Array) -> void: _refresh_text())


func setup(v: HudVisibility, l: MissionLog) -> void:
	vis = v
	mlog = l
	vis.register(EL, self, UiTokens.T_OBJECTIVE, false, &"tracker")
	_refresh_text()


func _on_objective(_mission_id: StringName, _step_id: StringName, w: StringName) -> void:
	what = w
	_since = 0.0
	updates += 1
	_refresh_text()
	if w == &"mission_done":
		var m := Missions.by_id(mlog.missions, String(_mission_id)) if mlog != null else {}
		objective = str(m.get("title", mission))
		count = ""
		mission = ""
	if vis != null:
		vis.poke(EL)
	AudioManager.play(&"ui_mission_done" if w == &"mission_done" else &"ui_objective_update")
	queue_redraw()


func _refresh_text() -> void:
	if mlog == null:
		return
	var m := mlog.tracked()
	if m.is_empty():
		return
	var s := Missions.current_step(m)
	objective = str(s.get("title", ""))
	count = Missions.progress_text(s)
	mission = str(m.get("title", ""))
	queue_redraw()


func _process(delta: float) -> void:
	if _since < 10.0:
		_since += delta
		queue_redraw()
	elif visible and vis != null and vis.phase_of(EL) != HudVisibility.Phase.SHOWN:
		queue_redraw()


func _draw() -> void:
	if objective == "":
		return
	var eyebrow := _since < float(UiTokens.T_OBJECTIVE[1]) + float(UiTokens.T_OBJECTIVE[2]) and what != &""
	var slide := UiMotion.slide(UiTokens.MOVE_MAX) * (1.0 - clampf(_since / float(UiTokens.T_OBJECTIVE[0]), 0.0, 1.0)) if eyebrow else 0.0
	var y := slide
	if eyebrow:
		Whisper.diamond(self, Vector2(4.0, y + 8.0), UiTokens.DIAMOND_INLINE, UiTokens.ACCENT, true, 1.0, false)
		UiStyle.draw_text(self, &"smallcaps_wide", Vector2(18.0, y + 13.0), String(WHAT_TEXT.get(what, "objetivo actualizado")), UiTokens.ACCENT)
		y += 30.0
	else:
		Whisper.diamond(self, Vector2(-14.0, y + 22.0), UiTokens.DIAMOND_INLINE, UiTokens.ACCENT, true, 1.0)
	UiStyle.draw_text(self, &"main", Vector2(0.0, y + 20.0), objective, UiTokens.INK_RGB)
	if count != "":
		var ow := UiStyle.text_width(&"main", objective)
		UiStyle.draw_text(self, &"main", Vector2(ow + 10.0, y + 20.0), count, UiTokens.INK_70)
	y += 32.0
	if eyebrow:
		var k := UiMotion.ease_in_curve(clampf(_since / UiTokens.T_OBJECTIVE_RULE, 0.0, 1.0)) if not UiMotion.reduced() else 1.0
		Whisper.hair(self, Vector2(0.0, y), Vector2(UiTokens.OBJECTIVE_RULE * k, y), UiTokens.ACCENT, 3)
		y += 10.0
	if mission != "":
		UiStyle.draw_text(self, &"meta", Vector2(0.0, y + 14.0), mission, UiTokens.INK_70)
