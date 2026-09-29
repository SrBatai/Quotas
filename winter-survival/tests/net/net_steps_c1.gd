extends "res://tests/net/net_steps.gd"
## C1 net scenario `tower` (4 clients on 3 floors of a hero tower, the Edificio Meridiano of Las Torres):
##   * setup: A turns the director / residents off, clears the zombies, plants 10 frozen zombies on floor 5 and 10 on
##     floor 11 and goes to floor 2; B stands on floor 2, C on floor 3, D on floor 8. The clients join at different
##     times on a loaded machine: each says "listo X" once in place and A starts every phase with a chat line
##     ("fase off", "fase on", "fase puertas") so the measurement windows are the same for everybody;
##   * the vertical interest filter (ZombieNet: a zombie inside a building more than 9 m above or below the player is
##     not sent): the zombie bytes each client receives are measured with the filter OFF (`/rule vertical_filter
##     off`) and ON; every client must see a cut ≥ 30 % (A, B: both groups are 11+ m away; C: floor 5 is 7.6 m
##     above it, so it keeps that one; D: floors 5 and 11 are 11.4 m away);
##   * doors: A opens the stair door of floor 2, C the one of floor 3; every client checks both on its own copy of
##     the tower (the same wids everywhere, the chunk delta);
##   * containers: C opens the desk container of floor 3 nearest to the landing, takes its first stack and announces
##     what is left in the chat; D goes down to floor 3, opens the same container and must find exactly that.
## Everybody stays until everybody said "hecho X".

const HERO := 902

var _checks: Dictionary = {}
var _facts: Dictionary = {}
var _started: bool = false
var _loot_wid: int = 0
var _announced: String = ""
var _bytes_off: float = -1.0
var _bytes_on: float = -1.0
var _ready: Dictionary = {}       # names in place ("listo X")
var _done: Dictionary = {}        # names finished ("hecho X")
var _phase: String = ""           # the phase A announced ("fase off" | "fase on" | "fase puertas")


func _run_client() -> void:
	super._run_client()
	_timeline = []
	tree.process_frame.connect(_tower_frame)
	Events.chat_message.connect(func(who: String, text: String) -> void:
		if text.begins_with("botin "):
			var parts := text.split(" ", false, 2)
			_loot_wid = parts[1].hex_to_int()
			_announced = parts[2] if parts.size() > 2 else ""
			_log("%s announced the container %s: %s" % [who, parts[1], _announced])
		elif text.begins_with("listo ") or text.begins_with("hecho "):
			(_ready if text.begins_with("listo ") else _done)[text.substr(6)] = true
		elif text.begins_with("fase "):
			_phase = text.substr(5)
			_log("phase %s" % _phase))


func _hero() -> HeroTower:
	for n in tree.get_nodes_in_group("hero_tower"):
		if (n as HeroTower).hero_id == HERO:
			return n as HeroTower
	return null


func _sleep(s: float) -> void:
	await tree.create_timer(s).timeout


## Waits until `cond` holds (polled every 0.25 s), at most `timeout` s; returns whether it held.
func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not bool(cond.call()) and t < timeout:
		await _sleep(0.25)
		t += 0.25
	return bool(cond.call())


func _say(text: String) -> void:
	Chat.instance.send(text)


## The server takes 2 chat lines per second per player and drops a third inside the same second (it did: "listo A",
## "/rule …" and "fase off" went out within ~1 s and the phase never came): A sends each phase again until it hears
## its own announcement back.
func _announce(phase: String) -> void:
	for attempt in 5:
		_say("fase %s" % phase)
		if await _until(func() -> bool: return _phase == phase, 2.5):
			return
		_log("phase %s not heard back: sending it again" % phase)


func _tp_floor(k: int, local: Vector3) -> void:
	var ht := _hero()
	if ht == null:
		_log("no tower to teleport into")
		return
	var p := ht.global_transform * Vector3(local.x, 0.0, local.z)
	_say("/tp %.2f %.2f %.2f" % [p.x, p.z, ht.floor_y(k)])


func _landing(k: int, side: float = 0.0) -> void:
	var ht := _hero()
	if ht == null:
		return
	var lp := ht.global_transform.affine_inverse() * ht.landing_point(k, 2.0)
	_tp_floor(k, lp + Vector3(side, 0.0, 0.0))


## The stair door of floor k on this peer's copy of the tower (the KitDoor nearest to that floor's landing).
func _stair_door(k: int) -> KitDoor:
	var ht := _hero()
	if ht == null:
		return null
	var at := ht.landing_point(k, 0.0)
	var best: KitDoor = null
	var bd := 3.0
	for d in ht.doors:
		var p := d.global_position
		var dd := Vector2(p.x - at.x, p.z - at.z).length()
		var leaf_floor := int((d.leaf.get_meta("extras", {}) as Dictionary).get("floor", -1))
		if leaf_floor == k and dd < bd:
			bd = dd
			best = d
	return best


func _door_state(k: int) -> String:
	var d := _stair_door(k)
	if d == null:
		return "none"
	return "open" if d.is_open else "closed"


func _use_door(k: int) -> void:
	var d := _stair_door(k)
	if d == null:
		_log("stair door of floor %d not built here" % k)
		return
	var wid := WorldRegistry.wid_of(d)
	_log("request use on stair door %x of floor %d (open=%s)" % [wid, k, d.is_open])
	Net.rpc_server(NetWorld.instance, &"request_interact", [wid, &"use", 0])


func _zbytes() -> int:
	return ZombieClient.instance.bytes_in if ZombieClient.instance != null else 0


## Zombie kB/s received over `secs` seconds.
func _measure(secs: float) -> float:
	var b0 := _zbytes()
	await _sleep(secs)
	return float(_zbytes() - b0) / secs / 1000.0


func _tower_frame() -> void:
	if _started or GameFlow.local_player() == null or _connect_time < 0.0:
		return
	_started = true
	_script()


## The clients join at different times (a loaded machine): every phase starts on a chat message of A once all four
## are in place ("listo X"), so the filter OFF / ON windows are the same for everybody.
func _script() -> void:
	var lp := GameFlow.local_player()
	var ht_pos := CityLots.v2(CityLots.hero(HERO)["pos"])
	_tp(Vector3(ht_pos.x, 0.0, ht_pos.y + 16.0))
	_checks["tower"] = await _until(func() -> bool: return _hero() != null, 60.0)
	_log("tower %s" % ("built" if _hero() != null else "MISSING"))
	await _sleep(1.0)
	match client_name:
		"A":
			# the stage: no director (no residents either), no zombies, noon; 10 frozen zombies on floor 5 and 10 on
			# floor 11 (they keep their floor: a wandering L1 walker could leave the footprint and drop to the street;
			# a frozen record is still sent once a second, the keyframe)
			_say("/director off")
			await _sleep(0.6)
			_say("/zombies clear")
			await _sleep(0.6)
			_say("/hora 12")
			await _sleep(0.6)
			_tp_floor(5, Vector3(12.0, 0.0, 5.0))
			await _sleep(2.0)
			_say("/zombies 10 frozen 4")
			await _sleep(1.0)
			_tp_floor(11, Vector3(12.0, 0.0, 5.0))
			await _sleep(2.0)
			_say("/zombies 10 frozen 4")
			await _sleep(1.0)
			_landing(2, -1.0)
		"B":
			_landing(2, 1.5)
		"C":
			_landing(3)
		_:
			_landing(8)
	await _sleep(2.0)
	_ready[client_name] = true
	_say("listo %s" % client_name)
	if client_name == "A":
		var all := await _until(func() -> bool: return _ready.size() >= int(opts["clients"]), 150.0)
		_log("%s: %s" % ["everybody in place" if all else "NOT everybody in place", _ready.keys()])
		await _sleep(1.2)
		_say("/rule vertical_filter off")
		await _sleep(1.2)
		await _announce("off")
	# phase OFF
	await _until(func() -> bool: return _phase == "off", 200.0)
	await _sleep(3.0)
	_bytes_off = await _measure(14.0)
	if client_name == "A":
		await _sleep(3.0)
		_say("/rule vertical_filter on")
		await _sleep(1.2)
		await _announce("on")
	# phase ON
	await _until(func() -> bool: return _phase == "on", 60.0)
	await _sleep(3.0)
	_bytes_on = await _measure(14.0)
	var cut := 1.0 - _bytes_on / maxf(_bytes_off, 0.001)
	_checks["filter_cut"] = _bytes_off > 0.05 and cut >= 0.30
	_log("zombie downstream: filter off %.2f kB/s, on %.2f kB/s: cut %.0f %% (floor %d)" % [_bytes_off, _bytes_on, cut * 100.0,
		_hero().floor_at_y(lp.global_position.y) if _hero() != null else -1])
	if client_name == "A":
		await _sleep(3.0)
		await _announce("puertas")
	# doors and the container
	await _until(func() -> bool: return _phase == "puertas", 60.0)
	match client_name:
		"A":
			await _sleep(1.0)
			_use_door(2)
		"C":
			await _sleep(2.0)
			_use_door(3)
			await _sleep(2.0)
			await _loot_c()
		"D":
			await _check_loot()
	_checks["door_f2"] = await _until(func() -> bool: return _door_state(2) == "open", 30.0)
	_checks["door_f3"] = await _until(func() -> bool: return _door_state(3) == "open", 30.0)
	_log("doors: floor 2 %s, floor 3 %s" % [_door_state(2), _door_state(3)])
	# everybody stays until everybody is done (the doors / the container are checked with all four in the tower)
	_done[client_name] = true
	_say("hecho %s" % client_name)
	await _until(func() -> bool: return _done.size() >= int(opts["clients"]), 90.0)
	_finish(lp)


## C: opens the desk container of floor 3 nearest to the landing, takes the first stack, announces what is left.
func _loot_c() -> void:
	var lc := _nearest_loot_on(3)
	if lc == null:
		_log("no container on floor 3")
		return
	_loot_wid = WorldRegistry.wid_of(lc)
	_checks["loot_open"] = await _open_container(lc)
	_log("C: the container %x holds %s" % [_loot_wid, _items(lc.storage)])
	for i in lc.storage.slots.size():
		if not lc.storage.slots[i].is_empty():
			Net.rpc_server(NetWorld.instance, &"request_take", [_loot_wid, i, true])
			break
	await _sleep(2.0)
	var left := _items(lc.storage)
	Net.rpc_server(NetWorld.instance, &"request_close_storage", [_loot_wid])
	_say("botin %x %s" % [_loot_wid, ",".join(left) if not left.is_empty() else "vacio"])


## D: goes down to floor 3, opens the container C announced and must find what C left.
func _check_loot() -> void:
	await _until(func() -> bool: return _announced != "", 60.0)
	var lc := WorldRegistry.get_object(_loot_wid) as LootContainer
	if lc == null:
		_log("the announced container is not built here")
		return
	await _open_container(lc)
	await _sleep(1.0)
	var now := _items(lc.storage)
	var saw := ",".join(now) if not now.is_empty() else "vacio"
	_checks["loot_same"] = lc.storage.is_open and saw == _announced
	_log("D: the container %x holds %s (C left %s)" % [_loot_wid, saw, _announced])
	Net.rpc_server(NetWorld.instance, &"request_close_storage", [_loot_wid])


## Teleports in front of the container (floor 3), waits to be there, then asks to open it until it opens (a loaded
## machine: the teleport and the answer can take seconds).
func _open_container(lc: LootContainer) -> bool:
	var front := lc.global_position + lc.global_basis.z * 1.0
	_say("/tp %.2f %.2f %.2f" % [front.x, front.z, _hero().floor_y(3)])
	await _until(func() -> bool: return GameFlow.local_player().global_position.distance_to(front) < 1.5, 20.0)
	await _sleep(0.5)
	var t := 0.0
	while not lc.storage.is_open and t < 30.0:
		GameFlow.local_player().interactor.send_interact(lc.interactable, &"open")
		await _until(func() -> bool: return lc.storage.is_open, 4.0)
		t += 4.0
	_log("%s: container %x open=%s at %.1f m" % [client_name, WorldRegistry.wid_of(lc), lc.storage.is_open,
		GameFlow.local_player().global_position.distance_to(lc.global_position)])
	return lc.storage.is_open


func _nearest_loot_on(k: int) -> LootContainer:
	var ht := _hero()
	if ht == null:
		return null
	var at := ht.landing_point(k, 2.0)
	var best: LootContainer = null
	var bd := INF
	for n in tree.get_nodes_in_group("loot_container"):
		var lc := n as LootContainer
		if lc == null or lc.loose or absf(lc.global_position.y - ht.floor_y(k)) > 1.0:
			continue
		var d := lc.global_position.distance_to(at)
		if d < bd:
			bd = d
			best = lc
	return best


func _items(st: Storage) -> Array:
	var out := []
	for sl in st.slots:
		if not sl.is_empty():
			out.append("%s×%d" % [sl["id"], int(sl["count"])])
	out.sort()
	return out


func _finish(lp: Player) -> void:
	tree.process_frame.disconnect(_client_frame)
	if tree.process_frame.is_connected(_tower_frame):
		tree.process_frame.disconnect(_tower_frame)
	var keys: Array = ["tower", "filter_cut", "door_f2", "door_f3"]
	if client_name == "C":
		keys.append("loot_open")
	if client_name == "D":
		keys.append("loot_same")
	var ok := _local_seen and lp != null
	for k in keys:
		if not bool(_checks.get(k, false)):
			ok = false
	_log("RESULT %s name=%s scenario=%s checks=%s zombie_kbps_off=%.2f zombie_kbps_on=%.2f loot=%x rtt_max=%.0f" % ["OK" if ok else "FAIL", client_name,
		scenario, _checks, _bytes_off, _bytes_on, _loot_wid, _rtt_max])
	tree.quit(0 if ok else 1)
