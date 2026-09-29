class_name ZoneTracker
extends Node
## Zone entry and exit (H2, PLAN C35; docs/research/10_hud_ux.md §V.3–V.4.4 and appendix §6.1). Evaluated at the
## player's POSITION every 0.25 s against `Locations` (LocationInfo records, most specific first):
## - hysteresis: a zone is entered when the player is ≥ 12 m inside it (a quarter of the size in small places) for
##   1.5 s, and left only when ≥ 12 m outside for 1.5 s — walking a border in zigzag changes nothing;
## - hierarchy: city → district → POI, the deepest one wins (standing in Las Torres = «Las Torres», Altavega is its
##   first fact); natural areas, water and roads after the places, like the region banner;
## - cards: first visit → the 5.6 s title («zona descubierta», name, one line of facts); re-entry → the name at 60 %
##   for 2.5 s (none in natural areas and on roads); roads and anyone faster than 40 km/h on a road (a vehicle, M7;
##   today a scripted fast mover) → the 3 s highway sign; 90 s per zone and 20 s between cards: only the LAST waiting
##   card is kept (a queue of 1; the others only update the location line);
## - deferred while in combat (a hit, a swing or a chasing zombie in the last 5 s) and while a P0 lasts (downed,
##   freezing, a P0 notice on screen: the card turns compact); dropped if the player left meanwhile;
## - leaving: no card; one P3 line in the feed only when the new zone is better («Has salido del Control militar km
##   12»: the danger drops from alto / extremo, and the new zone is not inside the old one);
## - discovery: the first confirmed entry asks ZoneDiscovery (server-authoritative, shared by the group with
##   `shared_discovery`); a zone the group already knows gives the compact title;
## - `zone_entered` (Events, and the signal below): every confirmed zone once outside combat (latest wins) — the
##   camera profile (C28) follows it.
## A bare tracker (tests) keeps its discoveries in `discovered` and only emits its own signals; the HUD's tracker
## (`publish = true`) also emits Events.location_entered / location_left / zone_entered and the P3 exit line.

signal entered(info: Dictionary)
signal card_shown(info: Dictionary)
signal zone_changed(info: Dictionary)
signal left(id: StringName)
signal exit_line(text: String)

const PERIOD := 0.25
## 40 km/h (C35: the highway sign in a vehicle faster than that, on roads).
const FAST_SPEED := 40.0 / 3.6
## A jump longer than this in one step is a teleport, not speed.
const TELEPORT_JUMP := 60.0
const SPEED_WINDOW := 1.5
## "On a road": within this many metres of a drivable bed's edge.
const ON_ROAD := 4.0

var current: Dictionary = {}
var pending: Dictionary = {}
var pending_t: float = 0.0
var queued: Dictionary = {}
## Zones this tracker counts as discovered (the ZoneDiscovery cache when there is one: the same Dictionary).
var discovered: Dictionary = {}
var last_card: Dictionary = {}   # id -> clock
var last_card_t: float = -1000.0
var clock: float = 0.0
## Confirmed entries (a zigzag test counts these), cards shown, exit lines, zone_entered events.
var entries: int = 0
var cards: int = 0
var exits: int = 0
var zone_events: int = 0
var enabled: bool = true
## True for the HUD's tracker: mirror on Events + discovery requests.
var publish: bool = false
## Server discovery (the HUD sets ZoneDiscovery.instance); null = local only.
var discovery: ZoneDiscovery = null:
	set(v):
		discovery = v
		discovered = v.known if v != null else {}
## Callables provided by the HUD: () -> bool.
var in_combat: Callable = func() -> bool: return false
var p0_active: Callable = func() -> bool: return false
## Horizontal speed (m/s) over the last 1.5 s and the direction of travel.
var speed: float = 0.0
var heading: Vector2 = Vector2.ZERO
var _hist: Array = []   # [dx, dz, dt]
var _last_pos: Vector3 = Vector3.INF
var _zone_evt: Dictionary = {}
var _acc: float = 0.0


func _process(delta: float) -> void:
	clock += delta
	if publish and discovery == null and ZoneDiscovery.instance != null:
		discovery = ZoneDiscovery.instance   # game.gd adds it after the HUD
	if not enabled:
		return
	_acc += delta
	if _acc < PERIOD:
		return
	var dt := _acc
	_acc = 0.0
	var p := GameFlow.local_player() as Player
	if p == null or not p.is_inside_tree() or p.dead:
		return
	step(p.global_position, dt)


## One evaluation at `pos` after `dt` seconds (public: tests feed positions directly — a scripted mover).
func step(pos: Vector3, dt: float) -> void:
	_update_speed(pos, dt)
	var cand := candidate(pos.x, pos.z)
	var cid := str(cand.get("id", ""))
	if cid == str(current.get("id", "")):
		pending = {}
		pending_t = 0.0
	elif cid == str(pending.get("id", "")):
		pending_t += dt
		if pending_t >= UiTokens.ZONE_DWELL:
			_enter(cand, pos)
			pending = {}
			pending_t = 0.0
	else:
		pending = cand
		pending_t = dt
	_try_queued()
	_try_zone_event()


## The zone the player is in, with hysteresis: the current zone holds until the player is `inset` outside it; a more
## specific zone (earlier in the list) takes over once the player is `inset` inside it.
func candidate(x: float, z: float) -> Dictionary:
	var cur_id := str(current.get("id", ""))
	for e: Dictionary in Locations.all():
		var d := Locations.depth(e, x, z)
		var ins := Locations.inset(e)
		if str(e["id"]) == cur_id:
			if d > -ins:
				return e
		elif d >= ins:
			return e
	return Locations.DEFAULT


func is_discovered(id: String) -> bool:
	return discovery.is_known(id) if discovery != null else discovered.has(id)


## Faster than 40 km/h on a drivable road (the highway sign replaces the titles).
func fast_on_road(pos: Vector3) -> bool:
	return speed > FAST_SPEED and not Locations.road_at(pos.x, pos.z, ON_ROAD).is_empty()


func _update_speed(pos: Vector3, dt: float) -> void:
	if _last_pos != Vector3.INF:
		var dx := pos.x - _last_pos.x
		var dz := pos.z - _last_pos.z
		if dx * dx + dz * dz > TELEPORT_JUMP * TELEPORT_JUMP:
			_hist.clear()   # a teleport (/tp, respawn): no speed, no direction
			heading = Vector2.ZERO
		else:
			_hist.append([dx, dz, dt])
	_last_pos = pos
	var t := 0.0
	var sx := 0.0
	var sz := 0.0
	var dist := 0.0
	for i in range(_hist.size() - 1, -1, -1):
		var h: Array = _hist[i]
		if t >= SPEED_WINDOW:
			_hist = _hist.slice(i + 1)
			break
		t += float(h[2])
		sx += float(h[0])
		sz += float(h[1])
		dist += Vector2(float(h[0]), float(h[1])).length()
	speed = dist / t if t >= 0.5 else 0.0
	heading = Vector2(sx, sz).normalized() if Vector2(sx, sz).length() > 0.5 else heading


func _enter(e: Dictionary, pos: Vector3) -> void:
	var old := current
	if not old.is_empty():
		left.emit(StringName(str(old["id"])))
		if publish:
			Events.location_left.emit(StringName(str(old["id"])))
		_exit_line(old, e)
	current = e
	entries += 1
	var id := str(e["id"])
	var first := not is_discovered(id)
	var cards_of := Locations.cards_of(e)
	var card := str(cards_of[0] if first else cards_of[1])
	if not first and card != "none" and clock - float(last_card.get(id, -1000.0)) < UiTokens.ZONE_COOLDOWN:
		card = "none"
	if card != "none" and fast_on_road(pos):
		card = "sign"
	if first:
		if discovery != null and publish:
			discovery.discover(id)
		elif discovery == null:
			discovered[id] = true
	var info := info_for(e, first, card)
	if card == "sign":
		info["sign"] = ZoneSign.compose(e, pos, heading)
	_zone_evt = info
	_try_zone_event()
	if card != "none":
		queued = info
		_try_queued()
		if not queued.is_empty():
			_emit_entered(_with_card(info, "none"))   # the location line updates now; the card waits
	else:
		_emit_entered(info)


## Card info of a zone (public: screenshots and tests).
func info_for(e: Dictionary, first: bool, card: String) -> Dictionary:
	var night := WorldState.is_night_now()
	var ps := Locations.parents(e)
	return {
		"id": StringName(str(e["id"])), "name": str(e["name"]), "kind": str(e.get("kind", "poi")),
		"parent": (ps[0] if not ps.is_empty() else ""), "facts": Locations.facts(e, UiClimate.air_now(), night),
		"first_visit": first, "card": card, "camera": e.get("camera", &""), "chain": Locations.chain_ids(e),
		"danger": Locations.danger_now(e, night),
	}


func _with_card(info: Dictionary, card: String) -> Dictionary:
	var d := info.duplicate()
	d["card"] = card
	return d


func _emit_entered(info: Dictionary) -> void:
	entered.emit(info)
	if publish:
		Events.location_entered.emit(info)


## Shows the waiting card when allowed (gap between cards, not in combat, no P0). Dropped once the player left.
func _try_queued() -> void:
	if queued.is_empty():
		return
	if str(queued["id"]) != str(current.get("id", "")):
		queued = {}
		return
	if clock - last_card_t < UiTokens.ZONE_GAP and last_card_t > -999.0:
		return
	if in_combat.call():
		return
	if p0_active.call():
		if str(queued["card"]) == "full":
			queued["card"] = "compact"
		return
	var info := queued
	queued = {}
	last_card_t = clock
	last_card[str(info["id"])] = clock
	cards += 1
	card_shown.emit(info)
	_emit_entered(info)


## zone_entered once outside combat (the camera profile never switches in a fight, C28); latest zone wins.
func _try_zone_event() -> void:
	if _zone_evt.is_empty():
		return
	if str(_zone_evt["id"]) != str(current.get("id", "")):
		_zone_evt = {}
		return
	if in_combat.call():
		return
	var info := _zone_evt
	_zone_evt = {}
	zone_events += 1
	zone_changed.emit(info)
	if publish:
		Events.zone_entered.emit(info)


## Leaving is silent unless it is good news: one P3 line when the danger drops from alto / extremo into a zone that
## is not inside the one left («Has salido del Control militar km 12»).
func _exit_line(old: Dictionary, new: Dictionary) -> void:
	if Locations.is_within(new, old):
		return
	var night := WorldState.is_night_now()
	var d_old := Locations.danger_now(old, night)
	if d_old < 2 or Locations.danger_now(new, night) >= d_old:
		return
	var text := "Has salido %s" % LocationInfo.de(old)
	exits += 1
	exit_line.emit(text)
	if publish:
		Events.notify_ex.emit({"priority": 3, "key": "exit:" + str(old["id"]), "body": text})


## Tests / screenshots: forget every discovery (next entries are first visits again) and the cooldowns.
func forget_all() -> void:
	if discovery != null:
		discovery.forget_all()
	else:
		discovered.clear()
	last_card.clear()
	last_card_t = -1000.0
	current = {}
	pending = {}
	queued = {}
	_zone_evt = {}
	_hist.clear()
	_last_pos = Vector3.INF
	speed = 0.0
