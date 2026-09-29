class_name HazardStack
extends RefCounted
## Environment hazards known to the HUD (H3; docs/research/10_hud_ux.md §V.3 "Peligro", §V.4.6, appendix §6.7):
## one entry per kind moving through   forecast (previsto) → soon (inminente) → active (activo) → end (fin).
## Blizzard and Gran Ventisca are wired today (the server's Weather through HudNet, the offline signals); the other
## kinds are the API for E1 / E2 — thin ice, ice storm, cold wave, avalanche, blackout, fire (and extreme cold):
##   Events.hazard_changed.emit(&"ice_storm", &"soon", {"seconds": 60.0})
##   Events.hazard_changed.emit(&"thin_ice", &"active", {"pos": p, "detail": "6 m"})      # zone kinds: no timer
##   Events.hazard_changed.emit(&"thin_ice", &"end", {})
## (or HudNet.broadcast_hazard(kind, state, data) on the server, which replicates it to every client).
## `data`: seconds (countdown to the next state / the end), detail (the line's middle part), pos (world point:
## distance on the line, P0 in the world), source. Repeated states only refresh the countdown. The stack keeps
## no nodes: HazardLine draws it (the top entry in full for 5 s, then icon + time; 2 entries at most) and turns the
## transitions into sounds and notices (P1 sound on imminent / active, P0 in the world for thin ice underfoot or an
## avalanche, the ending pulse in the last 15 s).

signal changed(kind: StringName, state: StringName, old_state: StringName)

const STATES := [&"forecast", &"soon", &"active", &"end"]
const ALIASES := {&"imminent": &"soon", &"inminente": &"soon", &"previsto": &"forecast", &"prevista": &"forecast",
	&"activo": &"active", &"activa": &"active", &"fin": &"end", &"clear": &"end"}
## Order on screen: active, then imminent, then the fading end line, then forecasts; within a state by `rank`.
const STATE_ORDER := {&"active": 0, &"soon": 1, &"end": 2, &"forecast": 3}
## name (Spanish, lower case: drawn in small caps), line icon, rank, notice level on imminent / active
## (0 = P0 in the world, 1 = P1 sound, 2 = the line only), the default detail per state, `zone` = lasts while you
## are inside (no timer), `end` = the P3 line when it is over ("" = none).
const SPECS := {
	&"great_blizzard": {"name": "gran ventisca", "icon": "storm", "rank": 0, "p_soon": 1, "p_active": 1,
		"forecast": "en 1 día", "soon": "hoy", "active": "hoy", "end": "La gran ventisca amaina"},
	&"blizzard": {"name": "ventisca", "icon": "snow", "rank": 1, "p_soon": 1, "p_active": 1,
		"forecast": "en unas horas", "soon": "se acerca", "active": "visibilidad 6 m", "end": "La ventisca amaina"},
	&"avalanche": {"name": "alud", "icon": "wind", "rank": 2, "p_soon": 1, "p_active": 0,
		"forecast": "riesgo en las laderas", "soon": "riesgo alto", "active": "¡apártate de la ladera!", "end": ""},
	&"thin_ice": {"name": "hielo fino", "icon": "crack", "rank": 3, "p_soon": 2, "p_active": 0, "zone": true,
		"forecast": "", "soon": "cerca", "active": "no corras ni lleves peso", "end": ""},
	&"fire": {"name": "incendio", "icon": "flame", "rank": 4, "p_soon": 1, "p_active": 1,
		"forecast": "", "soon": "humo cerca", "active": "humo y calor", "end": "El incendio se ha apagado"},
	&"ice_storm": {"name": "tormenta de hielo", "icon": "storm", "rank": 5, "p_soon": 1, "p_active": 1,
		"forecast": "esta noche", "soon": "se acerca", "active": "suelo resbaladizo · caen ramas", "end": "La tormenta de hielo amaina"},
	&"cold_wave": {"name": "ola de frío", "icon": "thermo", "rank": 6, "p_soon": 1, "p_active": 1,
		"forecast": "mañana", "soon": "esta noche", "active": "−31 °C sentida", "end": "Remite la ola de frío"},
	&"blackout": {"name": "sin electricidad", "icon": "boltoff", "rank": 7, "p_soon": 2, "p_active": 2, "zone": true,
		"forecast": "", "soon": "cortes", "active": "calles a oscuras · ascensores parados", "end": ""},
	&"extreme_cold": {"name": "frío extremo", "icon": "thermo", "rank": 8, "p_soon": 2, "p_active": 2, "zone": true,
		"forecast": "", "soon": "", "active": "", "end": ""},
}
## The fading "la ventisca amaina" line lasts this long before the entry goes.
const END_HOLD := 3.0

## kind -> {kind, state, ends_at (stack clock; -1 = no timer), detail, pos, since, source, seq}
var entries: Dictionary = {}
var clock: float = 0.0
## Every state change (tests).
var changes: int = 0
var history: Array = []   # [[kind, state], …] the last 16 transitions (tests / debug)


static func norm_state(s: StringName) -> StringName:
	var t := StringName(String(s).to_lower())
	return ALIASES.get(t, t)


static func spec(kind: StringName) -> Dictionary:
	return SPECS.get(kind, {"name": String(kind).replace("_", " "), "icon": "snow", "rank": 9, "p_soon": 2, "p_active": 2,
		"forecast": "", "soon": "", "active": "", "end": ""})


static func name_of(kind: StringName) -> String:
	return str(spec(kind)["name"])


static func icon_of(kind: StringName) -> String:
	return str(spec(kind)["icon"])


## Level of the notice a state raises (0 = P0, 1 = P1, 2 = line only, 3 = P3), for HazardLine.
static func level_of(kind: StringName, state: StringName) -> int:
	var s := spec(kind)
	match state:
		&"soon": return int(s["p_soon"])
		&"active": return int(s["p_active"])
		&"end": return 3
	return 2


## Applies a state. Returns true when something visible changed (a new state, or a countdown that moved > 1.5 s).
func set_hazard(kind: StringName, state: StringName, data: Dictionary = {}) -> bool:
	var st := norm_state(state)
	if not STATE_ORDER.has(st):
		return false
	var e: Dictionary = entries.get(kind, {})
	var old: StringName = e.get("state", &"")
	var secs := float(data.get("seconds", -1.0))
	if st == &"end":
		if e.is_empty() or old == &"end":
			return false
		e["state"] = &"end"
		e["ends_at"] = clock + END_HOLD
		e["since"] = clock
		_changed(kind, st, old)
		return true
	var fresh := e.is_empty() or old != st
	if e.is_empty():
		e = {"kind": kind, "seq": 0}
		entries[kind] = e
	var moved := false
	if secs > 0.0:
		var at := clock + secs
		moved = fresh or float(e.get("ends_at", -1.0)) < 0.0 or absf(float(e.get("ends_at", -1.0)) - at) > 1.5
		if moved:
			e["ends_at"] = at
	elif fresh:
		e["ends_at"] = -1.0
	var detail := str(data.get("detail", ""))
	if detail != "" and detail != str(e.get("detail", "")):
		e["detail"] = detail
		moved = true
	elif fresh:
		e["detail"] = detail
	if data.has("pos"):
		e["pos"] = data["pos"]
	e["source"] = data.get("source", e.get("source", &""))
	if not fresh:
		return moved
	e["state"] = st
	e["since"] = clock
	e["seq"] = int(e.get("seq", 0)) + 1
	_changed(kind, st, old)
	return true


func _changed(kind: StringName, st: StringName, old: StringName) -> void:
	changes += 1
	history.append([kind, st])
	if history.size() > 16:
		history.pop_front()
	changed.emit(kind, st, old)


## Drops a kind at once (no end line).
func clear(kind: StringName) -> void:
	entries.erase(kind)


func clear_all() -> void:
	entries.clear()


func tick(dt: float) -> void:
	clock += dt
	for kind: StringName in entries.keys():
		var e: Dictionary = entries[kind]
		var st: StringName = e["state"]
		var at := float(e.get("ends_at", -1.0))
		if st == &"end" and clock > at + float(UiTokens.T_HAZARD[2]):
			entries.erase(kind)
		elif st == &"active" and at > 0.0 and clock > at + 5.0 and str(e.get("source", "")) != "server":
			set_hazard(kind, &"end")   # an API hazard whose timer ran out and nobody ended it


func has(kind: StringName) -> bool:
	return entries.has(kind)


func state_of(kind: StringName) -> StringName:
	return (entries.get(kind, {}) as Dictionary).get("state", &"")


## Seconds left on the entry's countdown (−1 = none).
func left(kind: StringName) -> float:
	var e: Dictionary = entries.get(kind, {})
	var at := float(e.get("ends_at", -1.0))
	return maxf(at - clock, 0.0) if at > 0.0 and e.get("state", &"") != &"end" else -1.0


## Entries in screen order (active → imminent → ending → forecast; then rank).
func ordered() -> Array:
	var out: Array = entries.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := int(STATE_ORDER.get(a["state"], 9))
		var sb := int(STATE_ORDER.get(b["state"], 9))
		if sa != sb:
			return sa < sb
		return int(spec(a["kind"])["rank"]) < int(spec(b["kind"])["rank"]))
	return out


func top() -> Dictionary:
	var o := ordered()
	return o[0] if not o.is_empty() else {}


## Forecast entries not drawn (the "+1 previsto" of the full line).
func forecasts_beyond(n_drawn: int) -> int:
	var o := ordered()
	var k := 0
	for i in range(n_drawn, o.size()):
		if (o[i] as Dictionary)["state"] == &"forecast":
			k += 1
	return k


## Text parts of an entry's full line: [NAME, detail…, time]. Detail defaults from SPECS per state.
func parts_of(e: Dictionary) -> Array:
	if e.is_empty():
		return []
	var kind: StringName = e["kind"]
	var st: StringName = e["state"]
	var s := spec(kind)
	var nm := str(s["name"])
	var detail := str(e.get("detail", ""))
	var parts: Array = [nm]
	match st:
		&"forecast":
			parts[0] = nm + (" prevista" if nm.ends_with("a") else " previsto")
			parts.append(detail if detail != "" else (str(s["forecast"]) if str(s["forecast"]) != "" else "en unas horas"))
		&"soon":
			parts.append(str(s["soon"]) if str(s["soon"]) != "" else "se acerca")
			if detail != "":
				parts.append(detail)
		&"active":
			var d := detail if detail != "" else str(s["active"])
			if d != "":
				parts.append(d)
		&"end":
			parts[0] = ("la %s amaina" % nm) if kind == &"blizzard" or kind == &"great_blizzard" else ("fin: %s" % nm)
	var pos: Variant = e.get("pos", null)
	if pos is Vector3 and st != &"end" and (pos as Vector3) != Vector3.INF:
		var lp := GameFlow.local_player() as Node3D
		if lp != null:
			var q: Vector3 = pos
			parts.append(UiTokens.distance(Vector2(q.x - lp.global_position.x, q.z - lp.global_position.z).length()))
	var l := left(kind)
	if l >= 0.0 and st != &"end":
		parts.append(UiTokens.countdown(l))
	return parts
