class_name Missions
## Mission model of the HUD v2 (docs/research/10_hud_ux.md §8.6, appendix §6.2): three kinds — main (◆, the
## onboarding checklist and, later, the GDD meta), side (◇, survivors' errands) and dynamic (director / radio
## events with a countdown) — each with objectives (steps) that carry a progress count and optional world targets.
## A mission is a plain Dictionary so it travels unchanged in the owner mirror (`PlayerState.quest_state`):
##   {id, kind, title, giver, state, tracked, expires_at (world seconds, -1 = never),
##    steps: [{id, title, hint, count, progress, done, targets: [{anchor, label} | {pos: Vector3, label}]}]}
## Target anchors are resolved on the client (`MissionTargets`): "group:stove", "pickup:madera",
## "group:storage", "zone:<location id>" or an explicit `pos`.

const MAIN := "main"
const SIDE := "side"
const DYNAMIC := "dynamic"
const ACTIVE := "active"
const DONE := "done"
const FAILED := "failed"
## Group headers of the on-demand list (§V.4.8), in order.
const GROUPS := [[MAIN, "misiones"], [SIDE, "encargos"], [DYNAMIC, "en la radio"]]


static func make(id: String, kind: String, title: String, steps: Array, giver: String = "") -> Dictionary:
	return {"id": id, "kind": kind, "title": title, "giver": giver, "state": ACTIVE, "tracked": false,
		"expires_at": -1.0, "steps": steps}


static func step(id: String, title: String, hint: String = "", count: int = 1, targets: Array = []) -> Dictionary:
	return {"id": id, "title": title, "hint": hint, "count": maxi(count, 1), "progress": 0, "done": false,
		"targets": targets}


## Index of the first unfinished step (steps.size() when all are done).
static func current_index(m: Dictionary) -> int:
	var steps: Array = m.get("steps", [])
	for i in steps.size():
		if not bool((steps[i] as Dictionary).get("done", false)):
			return i
	return steps.size()


static func current_step(m: Dictionary) -> Dictionary:
	var steps: Array = m.get("steps", [])
	var i := current_index(m)
	return steps[i] if i < steps.size() else {}


static func is_done(m: Dictionary) -> bool:
	return str(m.get("state", ACTIVE)) == DONE or current_index(m) >= (m.get("steps", []) as Array).size()


## "1/2" for counted steps, "" for single actions.
static func progress_text(s: Dictionary) -> String:
	var n := int(s.get("count", 1))
	if n <= 1:
		return ""
	return "%d/%d" % [mini(int(s.get("progress", 0)), n), n]


## The tracked mission: the one flagged `tracked`, else the first active main, else the first active one.
static func tracked(missions: Array) -> Dictionary:
	var first := {}
	for m: Dictionary in missions:
		if is_done(m):
			continue
		if bool(m.get("tracked", false)):
			return m
		if first.is_empty() or (str(first.get("kind")) != MAIN and str(m.get("kind")) == MAIN):
			first = m
	return first


static func by_id(missions: Array, id: String) -> Dictionary:
	for m: Dictionary in missions:
		if str(m.get("id")) == id:
			return m
	return {}


## The day checklist of `Quests.for_day` as a main mission (server, QuestComponent): steps before `index` are
## done, the current one carries `counter`.
static func from_day(day: int, data: Dictionary, index: int, counter: int) -> Dictionary:
	var steps := []
	var defs: Array = data.get("steps", [])
	for i in defs.size():
		var d: Dictionary = defs[i]
		var s := step(str(d.get("id", "s%d" % i)), str(d["title"]), str(d.get("hint", "")), int(d.get("count", 1)),
			(d.get("targets", []) as Array).duplicate(true))
		if i < index:
			s["done"] = true
			s["progress"] = s["count"]
		elif i == index:
			s["progress"] = counter
		steps.append(s)
	var m := make("dia_%d" % day, MAIN, str(data.get("mission", "Día %d" % day)), steps)
	m["tracked"] = true
	if index >= defs.size():
		m["state"] = DONE
	return m


## Compatibility: a legacy quest state without "missions" (an old server) → one main mission.
static func from_quest_state(q: Dictionary) -> Array:
	if q.has("missions"):
		return q["missions"]
	if q.is_empty():
		return []
	var steps := []
	var list: Array = q.get("steps", [])
	for i in list.size():
		var d: Dictionary = list[i]
		var s := step("s%d" % i, str(d.get("title", "")), str(d.get("hint", "")))
		s["done"] = bool(d.get("done", false))
		s["progress"] = 1 if s["done"] else 0
		steps.append(s)
	var m := make("dia_%d" % int(q.get("day", 1)), MAIN, str(q.get("title_small", "Sobrevive")).capitalize(), steps)
	m["tracked"] = true
	if bool(q.get("day_completed", false)):
		m["state"] = DONE
	return [m]
