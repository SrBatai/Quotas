extends "res://tests/net/net_steps.gd"
## M6a net scenario `street` (3 clients; C joins 34 s late): the kit doors of the test street are server-authoritative
## and replicated through the chunk delta. Every step waits for the state it needs (the server may run slow on a
## shared machine) instead of a fixed time:
##   A  teleports onto the porch of the north 2-storey house of the Calle Mayor (Santa María del Puerto) and opens its
##      front door (NetWorld.request_interact(wid, &"use")); once it sees B's close arrive, opens it again;
##   B  teleports onto the street, sees A's door open (live event), steps onto the porch and closes it (request
##      `close`); then sees A's reopen;
##   C  joins late, teleports to the street: the door on its fresh copy of the street is OPEN from the start (the chunk
##      delta snapshot of the door's chunk; the door node reads NetWorld.delta_of(wid) when it is built).
## Every client checks the door on its own copy of the street (same wid on every peer, nothing spawned by the net).

const STREET := "calle_mayor"
const WAIT := 30.0

var _checks: Dictionary = {}
var _door_wid: int = 0
var _started: bool = false


func _run_client() -> void:
	super._run_client()
	_timeline = []
	tree.process_frame.connect(_street_frame)


## The front door (S facade) of the north 2-storey house, on this peer's copy of the street.
func _front_door() -> KitDoor:
	var st := KitStreets.street(STREET)
	if st == null or not st.done:
		return null
	for b in st.buildings:
		if b.template_id == "house_two_story_A" and b.style == "wood_blue":
			for d in b.doors:
				if d.exterior and str((d.leaf.get_meta("extras", {}) as Dictionary).get("cut_group", "")) == "Walls0_S":
					return d
	return null


## World point `ahead` m in front of that door (on the porch), from the street data (no node needed).
func _porch_spot(ahead: float) -> Vector3:
	var c := KitStreets.centre_of(KitStreets.by_id(STREET))
	# the house: lot (4, -13.7), yaw 0; its front door: cell 1 of the S facade (x = -1 local), leaf at z +5.0
	return c + Vector3(4.0 - 1.0, 0.0, -13.7 + 5.0 + ahead)


func _use_door(action: StringName) -> void:
	var d := _front_door()
	if d == null:
		_log("door not built here yet")
		return
	_door_wid = WorldRegistry.wid_of(d)
	_log("request %s on door %x (open=%s)" % [action, _door_wid, d.is_open])
	Net.rpc_server(NetWorld.instance, &"request_interact", [_door_wid, action, 0])


func _door_state() -> String:
	var d := _front_door()
	if d == null:
		return "none"
	return "open" if d.is_open else "closed"


func _sleep(s: float) -> void:
	await tree.create_timer(s).timeout


## Polls until the door reads `want` (or the timeout). Returns true when it did.
func _wait_door(want: String, timeout: float = WAIT) -> bool:
	var t := 0.0
	while t < timeout:
		if _door_state() == want:
			return true
		await _sleep(0.25)
		t += 0.25
	return false


func _street_frame() -> void:
	if _started or GameFlow.local_player() == null or _connect_time < 0.0:
		return
	_started = true
	match client_name:
		"A":
			_script_a()
		"B":
			_script_b()
		_:
			_script_c()


func _quiet() -> void:
	await _sleep(1.0)
	Chat.instance.send("/director off")
	await _sleep(0.8)
	Chat.instance.send("/zombies clear")


func _script_a() -> void:
	await _quiet()
	await _sleep(0.8)
	_tp(_porch_spot(0.9))
	await _wait_door("closed")                 # the street is built on this client
	await _sleep(2.0)
	_use_door(&"use")
	_checks["a_open"] = await _wait_door("open")
	_log("A: door %s after its request" % _door_state())
	_checks["a_sees_b_close"] = await _wait_door("closed", 45.0)
	_log("A: door %s (B closed it)" % _door_state())
	await _sleep(1.0)
	_use_door(&"open")
	_checks["a_reopen"] = await _wait_door("open")
	await _sleep(1.0)
	var d := _front_door()
	_checks["leaf_turned"] = d != null and absf(d.leaf.rotation.y) > deg_to_rad(80.0)
	_log("A: door %s again (leaf at %.0f deg)" % [_door_state(), rad_to_deg(d.leaf.rotation.y) if d else 0.0])
	Chat.instance.send("puerta abierta")


func _script_b() -> void:
	await _sleep(2.6)
	_tp(_porch_spot(6.0))
	_checks["b_sees_open"] = await _wait_door("open", 45.0)
	_log("B: door %s (A opened it)" % _door_state())
	_tp(_porch_spot(1.4))
	await _sleep(3.0)
	_use_door(&"close")
	_checks["b_closed"] = await _wait_door("closed")
	_log("B: door %s after its close" % _door_state())
	_checks["b_sees_reopen"] = await _wait_door("open", 45.0)
	_log("B: door %s (A reopened it)" % _door_state())


func _script_c() -> void:
	await _sleep(2.6)
	_tp(_porch_spot(6.0))
	var t := 0.0
	while _front_door() == null and t < WAIT:
		await _sleep(0.25)
		t += 0.25
	var d := _front_door()
	# the state it was BUILT with (from the snapshot delta), before any live event could have changed it
	_checks["late_open"] = d != null and d.is_open
	_checks["late_delta"] = d != null and bool(NetWorld.instance.delta_of(WorldRegistry.wid_of(d)).get("open", false))
	_checks["late_snapshot"] = d != null and NetWorld.instance.snapshot_keys.has(WorldConst.key_of(d.global_position))
	_door_wid = WorldRegistry.wid_of(d) if d != null else 0
	await _sleep(1.0)
	_checks["late_leaf"] = d != null and absf(d.leaf.rotation.y) > deg_to_rad(80.0)
	_log("C (late): door %s, delta %s, events %d" % [_door_state(), NetWorld.instance.delta_of(_door_wid) if d else {},
		NetWorld.instance.events_received])


func _finish(lp: Player) -> void:
	tree.process_frame.disconnect(_client_frame)
	if tree.process_frame.is_connected(_street_frame):
		tree.process_frame.disconnect(_street_frame)
	var keys: Array = {"A": ["a_open", "a_sees_b_close", "a_reopen", "leaf_turned"], "B": ["b_sees_open", "b_closed", "b_sees_reopen"],
		"C": ["late_open", "late_delta", "late_snapshot", "late_leaf"]}.get(client_name, [])
	var ok := _local_seen and lp != null
	for k in keys:
		if not bool(_checks.get(k, false)):
			ok = false
	_log("RESULT %s name=%s scenario=%s checks=%s door=%x snapshots=%d events=%d rtt_max=%.0f" % ["OK" if ok else "FAIL", client_name,
		scenario, _checks, _door_wid, NetWorld.instance.snapshots_received if NetWorld.instance != null else -1,
		NetWorld.instance.events_received if NetWorld.instance != null else -1, _rtt_max])
	tree.quit(0 if ok else 1)
