extends "res://tests/net/net_steps.gd"
## H2 net scenario `discovery` (PLAN v3.8.1 H2 acceptance; C35 `shared_discovery`), driven by
## tests/net/run_discovery_test.sh around a server restart:
##   phase 1, clients A and B (B joins 0.7 s later): A turns the director off, teleports to the Granja del Molino and
##            discovers it (its own full title; the server records it and tells the group); B, still in the clearing,
##            gets the P3 feed line «A descubrió: Granja del Molino» (it waits for it: under load the clients drift by
##            seconds), then goes there itself and sees the COMPACT title
##            (a re-entry for the group: the name at 60 %), without asking the server for a new discovery.
##   phase 2, client C (a new player) after save-and-quit and a new server process on the same store: the discovery
##            was restored (C's sync already knows the farm), C goes there and sees the compact title, no feed line.
## Every client prints RESULT OK / FAIL with its checks.

const MOLINO := Vector3(-128.0, 0.0, -896.0)
const ZONE := "granja_del_molino"

var phase: int = 1
var _cards: Array = []   # [id, card, first_visit] of every title / sign shown
var _feed: Array = []    # P3 feed bodies
var _found: Array = []   # [id, by, own] of every zone_discovered
var _checks: Dictionary = {}


func _run_client() -> void:
	phase = int(opts.get("phase", 1))
	super._run_client()
	Events.location_entered.connect(func(i: Dictionary) -> void:
		if str(i.get("card", "none")) != "none":
			_cards.append([str(i["id"]), str(i["card"]), bool(i.get("first_visit", false))])
			_log("card %s %s first_visit=%s" % [i["id"], i["card"], i.get("first_visit", false)]))
	Events.notify_ex.connect(func(n: Dictionary) -> void:
		if int(n.get("priority", 2)) >= 3:
			_feed.append(str(n.get("body", "")))
			_log("feed: %s" % n.get("body", "")))
	Events.zone_discovered.connect(func(id: StringName, by: String, own: bool) -> void:
		_found.append([String(id), by, own])
		_log("zone_discovered %s by %s own=%s" % [id, by, own]))
	_build_discovery_timeline()


func _card_of(id: String) -> Array:
	for c: Array in _cards:
		if str(c[0]) == id:
			return c
	return []


## The server takes 2 chat lines per second per player: under load a client frame can bunch its timeline lines and
## the third is dropped, so commands are 1.2 s apart and the teleports are checked and sent again.
func _tp_if_far(lp: Player, pos: Vector3) -> void:
	if Vector2(lp.global_position.x - pos.x, lp.global_position.z - pos.z).length() > 30.0:
		_log("not at %s yet (%s): /tp again" % [pos, lp.global_position.snapped(Vector3(0.1, 0.1, 0.1))])
		_tp(pos)


func _build_discovery_timeline() -> void:
	var tl := []
	var quiet := [
		[1.0, func(_lp: Player, _w: Node) -> void: Chat.instance.send("/director off")],
		[2.2, func(_lp: Player, _w: Node) -> void: Chat.instance.send("/zombies clear")],
	]
	if phase == 1 and client_name == "A":
		tl = quiet + [
			[3.4, func(_lp: Player, _w: Node) -> void: _tp(MOLINO)],
			[5.6, func(lp: Player, _w: Node) -> void: _tp_if_far(lp, MOLINO)],
			[7.8, func(lp: Player, _w: Node) -> void: _tp_if_far(lp, MOLINO)],
			[9.0, func(_lp: Player, _w: Node) -> void: Chat.instance.send("/director off")],
			[10.2, func(_lp: Player, _w: Node) -> void: Chat.instance.send("/zombies clear")],
			# the title waits the 20 s between cards (A's first card was the clearing's, at ≈ 1.8 s)
			[33.0, func(_lp: Player, _w: Node) -> void:
				var c := _card_of(ZONE)
				_checks["full_card"] = not c.is_empty() and str(c[1]) == "full" and bool(c[2])
				_checks["discovered"] = _found.has([ZONE, "A", true])
				_log("A: card %s, discoveries %s" % [c, _found])],
		]
	elif phase == 1:
		# B waits for A's discovery (event-driven: under load the two clients drift by seconds), then goes there
		tl = []
		for k in 14:
			tl.append([6.0 + 1.5 * k, func(lp: Player, _w: Node) -> void:
				var disc := ZoneDiscovery.instance
				if disc == null or not disc.known.has(ZONE):
					return
				if not _checks.has("feed"):
					_checks["feed"] = _feed.has("A descubrió: Granja del Molino")
					_checks["known"] = str(disc.known.get(ZONE, "")) == "A"
					_log("B: feed %s, known %s → going there" % [_feed, disc.known])
					_tp(MOLINO)
				else:
					_tp_if_far(lp, MOLINO)])
		tl.append([33.0, func(_lp: Player, _w: Node) -> void:
			var c := _card_of(ZONE)
			_checks["compact"] = not c.is_empty() and str(c[1]) == "compact" and not bool(c[2])
			var disc := ZoneDiscovery.instance
			_checks["no_rediscovery"] = disc != null and not disc.pending.has(ZONE) and not _found.has([ZONE, "B", true])
			_log("B at the farm: card %s, pending %s" % [c, disc.pending if disc != null else {}])])
	else:
		tl = quiet + [
			[3.4, func(_lp: Player, _w: Node) -> void:
				var disc := ZoneDiscovery.instance
				_checks["restored"] = disc != null and disc.synced and str(disc.known.get(ZONE, "")) == "A"
				_log("C after the restart: synced %s, known %s" % [disc.synced if disc != null else false, disc.known if disc != null else {}])],
			[3.5, func(_lp: Player, _w: Node) -> void: _tp(MOLINO)],
			[5.7, func(lp: Player, _w: Node) -> void: _tp_if_far(lp, MOLINO)],
			[7.9, func(lp: Player, _w: Node) -> void: _tp_if_far(lp, MOLINO)],
			[24.0, func(_lp: Player, _w: Node) -> void:
				var c := _card_of(ZONE)
				_checks["compact_after_restart"] = not c.is_empty() and str(c[1]) == "compact" and not bool(c[2])
				_checks["no_feed"] = _feed.filter(func(b: String) -> bool: return b.contains("Granja del Molino")).is_empty()
				_log("C at the farm: card %s, feed %s" % [c, _feed])],
		]
	tl.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	_timeline = tl


func _finish(lp: Player) -> void:
	tree.process_frame.disconnect(_client_frame)
	var keys: Array = ["full_card", "discovered"] if client_name == "A" else (["feed", "known", "compact", "no_rediscovery"] if phase == 1
		else ["restored", "compact_after_restart", "no_feed"])
	var ok := _local_seen and lp != null
	for k in keys:
		if not bool(_checks.get(k, false)):
			ok = false
	_log("RESULT %s name=%s scenario=%s phase=%d checks=%s cards=%s rtt_max=%.0f" % ["OK" if ok else "FAIL", client_name, scenario, phase,
		_checks, _cards, _rtt_max])
	tree.quit(0 if ok else 1)
