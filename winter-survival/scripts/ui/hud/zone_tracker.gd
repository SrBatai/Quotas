class_name ZoneTracker
extends Node
## Zone entry for the title card (docs/research/10_hud_ux.md §V.3 "Título de zona", appendix §6.1). Replaces the
## per-chunk region banner (its borders moved up to 45 m and flickered at full opacity on every crossing):
## - evaluated at the player's POSITION every 0.25 s against `Locations` (most specific first);
## - hysteresis: a place is entered when the player is ≥ 12 m inside it (half the size for small places) for
##   1.5 s, and left only when ≥ 12 m outside — walking a border in zigzag changes nothing;
## - first visit → full card (5.6 s); re-entry → the name at 60 % (2.5 s), none for natural areas, and none
##   within 90 s of the last card of that place; 20 s between cards (only the last waiting one is kept);
## - deferred while in combat (a hit, a swing or a chasing zombie in the last 5 s) and while a P0 lasts
##   (downed, freezing: the card then becomes compact); dropped if the player left meanwhile.
## Emits `Events.location_entered(info)` for every confirmed entry (info.card = full | compact | none) and
## `Events.location_left(id)`. Discovery is kept per world seed in user://hud_discovered.cfg (the server-side,
## group-shared discovery of appendix §6.1 is deferred).

const PATH := "user://hud_discovered.cfg"
const PERIOD := 0.25

var current: Dictionary = {}
var pending: Dictionary = {}
var pending_t: float = 0.0
var queued: Dictionary = {}
var discovered: Dictionary = {}
var last_card: Dictionary = {}   # id -> clock
var last_card_t: float = -1000.0
var clock: float = 0.0
## Confirmed entries (a zigzag test counts these).
var entries: int = 0
var cards: int = 0
var enabled: bool = true
## Callables provided by the HUD: () -> bool.
var in_combat: Callable = func() -> bool: return false
var p0_active: Callable = func() -> bool: return false
var _acc: float = 0.0
var _seed_key: String = ""


func _ready() -> void:
	_load()


func _process(delta: float) -> void:
	clock += delta
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


## One evaluation at `pos` after `dt` seconds (public: tests feed positions directly).
func step(pos: Vector3, dt: float) -> void:
	_check_seed()
	var cand := candidate(pos.x, pos.z)
	var cid := str(cand.get("id", ""))
	if cid == str(current.get("id", "")):
		pending = {}
		pending_t = 0.0
	elif cid == str(pending.get("id", "")):
		pending_t += dt
		if pending_t >= UiTokens.ZONE_DWELL:
			_enter(cand)
			pending = {}
			pending_t = 0.0
	else:
		pending = cand
		pending_t = dt
	_try_queued(pos)


## The place the player is in with hysteresis: the current place holds until the player is `inset` outside it;
## a more specific place (earlier in the list) takes over once the player is `inset` inside it.
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


func _enter(e: Dictionary) -> void:
	var old := str(current.get("id", ""))
	if old != "":
		Events.location_left.emit(StringName(old))
	current = e
	entries += 1
	var id := str(e["id"])
	var first := not discovered.has(id)
	var kind := str(e.get("kind", "poi"))
	var cards_of: Array = Locations.CARD.get(kind, ["full", "compact"])
	var card := str(cards_of[0] if first else cards_of[1])
	if not first and clock - float(last_card.get(id, -1000.0)) < UiTokens.ZONE_COOLDOWN:
		card = "none"
	if first:
		discovered[id] = true
		_save()
	var info := info_for(e, first, card)
	if card != "none":
		queued = info
		_try_queued(Vector3.INF)
		if not queued.is_empty():
			Events.location_entered.emit(_with_card(info, "none"))   # the location line updates now
	else:
		Events.location_entered.emit(info)


## Card info of a place (public: screenshots and tests).
func info_for(e: Dictionary, first: bool, card: String) -> Dictionary:
	var night := WorldState.is_night_now()
	return {
		"id": StringName(str(e["id"])), "name": str(e["name"]), "kind": str(e.get("kind", "poi")),
		"parent": (Locations.parents(e)[0] if not Locations.parents(e).is_empty() else ""),
		"facts": Locations.facts(e, UiClimate.air_now(), night), "first_visit": first, "card": card,
	}


func _with_card(info: Dictionary, card: String) -> Dictionary:
	var d := info.duplicate()
	d["card"] = card
	return d


## Shows the waiting card when allowed (gap between cards, not in combat, no P0). Dropped once the player left.
func _try_queued(_pos: Vector3) -> void:
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
	Events.location_entered.emit(info)


## Tests / screenshots: forget every discovery (next entries are first visits again) and the cooldowns.
func forget_all() -> void:
	_check_seed()
	discovered.clear()
	last_card.clear()
	last_card_t = -1000.0
	current = {}
	pending = {}
	queued = {}
	_save()


func _check_seed() -> void:
	var key := "seed_%d" % (WorldState.instance.world_seed if WorldState.instance != null else 0)
	if key != _seed_key:
		_seed_key = key
		_load()


func _load() -> void:
	discovered.clear()
	if _seed_key == "":
		return
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for id: String in cfg.get_value(_seed_key, "ids", PackedStringArray()):
		discovered[id] = true


func _save() -> void:
	if _seed_key == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(_seed_key, "ids", PackedStringArray(discovered.keys()))
	cfg.save(PATH)
