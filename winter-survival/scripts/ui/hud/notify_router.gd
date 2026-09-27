class_name NotifyRouter
extends Node
## Notification router of the HUD v2 (docs/research/10_hud_ux.md §V.8 "UI‑3", appendix §6.5). Two channels:
## - BANNER (top centre, one at a time) for P0–P2, with a queue of 6, priority, pre-emption (a P0 interrupts a P1/P2
##   shown for more than 1.2 s; the interrupted one goes back to the queue), refresh of the same key within 10 s and
##   "N avisos en espera". P1/P2 wait while a zone title is on screen.
## - FEED (side stack, bottom right) for P3: pickups and crafting with merged counters ("Leña +2 (4)").
## Every legacy `Events.notify(text, seconds)` is classified by the table below: the weather notices feed the hazard
## line, the cold / hunger warnings are the vitals' job (v2: criticals live in the world or on the vital, §V.9.3),
## "Sin aliento" is the stamina arc, crafted / eaten / stove messages go to the feed, the rest is a P2 banner.
## Pickups come from the inventory mirror diff (works for remote clients, where `item_picked_up` never fires).

signal routed(text: String, where: StringName)

var banner: NotifyBanner
var feed: PickupStack
var hazard: HazardLine
var zone_title: ZoneTitle
var vis: HudVisibility
var queue: Array = []
var current: Dictionary = {}
var clock: float = 0.0
var counts: Dictionary = {}   # where -> n (tests)
var _shown_at: float = 0.0
var _until: float = 0.0
var _last_key_t: Dictionary = {}
var _inv: Dictionary = {}
var _inv_ready: bool = false
var _crafted: Dictionary = {}   # display name -> clock

## Keys shown at most once every 8 s (appendix §6.5 "Enfriamiento por clave").
const COOLDOWN_KEYS := ["No se puede colocar aquí", "Inventario lleno", "Contenedor lleno", "No tienes comida", "Sin leña"]


func _ready() -> void:
	Events.notify.connect(notify_text)
	Events.notify_ex.connect(push)
	Events.inventory_changed.connect(_on_inventory)
	GameFlow.local_player_changed.connect(func(_p: Node) -> void:
		_inv_ready = false
		_on_inventory())
	Events.player_respawned.connect(func() -> void: _inv_ready = false)


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
			if hazard != null and hazard.state != &"end":
				hazard.set_hazard(&"blizzard", &"end", {})
			return &"hazard"
		"Tienes frío", "Te estás congelando", "Tienes hambre", "Te mueres de hambre":
			if vis != null:
				vis.poke(&"vitals.hunger" if t.contains("hambre") else &"vitals.warmth")
			return &"vitals"
		"¡Estás derribado! Aguanta hasta que te reanimen":
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
	if t.begins_with("Comes ") or t.begins_with("Has reanimado"):
		if feed != null:
			feed.add("msg:" + t, t, 0, 0)
		return &"feed"
	if t.ends_with(" se ha roto") or t.begins_with("Aviso del servidor"):
		push({"priority": 1, "key": t, "title": "", "body": t, "seconds": 4.0, "tone": &"warn"})
		return &"banner"
	push({"priority": 2, "key": t, "title": "", "body": t, "seconds": clampf(seconds, 1.5, 6.0)})
	return &"banner"


## A structured notice: {priority 0–3, key, title, body, seconds, tone (&"" | &"warn" | &"danger" | &"accent")}.
func push(n: Dictionary) -> void:
	var pr := int(n.get("priority", 2))
	var key := str(n.get("key", n.get("body", "")))
	if pr >= 3:
		if feed != null:
			feed.add("msg:" + key, str(n.get("body", key)), 0, 0)
		return
	# cooldown keys
	if COOLDOWN_KEYS.has(key) and clock - float(_last_key_t.get(key, -100.0)) < UiTokens.NOTIFY_KEY_COOLDOWN:
		return
	# the same key shown recently / now → refresh
	if not current.is_empty() and str(current["key"]) == key:
		_until = clock + float(n.get("seconds", 3.0))
		return
	for q: Dictionary in queue:
		if str(q["key"]) == key:
			q["seconds"] = n.get("seconds", q["seconds"])
			return
	var e := n.duplicate()
	e["priority"] = pr
	e["key"] = key
	e["t"] = clock
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
	# pre-emption: a P0 interrupts a P1/P2 shown for more than 1.2 s
	if pr == 0 and not current.is_empty() and int(current["priority"]) > 0 and clock - _shown_at > UiTokens.NOTIFY_PREEMPT_AFTER:
		var back := current.duplicate()
		back["t"] = clock
		queue.append(back)
		_sort_queue()
		_hide_current()


func _sort_queue() -> void:
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["priority"]) < int(b["priority"]) or (int(a["priority"]) == int(b["priority"]) and float(a["t"]) < float(b["t"])))


func _hide_current() -> void:
	current = {}
	if banner != null:
		banner.show_notice({}, 0)


func _process(delta: float) -> void:
	clock += delta
	if not current.is_empty() and clock >= _until:
		_hide_current()
	if current.is_empty() and not queue.is_empty() and clock - _shown_at > 0.3:
		var next: Dictionary = queue[0]
		var waits := zone_title != null and zone_title.is_showing() and int(next["priority"]) > 0
		if not waits:
			queue.pop_front()
			current = next
			_shown_at = clock
			_until = clock + float(next.get("seconds", 3.0))
			_last_key_t[str(next["key"])] = clock
			if banner != null:
				banner.show_notice(current, queue.size())
	elif banner != null and not current.is_empty():
		banner.set_waiting(queue.size())


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
