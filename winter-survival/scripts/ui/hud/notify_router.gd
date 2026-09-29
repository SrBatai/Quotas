class_name NotifyRouter
extends Node
## Notification router of the HUD v2 (H3; docs/research/10_hud_ux.md §V.3 "Avisos críticos", §V.8 "UI‑3", §V.9.3,
## appendix §6.5). Four priorities, and no central banner for the critical ones:
##   P0  compañero derribado o muerto, te estás congelando, hielo fino bajo los pies, alud — shown IN THE WORLD (the
##       downed indicator, the "!" at the feet) or ON THE AFFECTED VITAL, never as a banner; it lasts while its
##       condition does (`seconds` 0 + `end_p0(key)` / a `hold` Callable, or `seconds` > 0). Its sound (`sound`)
##       plays once with a direction-labelled caption (SoundCaptions). For P0_ATTENTION s it owns the attention:
##       a P1 / P2 line shown > 1.2 s yields (it goes back to the queue), the others wait; the queue resumes 300 ms
##       later. «Banner P0 mínimo» (setting `p0_banner`, R29 plan B) also puts it on the line.
##   P1  peligro inminente, misión completada, Gran Ventisca — the 3 s line (NotifyBanner) with a small-caps eyebrow.
##   P2  misión nueva, compañero que entra o sale, un ping de peligro — the same line.
##   P3  pickups, crafting, discoveries, "la ventisca amaina" — the pickup line bottom right (PickupStack), merged.
## Line rules: one at a time, queue of 6 (full: the oldest of the lowest priority goes), the same key on screen
## refreshes it (×N) and a queued one is updated instead of repeated, cooldown keys at most once per 8 s, P1 / P2
## wait while a zone title is on screen, co-op filter (from another player only what affects you: `from_peer` +
## `affects_me`). Every legacy `Events.notify(text, seconds)` is classified: weather → HazardLine, cold / hunger →
## the vitals (freezing is a P0 on Calor), "Sin aliento" → the stamina arc, crafted / eaten / stove → P3, own downed
## → the DownedOverlay (P0 self), the rest a P2 line. Pickups come from the inventory mirror diff.
## Standalone-testable (tests/unit/notify_router_test.gd): every sink may be null and `tick(dt)` drives the clock.

signal routed(text: String, where: StringName)

var banner: NotifyBanner
var feed: PickupStack
var hazard: HazardLine
var zone_title: ZoneTitle
var vis: HudVisibility
## SoundCaptions (untyped: optional): the router tells it where a 2D P0 sound comes from.
var captions: Node
## The P1 / P2 line queue and the notice on the line.
var queue: Array = []
var current: Dictionary = {}
## Active P0 notices: key -> notice (+ t, until).
var p0: Dictionary = {}
var clock: float = 0.0
var counts: Dictionary = {}   # where -> n (tests)
var stats: Dictionary = {"merged": 0, "dropped": 0, "cooled": 0, "preempted": 0, "filtered": 0, "p0": 0, "shown": 0}
## Tests: the last notices shown on the line (key list, newest last) and the P0 keys raised.
var shown_keys: Array = []
var p0_keys: Array = []
var _shown_at: float = -100.0
var _until: float = 0.0
var _hidden_at: float = -100.0
var _attention_until: float = -100.0
var _last_key_t: Dictionary = {}
var _hold_acc: float = 0.0
var _inv: Dictionary = {}
var _inv_ready: bool = false
var _crafted: Dictionary = {}   # display name -> clock

## Keys shown at most once every 8 s (appendix §6.5 "Enfriamiento por clave").
const COOLDOWN_KEYS := ["No se puede colocar aquí", "Inventario lleno", "Contenedor lleno", "No tienes comida", "Sin leña"]
## P0 targets: where the notice lives instead of a banner.
const TARGETS := [&"world", &"vital", &"self"]


func _ready() -> void:
	Events.notify.connect(notify_text)
	Events.notify_ex.connect(push)
	Events.inventory_changed.connect(_on_inventory)
	GameFlow.local_player_changed.connect(func(_p: Node) -> void:
		_inv_ready = false
		_on_inventory())
	Events.player_respawned.connect(func() -> void: _inv_ready = false)


# ------------------------------------------------------------------ legacy text notices
## Legacy text notices → the right channel.
func notify_text(text: String, seconds: float = 3.0) -> void:
	var t := text.strip_edges()
	if t == "":
		return
	var where := _classify(t, seconds)
	counts[where] = int(counts.get(where, 0)) + 1
	routed.emit(t, where)


func _classify(t: String, seconds: float) -> StringName:
	match t:
		"Sin aliento":
			return &"stamina"
		"Se acerca una ventisca…":
			if hazard != null:
				hazard.set_hazard(&"blizzard", &"soon", {"seconds": Balance.BLIZZARD_WARNING} if Net.is_server else {})
			return &"hazard"
		"La ventisca amaina":
			if hazard != null and hazard.stack.state_of(&"blizzard") != &"end":
				hazard.set_hazard(&"blizzard", &"end", {})
			return &"hazard"
		"Te estás congelando":
			if vis != null:
				vis.poke(&"vitals.warmth")
			push({"priority": 0, "key": "freezing", "title": "te estás congelando", "body": "Te estás congelando",
				"target": &"vital", "vital": &"warmth", "seconds": 0.0, "hold": _still_freezing})
			return &"vitals"
		"Tienes frío", "Tienes hambre", "Te mueres de hambre":
			if vis != null:
				vis.poke(&"vitals.hunger" if t.contains("hambre") else &"vitals.warmth")
			return &"vitals"
		"¡Estás derribado! Aguanta hasta que te reanimen":
			push({"priority": 0, "key": "self_down", "title": "derribado", "body": t, "target": &"self", "seconds": 0.0,
				"hold": _still_downed})
			return &"downed"
		"Alimentas la estufa", "Añades leña a la fogata", "Fogata colocada", "Kit de pruebas recibido", "Armas de prueba recibidas":
			if feed != null:
				feed.add("msg:" + t, t, 0, 0)
			return &"feed"
	if t.begins_with("Fabricado: "):
		var n := t.substr(11)
		_crafted[n] = clock
		if feed != null:
			feed.replace_item_line(n, "craft:" + n, "Fabricado · " + n)
		return &"feed"
	if t.begins_with("Comes ") or t.begins_with("Has reanimado") or t.begins_with("Te han reanimado") or t.begins_with("Te levantas"):
		if feed != null:
			feed.add("msg:" + t, t, 0, 0)
		return &"feed"
	if t.ends_with(" se ha roto") or t.begins_with("Aviso del servidor"):
		push({"priority": 1, "key": t, "title": "", "body": t, "seconds": 4.0, "tone": &"warn"})
		return &"banner"
	push({"priority": 2, "key": t, "title": "", "body": t, "seconds": clampf(seconds, 1.5, 6.0)})
	return &"banner"


func _still_freezing() -> bool:
	var st: PlayerState = GameFlow.local_state()
	return st != null and not st.dead and st.warmth < Balance.FREEZING_SLOW_BELOW


func _still_downed() -> bool:
	var p := GameFlow.local_player() as Player
	return p != null and p.downed and not p.dead


# ------------------------------------------------------------------ structured notices
## A structured notice: {priority 0–3, key, title, body, seconds, tone (&"" | &"warn" | &"danger" | &"accent" |
## &"cold"), and for P0: target (&"world" | &"vital" | &"self"), vital, pos, subject, peer, sound, hold (Callable),
## icon; co-op: from_peer, affects_me}.
func push(n: Dictionary) -> void:
	var pr := clampi(int(n.get("priority", 2)), 0, 3)
	var key := str(n.get("key", n.get("body", "")))
	# co-op filter (appendix §6.5): from another player only what affects you
	var from := int(n.get("from_peer", 0))
	if from != 0 and from != Net.local_peer_id() and not bool(n.get("affects_me", false)):
		stats["filtered"] = int(stats["filtered"]) + 1
		return
	if pr >= 3:
		if feed != null:
			feed.add("msg:" + key, str(n.get("body", key)), 0, 0)
		counts[&"feed"] = int(counts.get(&"feed", 0)) + 1
		return
	if pr == 0:
		_p0_start(n, key)
		if not bool(UiSettings.get_value("p0_banner")):
			return
		n = n.duplicate()
		n["seconds"] = minf(float(n.get("seconds", 0.0)) if float(n.get("seconds", 0.0)) > 0.0 else UiTokens.P0_ATTENTION, UiTokens.P0_ATTENTION)
		n["tone"] = n.get("tone", &"danger")
	# cooldown keys
	if COOLDOWN_KEYS.has(key) and clock - float(_last_key_t.get(key, -100.0)) < UiTokens.NOTIFY_KEY_COOLDOWN:
		stats["cooled"] = int(stats["cooled"]) + 1
		return
	# the same key on the line → refresh it (×N); queued → update it instead of repeating
	if not current.is_empty() and str(current["key"]) == key:
		_until = maxf(_until, clock + float(n.get("seconds", 3.0)))
		current["count"] = int(current.get("count", 1)) + 1
		stats["merged"] = int(stats["merged"]) + 1
		if banner != null:
			banner.show_notice(current, queue.size())
		return
	for q: Dictionary in queue:
		if str(q["key"]) == key:
			q["seconds"] = n.get("seconds", q["seconds"])
			q["body"] = n.get("body", q.get("body", ""))
			q["count"] = int(q.get("count", 1)) + 1
			stats["merged"] = int(stats["merged"]) + 1
			return
	var e := n.duplicate()
	e["priority"] = pr
	e["key"] = key
	e["t"] = clock
	e["count"] = 1
	queue.append(e)
	_sort_queue()
	while queue.size() > UiTokens.NOTIFY_QUEUE:
		# drop the oldest of the lowest priority
		var worst := 0
		for i in queue.size():
			var a: Dictionary = queue[i]
			var b: Dictionary = queue[worst]
			if int(a["priority"]) > int(b["priority"]) or (int(a["priority"]) == int(b["priority"]) and float(a["t"]) < float(b["t"])):
				worst = i
		queue.remove_at(worst)
		stats["dropped"] = int(stats["dropped"]) + 1


func _sort_queue() -> void:
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["priority"]) < int(b["priority"]) or (int(a["priority"]) == int(b["priority"]) and float(a["t"]) < float(b["t"])))


# ------------------------------------------------------------------ P0
func _p0_start(n: Dictionary, key: String) -> void:
	var secs := float(n.get("seconds", 0.0))
	if p0.has(key):
		var old: Dictionary = p0[key]
		old["until"] = clock + secs if secs > 0.0 else INF
		for f in ["body", "pos", "hold", "subject"]:
			if n.has(f):
				old[f] = n[f]
		return
	var e := n.duplicate()
	e["priority"] = 0
	e["key"] = key
	e["t"] = clock
	e["until"] = clock + secs if secs > 0.0 else INF
	var target: StringName = e.get("target", &"world")
	e["target"] = target if TARGETS.has(target) else &"world"
	p0[key] = e
	p0_keys.append(key)
	stats["p0"] = int(stats["p0"]) + 1
	counts[&"p0"] = int(counts.get(&"p0", 0)) + 1
	_attention_until = clock + UiTokens.P0_ATTENTION
	# precedence: a P1 / P2 line shown for more than 1.2 s yields and goes back to the queue (first of its priority:
	# it keeps its arrival time)
	if not current.is_empty() and clock - _shown_at > UiTokens.NOTIFY_PREEMPT_AFTER:
		var back := current.duplicate()
		back["preempted"] = true
		queue.append(back)
		_sort_queue()
		_hide_current()
		stats["preempted"] = int(stats["preempted"]) + 1
	if e["target"] == &"vital" and vis != null:
		var el := StringName("vitals." + String(e.get("vital", &"warmth")))
		vis.poke(el)
		vis.set_hold(el, true)
	var snd: StringName = e.get("sound", &"")
	if snd != &"":
		var pos: Vector3 = e.get("pos", Vector3.INF)
		if captions != null:
			captions.call("expect", snd, pos, str(e.get("subject", "")), int(e.get("peer", 0)))
		AudioManager.play_ex(snd, pos if bool(e.get("sound_3d", false)) else Vector3.INF)
	Events.p0_notice.emit(e, true)


## Ends a P0 now (its condition is over). Unknown keys are ignored.
func end_p0(key: String) -> void:
	var e: Dictionary = p0.get(key, {})
	if e.is_empty():
		return
	p0.erase(key)
	if e.get("target", &"") == &"vital" and vis != null:
		var el := StringName("vitals." + String(e.get("vital", &"warmth")))
		var still := false
		for o: Dictionary in p0.values():
			if o.get("target", &"") == &"vital" and o.get("vital", &"") == e.get("vital", &""):
				still = true
		if not still:
			vis.set_hold(el, false)
	Events.p0_notice.emit(e, false)


func p0_active() -> bool:
	return not p0.is_empty()


## The P0 notices that live in the world (the WorldLayer draws those with a position and no own indicator).
func p0_world() -> Array:
	var out: Array = []
	for e: Dictionary in p0.values():
		if e.get("target", &"") == &"world":
			out.append(e)
	return out


# ------------------------------------------------------------------ line
func _hide_current() -> void:
	current = {}
	_hidden_at = clock
	if banner != null:
		banner.show_notice({}, 0)


func _process(delta: float) -> void:
	tick(delta)


## Advances the router's clock (the HUD's _process; tests call it directly).
func tick(delta: float) -> void:
	clock += delta
	# P0 conditions (4 Hz) and timers
	_hold_acc += delta
	if not p0.is_empty():
		var check_holds := _hold_acc >= 0.25
		for key: String in p0.keys():
			var e: Dictionary = p0[key]
			var over := clock >= float(e["until"])
			if not over and check_holds and e.get("hold") is Callable:
				var c: Callable = e["hold"]
				over = c.is_valid() and not bool(c.call())
			if over:
				end_p0(key)
	if _hold_acc >= 0.25:
		_hold_acc = 0.0
	if not current.is_empty() and clock >= _until:
		_hide_current()
	if current.is_empty() and not queue.is_empty() and clock - maxf(_hidden_at, _shown_at) > UiTokens.NOTIFY_GAP:
		var next: Dictionary = queue[0]
		var waits := (zone_title != null and zone_title.is_showing() and int(next["priority"]) > 0) \
			or (clock < _attention_until and int(next["priority"]) > 0)
		if not waits:
			queue.pop_front()
			_show(next)
	elif banner != null and not current.is_empty():
		banner.set_waiting(queue.size())


func _show(n: Dictionary) -> void:
	current = n
	_shown_at = clock
	_until = clock + float(n.get("seconds", float(UiTokens.T_BANNER[1])))
	_last_key_t[str(n["key"])] = clock
	stats["shown"] = int(stats["shown"]) + 1
	shown_keys.append(str(n["key"]))
	if shown_keys.size() > 32:
		shown_keys.pop_front()
	var snd: StringName = n.get("sound", &"")
	if snd != &"":
		AudioManager.play_ex(snd, n.get("pos", Vector3.INF))
	if banner != null:
		banner.show_notice(current, queue.size())


## Tests / screenshots: drop every notice (line, queue and P0).
func clear_all() -> void:
	queue.clear()
	current = {}
	for key: String in p0.keys():
		end_p0(key)
	_attention_until = -100.0
	if banner != null:
		banner.show_notice({}, 0)


# ------------------------------------------------------------------ pickups (inventory mirror diff)
func _on_inventory() -> void:
	var st: PlayerState = GameFlow.local_state()
	if st == null:
		return
	var now := {}
	for s: Dictionary in st.slots:
		if not s.is_empty():
			now[s["id"]] = int(now.get(s["id"], 0)) + int(s["count"])
	if _inv_ready and feed != null:
		for id in now:
			var d := int(now[id]) - int(_inv.get(id, 0))
			if d > 0:
				var n := Items.display_name(id)
				if clock - float(_crafted.get(n, -100.0)) < 1.5:
					continue   # just crafted: the "Fabricado" line covers it
				feed.add("item:" + String(id), n, d, int(now[id]))
				counts[&"pickup"] = int(counts.get(&"pickup", 0)) + 1
	_inv = now
	_inv_ready = GameFlow.local_player() != null
