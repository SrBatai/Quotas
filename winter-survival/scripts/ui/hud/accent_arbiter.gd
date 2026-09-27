class_name AccentArbiter
extends Node
## "Un solo acento" (docs/research/10_hud_ux.md §V.1 rules 4–5, §V.8): decides what carries the amber and the ONE
## edge-of-screen marker, by priority —
##   1. a downed teammate (the nearest),
##   2. the nearest known heat source while freezing (Calor < 30): a lit campfire, or the refuge with its stove lit,
##   3. the tracked objective's nearest target.
## The edge marker shows for priorities 1–2 all the time, and for the objective only for 5 s after it updates
## (element `edge`) or while Info is held. Heat sources within 60 m (up to 2) are listed for the world markers.

const PERIOD := 0.1

var team: TeamTracker
var mlog: MissionLog
var vis: HudVisibility
## {kind: &"downed" | &"heat" | &"objective" | &"", pos: Vector3, label: String, dist: float, player: Player}
var accent: Dictionary = {}
var heat: Array = []   # [{pos, label, dist}] nearest first (only while Calor < 30)
var _acc: float = 0.0


func setup(t: TeamTracker, l: MissionLog, v: HudVisibility) -> void:
	team = t
	mlog = l
	vis = v
	vis.register(&"edge", null, UiTokens.T_EDGE, true, &"")
	Events.objective_updated.connect(func(_m: StringName, _s: StringName, _w: StringName) -> void: vis.poke(&"edge"))


func _process(delta: float) -> void:
	_acc += delta
	if _acc < PERIOD:
		return
	_acc = 0.0
	update()


func update() -> void:
	var p := GameFlow.local_player() as Player
	if p == null or not p.is_inside_tree():
		accent = {}
		heat = []
		return
	var me := p.global_position
	# 1. downed teammate
	var d := team.nearest_downed() if team != null else {}
	if not d.is_empty():
		var o := TeamTracker.player_of(d)
		accent = {"kind": &"downed", "pos": o.global_position, "label": str(d["name"]), "dist": float(d["dist"]), "player": o}
		heat = _heat_sources(p) if p.state != null and p.state.warmth < UiTokens.HEAT_ACCENT_BELOW else []
		return
	# 2. heat while freezing
	heat = []
	if p.state != null and p.state.warmth < UiTokens.HEAT_ACCENT_BELOW and not p.dead:
		heat = _heat_sources(p)
		if not heat.is_empty():
			var h: Dictionary = heat[0]
			accent = {"kind": &"heat", "pos": h["pos"], "label": str(h["label"]), "dist": float(h["dist"]), "player": null}
			return
	# 3. tracked objective
	var t := mlog.tracked_target(me) if mlog != null else {}
	if not t.is_empty():
		var tp: Vector3 = t["pos"]
		accent = {"kind": &"objective", "pos": tp, "label": str(t["label"]), "player": null,
			"dist": Vector2(tp.x - me.x, tp.z - me.z).length()}
		return
	accent = {}


## Lit campfires and refuges (a lit stove) within 60 m, nearest first (2 at most).
func _heat_sources(p: Player) -> Array:
	var out: Array = []
	var me := p.global_position
	for n in get_tree().get_nodes_in_group("heat_source"):
		if n is Node3D:
			var q := (n as Node3D).global_position
			var dd := Vector2(q.x - me.x, q.z - me.z).length()
			if dd <= UiTokens.HEAT_RANGE:
				out.append({"pos": q, "label": "fogata", "dist": dd})
	for n in get_tree().get_nodes_in_group("stove"):
		if n is Node3D and bool(n.get("is_lit")):
			var q := (n as Node3D).global_position
			var dd := Vector2(q.x - me.x, q.z - me.z).length()
			if dd <= UiTokens.HEAT_RANGE and not p.in_house:
				out.append({"pos": q, "label": "refugio", "dist": dd})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	if out.size() > 2:
		out.resize(2)
	return out


## Whether the single edge marker may show right now.
func edge_allowed() -> bool:
	if accent.is_empty():
		return false
	var k: StringName = accent["kind"]
	if k == &"downed" or k == &"heat":
		return true
	return vis != null and (vis.is_on(&"edge") or vis.info_active)
