class_name MissionLog
extends Node
## Client-side mission list of the local player (HUD v2, docs/research/10_hud_ux.md §V.4.3, §V.4.8): reads the
## `missions` of the mirrored quest state (`Events.quest_updated`), keeps which one is tracked (a client choice,
## "Y seguir otra"), diffs every update and emits `Events.objective_updated(mission, step, what)`:
##   mission_new   a mission appeared (the HUD line says "nueva misión")
##   progress      the current step's count went up ("objetivo actualizado", 1/2 → 2/2)
##   completed     a step was completed (the next one becomes current: "objetivo actualizado")
##   mission_done  the last step was completed ("misión completada")
## It also resolves the step targets to world positions (`targets_of`), nearest first.

var missions: Array = []
var tracked_id: String = ""
## Last change: {mission, step, what, t} (HUD clock seconds, `Time.get_ticks_msec`).
var last_change: Dictionary = {}
var changes: int = 0
var _prev: Dictionary = {}   # mission id -> {index, progress, done}


func _ready() -> void:
	Events.quest_updated.connect(_on_quest_updated)
	var st: PlayerState = GameFlow.local_state()
	if st != null and not st.quest_state.is_empty():
		_on_quest_updated(st.quest_state)
	GameFlow.local_player_changed.connect(func(_p: Node) -> void:
		var s: PlayerState = GameFlow.local_state()
		if s != null and not s.quest_state.is_empty():
			_on_quest_updated(s.quest_state))


func _on_quest_updated(state: Dictionary) -> void:
	apply(Missions.from_quest_state(state))


## Replaces the list and emits the differences (public for tests).
func apply(list: Array) -> void:
	missions = list.duplicate(true)
	if tracked_id == "" or Missions.by_id(missions, tracked_id).is_empty() or Missions.is_done(Missions.by_id(missions, tracked_id)):
		tracked_id = str(Missions.tracked(missions).get("id", ""))
	var seen := {}
	for m: Dictionary in missions:
		var id := str(m["id"])
		seen[id] = true
		var idx := Missions.current_index(m)
		var cur := Missions.current_step(m)
		var prog := int(cur.get("progress", 0))
		var done := Missions.is_done(m)
		if not _prev.has(id):
			if not done:
				_emit(id, str(cur.get("id", "")), &"mission_new")
		else:
			var p: Dictionary = _prev[id]
			if done and not bool(p["done"]):
				var steps: Array = m.get("steps", [])
				_emit(id, str((steps[steps.size() - 1] as Dictionary).get("id", "")) if not steps.is_empty() else "", &"mission_done")
			elif idx > int(p["index"]):
				_emit(id, str(cur.get("id", "")), &"completed")
			elif idx == int(p["index"]) and prog > int(p["progress"]):
				_emit(id, str(cur.get("id", "")), &"progress")
		_prev[id] = {"index": idx, "progress": prog, "done": done}
	for id: String in _prev.keys():
		if not seen.has(id):
			_prev.erase(id)
	Events.mission_state.emit(missions)


func _emit(mission_id: String, step_id: String, what: StringName) -> void:
	last_change = {"mission": mission_id, "step": step_id, "what": what, "t": Time.get_ticks_msec() / 1000.0}
	changes += 1
	Events.objective_updated.emit(StringName(mission_id), StringName(step_id), what)


func tracked() -> Dictionary:
	var m := Missions.by_id(missions, tracked_id)
	return m if not m.is_empty() else Missions.tracked(missions)


## "Y seguir otra": the next active mission becomes the tracked one.
func track_next() -> void:
	var active: Array = []
	for m: Dictionary in missions:
		if not Missions.is_done(m):
			active.append(str(m["id"]))
	if active.size() <= 1:
		return
	var i := active.find(tracked_id)
	tracked_id = active[(i + 1) % active.size()]
	Events.mission_state.emit(missions)


func active_count() -> int:
	var n := 0
	for m: Dictionary in missions:
		if not Missions.is_done(m):
			n += 1
	return n


## World positions of a step's targets, nearest to `from` first: [{pos, label}] (at most `limit`).
func targets_of(step: Dictionary, from: Vector3, limit: int = 3) -> Array:
	var out: Array = []
	for t: Dictionary in step.get("targets", []):
		for pos: Vector3 in MissionTargets.resolve(t, from, get_tree()):
			out.append({"pos": pos, "label": str(t.get("label", ""))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return from.distance_squared_to(a["pos"]) < from.distance_squared_to(b["pos"]))
	if out.size() > limit:
		out.resize(limit)
	return out


## The nearest target of the tracked mission's current step, or {}.
func tracked_target(from: Vector3) -> Dictionary:
	var m := tracked()
	if m.is_empty() or Missions.is_done(m):
		return {}
	var list := targets_of(Missions.current_step(m), from, 1)
	return list[0] if not list.is_empty() else {}
