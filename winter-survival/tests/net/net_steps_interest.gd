extends "res://tests/net/net_steps.gd"
## Net scenario `interest` (2 clients; B joins 9 s late): replicated nodes that appear or move while a peer is OUT of
## their 3 × 3 chunk interest (ARQ v2 §6.5) must never make that peer log "Ignoring delta for non-authority or
## invalid synchronizer" (the runner fails on any ERROR:):
##   A  turns the director off, teleports 3 km away (2816, -1216) and waits;
##   B  joins while A is away (its body spawns in the clearing, outside A's interest), then teleports next to A and
##      back to the clearing three times (A gets B spawned / despawned on every jump), ends in the clearing and says
##      «listo»;
##   A  then sets the hour to 21:00: night → the WolfSpawner puts a wolf around one of the two players, outside the
##      other one's interest.
## Every step waits for the state it needs (the server may run slow on a shared machine).
##   tests/net/run_net_test.sh --clients 2 --duration 40 --soak 60 --scenario interest

const FAR := Vector3(2816.0, 0.0, -1216.0)
const CLEARING := Vector3(3.0, 0.0, 9.0)
const FLAPS := 3
const WAIT := 20.0

var _checks: Dictionary = {}
var _started: bool = false
var _ready_seen: bool = false
var _wolves_seen: int = 0


func _run_client() -> void:
	if client_name == "B":
		_late = 9.0
	super._run_client()
	_timeline = []
	tree.process_frame.connect(_interest_frame)
	Events.chat_message.connect(func(who: String, text: String) -> void:
		if who == "B" and text == "listo":
			_ready_seen = true)


func _interest_frame() -> void:
	if _started or GameFlow.local_player() == null or _connect_time < 0.0:
		return
	_started = true
	var asp := tree.current_scene.get_node_or_null("ActorSpawner") as MultiplayerSpawner
	if asp != null:
		asp.spawned.connect(func(n: Node) -> void:
			if n.is_in_group("wolves") or str(n.name).begins_with("wolf"):
				_wolves_seen += 1
				_log("wolf spawned here: %s" % n.name))
	if client_name == "A":
		_script_a()
	else:
		_script_b()


func _sleep(s: float) -> void:
	await tree.create_timer(s).timeout


## Polls until `cond` returns true (or the timeout). Returns true when it did.
func _wait_for(cond: Callable, timeout: float = WAIT) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await _sleep(0.25)
		t += 0.25
	return false


func _near(pos: Vector3, d: float = 30.0) -> bool:
	var lp: Player = GameFlow.local_player()
	return lp != null and Vector2(lp.global_position.x - pos.x, lp.global_position.z - pos.z).length() < d


func _script_a() -> void:
	await _sleep(1.0)
	Chat.instance.send("/director off")
	await _sleep(0.8)
	Chat.instance.send("/zombies clear")
	await _sleep(0.8)
	_tp(FAR)
	_checks["far"] = await _wait_for(func() -> bool: return _near(FAR))
	_log("A: at %s, waiting for B" % GameFlow.local_player().global_position.snapped(Vector3(0.1, 0.1, 0.1)))
	_checks["b_ready"] = await _wait_for(func() -> bool: return _ready_seen, 60.0)
	_checks["b_in_out"] = _remote_spawned >= FLAPS and _remote_despawned >= FLAPS
	_log("A: B came and went (spawned %d, despawned %d); night" % [_remote_spawned, _remote_despawned])
	Chat.instance.send("/hora 21")
	_checks["night"] = await _wait_for(func() -> bool: return WorldState.is_night_now())
	await _sleep(3.0)


func _script_b() -> void:
	await _sleep(1.5)
	for i in FLAPS:
		_tp(FAR + Vector3(3.0, 0.0, 2.0))
		await _wait_for(func() -> bool: return _near(FAR))
		await _sleep(0.8)
		_tp(CLEARING)
		await _wait_for(func() -> bool: return _near(CLEARING))
		await _sleep(0.8)
	_checks["flapped"] = _near(CLEARING)
	_log("B: %d jumps next to A and back, now in the clearing" % FLAPS)
	Chat.instance.send("listo")
	_checks["night"] = await _wait_for(func() -> bool: return WorldState.is_night_now())


func _finish(lp: Player) -> void:
	tree.process_frame.disconnect(_client_frame)
	if tree.process_frame.is_connected(_interest_frame):
		tree.process_frame.disconnect(_interest_frame)
	var keys: Array = {"A": ["far", "b_ready", "b_in_out", "night"], "B": ["flapped", "night"]}.get(client_name, [])
	var ok := _local_seen and lp != null
	for k in keys:
		if not bool(_checks.get(k, false)):
			ok = false
	_log("RESULT %s name=%s scenario=%s checks=%s remote_spawns=%d remote_despawns=%d wolves_here=%d rtt_max=%.0f" % [
		"OK" if ok else "FAIL", client_name, scenario, _checks, _remote_spawned, _remote_despawned, _wolves_seen, _rtt_max])
	tree.quit(0 if ok else 1)
