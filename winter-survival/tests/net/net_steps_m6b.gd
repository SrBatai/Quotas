extends "res://tests/net/net_steps.gd"
## M6b net scenario `village` (2 clients, PLAN §7 M6b acceptance «2 jugadores en casas distintas ven estados de
## puertas y contenedores coherentes»). Every peer builds its own copy of La Herrería from the seed (same wids);
## only the door / container deltas travel. Each step waits for the state it needs (the server may run slow):
##   both  log the plan hash (the server logs it too: `[SETTLEMENT] plans <hash>`; run_net_test / run_all compare
##         the lines) and exchange it by chat: the two clients' plans must be equal;
##   A     walks to the first enterable house HA of the plan, opens its front door, opens one of its containers that
##         holds something, takes one stack, closes it and tells the chat what is left («LEFT <wid> <items>»);
##   B     the same in another house HB (≥ 18 m away);
##   both  see the OTHER house's front door open (live event), then walk into the other house and open the other's
##         container: its contents are exactly what the other left (server-authoritative contents, one roll).

const SITE := "la_herreria"
const WAIT := 40.0

var _checks: Dictionary = {}
var _started: bool = false
var _hash: String = ""
var _peer_hash: String = ""
var _peer_left: Dictionary = {}       # wid -> items (from the other client's chat)
var _mine: Dictionary = {}            # {"house": index, "wid": container wid, "left": items}


func _run_client() -> void:
	super._run_client()
	_timeline = []
	tree.process_frame.connect(_village_frame)
	Events.chat_message.connect(_on_chat)
	Events.interact_result.connect(func(wid: int, action: StringName, ok: bool, reason: String) -> void:
		if not ok:
			_log("%s: interact %s on %x refused (%s)" % [client_name, action, wid, reason]))


func _on_chat(_who: String, text: String) -> void:
	var parts := text.split(" ", false)
	if parts.size() >= 3 and parts[0] == "HASH" and parts[1] != client_name:
		_peer_hash = parts[2]
	if parts.size() >= 3 and parts[0] == "LEFT" and parts[1] != client_name:
		_peer_left[parts[2].hex_to_int()] = Array(parts.slice(3)) if parts.size() > 3 else []


func _village_frame() -> void:
	if _started or GameFlow.local_player() == null or _connect_time < 0.0:
		return
	var w := World.instance
	if w == null or not w.is_configured:
		return
	_started = true
	_hash = Settlements.plan_hash(w.seed_value).substr(0, 16)
	_log("[SETTLEMENT] client plans %s (seed %d)" % [_hash, w.seed_value])
	_script(client_name == "A")


## The two houses of the test: the first enterable houses of the plan with ≥ 18 m between them.
func _houses() -> Array:
	var p := Settlements.site(World.instance.seed_value, SITE)
	var out: Array = []
	for b: Dictionary in p["buildings"]:
		if str(b["use"]) != "house" or not bool(b["enterable"]):
			continue
		if out.is_empty() or (b["pos"] as Vector2).distance_to((out[0] as Dictionary)["pos"]) >= 18.0:
			out.append(b)
		if out.size() == 2:
			break
	return out


func _building(rec: Dictionary) -> KitBuilding:
	return SettlementSpawner.instance.building(SITE, int(rec["index"])) if SettlementSpawner.instance != null else null


func _front_door(b: KitBuilding) -> KitDoor:
	if b == null:
		return null
	for d in b.doors:
		if d.exterior and str((d.leaf.get_meta("extras", {}) as Dictionary).get("cut_group", "")) == "Walls0_S":
			return d
	for d in b.doors:
		if d.exterior:
			return d
	return null


func _porch(rec: Dictionary, ahead: float) -> Vector3:
	var yaw := deg_to_rad(float(rec["yaw"]))
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var size: Vector2 = rec["size"]
	var p: Vector2 = rec["pos"]
	return Vector3(p.x, 0.0, p.y) + fwd * (size.y * 0.5 + ahead)


func _sleep(s: float) -> void:
	await tree.create_timer(s).timeout


func _until(cond: Callable, timeout: float = WAIT) -> bool:
	var t := 0.0
	while t < timeout:
		if bool(cond.call()):
			return true
		await _sleep(0.25)
		t += 0.25
	return false


func _items(st: Storage) -> Array:
	var out := []
	for sl in st.slots:
		if not sl.is_empty():
			out.append("%s×%d" % [sl["id"], int(sl["count"])])
	out.sort()
	return out


func _containers(b: KitBuilding) -> Array:
	var out: Array = []
	for c in b.find_children("loot_*", "LootContainer", true, false):
		# ground floor only (a /tp lands on the ground floor)
		if not (c as LootContainer).loose and (c as Node3D).global_position.y - b.global_position.y < 1.5:
			out.append(c)
	out.sort_custom(func(x: Node, y: Node) -> bool: return int(x.get_meta("wid")) < int(y.get_meta("wid")))
	return out


func _open_container(c: LootContainer) -> bool:
	var lp := GameFlow.local_player()
	_log("%s: open %x at %s from %s (%.2f m)" % [client_name, WorldRegistry.wid_of(c), c.global_position.snapped(Vector3(0.01, 0.01, 0.01)),
		lp.global_position.snapped(Vector3(0.01, 0.01, 0.01)), lp.global_position.distance_to(c.global_position)])
	Net.rpc_server(NetWorld.instance, &"request_interact", [WorldRegistry.wid_of(c), &"open", 0])
	return await _until(func() -> bool: return c.storage.is_open, 10.0)


func _script(is_a: bool) -> void:
	await _sleep(1.0 if is_a else 2.2)
	if is_a:
		Chat.instance.send("/director off")
		await _sleep(1.2)
		Chat.instance.send("/zombies clear")
		await _sleep(1.2)
	Chat.instance.send("HASH %s %s" % [client_name, _hash])
	await _sleep(1.2)
	var hs := _houses()
	if hs.size() < 2:
		_log("FAIL: fewer than 2 enterable houses in the plan")
		return
	var mine: Dictionary = hs[0] if is_a else hs[1]
	var theirs: Dictionary = hs[1] if is_a else hs[0]
	_tp(_porch(mine, 2.0))
	var built := await _until(func() -> bool: return _front_door(_building(mine)) != null and _front_door(_building(theirs)) != null)
	_checks["built"] = built
	_log("%s: my house %s #%d (%s), theirs %s #%d; built %s" % [client_name, mine["template"], int(mine["number"]), (mine["pos"] as Vector2).snapped(Vector2(0.1, 0.1)),
		theirs["template"], int(theirs["number"]), built])
	if not built:
		return
	await _sleep(1.5)
	# my door
	var door := _front_door(_building(mine))
	_tp(_porch(mine, 1.2))
	await _sleep(1.5)
	Net.rpc_server(NetWorld.instance, &"request_interact", [WorldRegistry.wid_of(door), &"use", 0])
	_checks["own_open"] = await _until(func() -> bool: return door.is_open, 15.0)
	# my container: the first that holds something; take one stack, close, tell the other
	var b := _building(mine)
	var chosen: LootContainer = null
	for c in _containers(b):
		_tp((c as LootContainer).global_position + (c as Node3D).global_transform.basis.z * 1.0)
		await _sleep(1.2)
		if not await _open_container(c):
			continue
		await _sleep(0.6)
		if not _items((c as LootContainer).storage).is_empty():
			chosen = c
			break
		Net.rpc_server(NetWorld.instance, &"request_close_storage", [WorldRegistry.wid_of(c)])
		await _sleep(0.5)
	if chosen == null:
		chosen = _containers(b)[0] if not _containers(b).is_empty() else null
		if chosen != null and not chosen.storage.is_open:
			await _open_container(chosen)
	if chosen == null:
		_log("FAIL: no container in my house")
		return
	var before := _items(chosen.storage)
	for i in chosen.storage.slots.size():
		if not chosen.storage.slots[i].is_empty():
			Net.rpc_server(NetWorld.instance, &"request_take", [WorldRegistry.wid_of(chosen), i, true])
			break
	await _until(func() -> bool: return _items(chosen.storage) != before or before.is_empty(), 6.0)
	await _sleep(0.5)
	var left := _items(chosen.storage)
	_checks["own_take"] = before.is_empty() or left.size() == before.size() - 1
	Net.rpc_server(NetWorld.instance, &"request_close_storage", [WorldRegistry.wid_of(chosen)])
	var cwid := WorldRegistry.wid_of(chosen)
	_log("%s: container %x had %s, left %s" % [client_name, cwid, before, left])
	Chat.instance.send("LEFT %s %x %s" % [client_name, cwid, " ".join(left)])
	# the other house's door opened by the other client (a live event on my copy of the village)
	var their_door := _front_door(_building(theirs))
	_checks["other_open"] = await _until(func() -> bool: return their_door != null and is_instance_valid(their_door) and their_door.is_open)
	_checks["hash_equal"] = await _until(func() -> bool: return _peer_hash != "", 20.0) and _peer_hash == _hash
	# walk into the other house, open the container the other one left, compare
	var got_left := await _until(func() -> bool: return not _peer_left.is_empty())
	if not got_left:
		_log("FAIL: no LEFT message from the other client")
		return
	var pw: int = _peer_left.keys()[0]
	await _sleep(2.0 if is_a else 5.0)     # one at a time at each container (exclusive opening)
	var pc := WorldRegistry.get_object(pw) as LootContainer
	if pc == null:
		_log("FAIL: container %x not found on my copy" % pw)
		return
	_tp(pc.global_position + pc.global_transform.basis.z * 1.0)
	await _sleep(1.5)
	var opened := await _open_container(pc)
	await _sleep(0.8)
	var now := _items(pc.storage)
	var want: Array = _peer_left[pw]
	want.sort()
	_checks["cross_loot"] = opened and now == want
	_log("%s: the other's container %x shows %s (they left %s)" % [client_name, pw, now, want])
	Net.rpc_server(NetWorld.instance, &"request_close_storage", [pw])
	Chat.instance.send("%s ok" % client_name)


func _finish(lp: Player) -> void:
	tree.process_frame.disconnect(_client_frame)
	if tree.process_frame.is_connected(_village_frame):
		tree.process_frame.disconnect(_village_frame)
	var keys := ["built", "own_open", "own_take", "other_open", "hash_equal", "cross_loot"]
	var ok := _local_seen and lp != null
	for k in keys:
		if not bool(_checks.get(k, false)):
			ok = false
	_log("RESULT %s name=%s scenario=%s checks=%s plans=%s snapshots=%d events=%d rtt_max=%.0f" % ["OK" if ok else "FAIL", client_name,
		scenario, _checks, _hash, NetWorld.instance.snapshots_received if NetWorld.instance != null else -1,
		NetWorld.instance.events_received if NetWorld.instance != null else -1, _rtt_max])
	tree.quit(0 if ok else 1)
