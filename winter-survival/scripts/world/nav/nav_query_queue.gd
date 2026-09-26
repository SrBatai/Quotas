class_name NavQueryQueue
extends RefCounted
## Path requests of the zombies (ARQ v2 §10.2): at most `per_tick` `NavigationServer3D.map_get_path` calls per
## physics tick, highest priority first (L0 chasers > L0 others > L1), one pending request per zombie. A recent
## route (≤ SHARE_SECONDS old) whose start is within Balance.NAV_SHARE_RADIUS of the requester and whose goal is
## within SHARE_GOAL of the requested one is reused as is: a group chasing the same player computes one route.

const SHARE_SECONDS := 1.0
const SHARE_GOAL := 2.0
const CACHE_SIZE := 24
## A* bounds: a chase never needs more (an unreachable goal — a survivor inside the cabin — would otherwise make the
## search flood every polygon of the map looking for the closest reachable point: 1.8 ms per query measured).
const MAX_POLYGONS := 1200
const MAX_DISTANCE := 90.0
## Main-thread budget per tick for the queries (µs); the rest waits for the next tick.
const BUDGET_USEC := 1500

var map: RID
var per_tick: int = Balance.NAV_QUERIES_PER_TICK
## Stats: queries run, shared, max per tick, µs max per tick.
var stats: Dictionary = {"queries": 0, "shared": 0, "max_per_tick": 0, "usec_max": 0, "usec_total": 0}

var _queue: Array = []           # [priority, slot, from, to]
var _params := NavigationPathQueryParameters3D.new()
var _result := NavigationPathQueryResult3D.new()
var _pending: Dictionary = {}    # slot -> true
var _cache: Array = []           # [t, from, to, path]


func request(slot: int, from: Vector3, to: Vector3, priority: int) -> bool:
	if _pending.has(slot):
		return false
	_pending[slot] = true
	_queue.append([priority, slot, from, to])
	return true


func cancel(slot: int) -> void:
	if not _pending.has(slot):
		return
	_pending.erase(slot)
	for i in _queue.size():
		if int(_queue[i][1]) == slot:
			_queue.remove_at(i)
			return


func pending() -> int:
	return _queue.size()


## Runs the queue for this tick; `deliver(slot, path: PackedVector3Array)` receives each result.
func process(deliver: Callable) -> int:
	if _queue.is_empty() or not map.is_valid():
		return 0
	var t0 := Time.get_ticks_usec()
	if _queue.size() > 1:
		_queue.sort_custom(func(a, b) -> bool: return int(a[0]) < int(b[0]))
	var now := Time.get_ticks_msec() / 1000.0
	var ran := 0
	while not _queue.is_empty() and ran < per_tick and (ran == 0 or Time.get_ticks_usec() - t0 < BUDGET_USEC):
		var q: Array = _queue.pop_front()
		var slot := int(q[1])
		_pending.erase(slot)
		var from: Vector3 = q[2]
		var to: Vector3 = q[3]
		var path := _shared(now, from, to)
		if path.is_empty():
			# a goal beyond the search bound (a survivor who teleported / ran far): route toward a waypoint on the
			# way (re-queried on arrival). A bounded search whose goal lies outside the bound makes Godot's
			# "most reachable polygon" fallback fail (engine ERROR) and return no route.
			var span := Vector2(to.x - from.x, to.z - from.z).length()
			if span > MAX_DISTANCE * 0.7:
				to = from.lerp(to, MAX_DISTANCE * 0.7 / span)
			_params.map = map
			_params.start_position = from
			_params.target_position = to
			_params.metadata_flags = 0
			_params.simplify_path = true
			_params.simplify_epsilon = 0.25
			_params.path_search_max_polygons = MAX_POLYGONS
			_params.path_search_max_distance = MAX_DISTANCE
			NavigationServer3D.query_path(_params, _result)
			path = _result.path
			ran += 1
			stats["queries"] = int(stats["queries"]) + 1
			_cache.append([now, from, to, path])
			if _cache.size() > CACHE_SIZE:
				_cache.pop_front()
		else:
			stats["shared"] = int(stats["shared"]) + 1
		deliver.call(slot, path)
	var us := Time.get_ticks_usec() - t0
	stats["usec_total"] = int(stats["usec_total"]) + us
	stats["usec_max"] = maxi(int(stats["usec_max"]), us)
	stats["max_per_tick"] = maxi(int(stats["max_per_tick"]), ran)
	return ran


func _shared(now: float, from: Vector3, to: Vector3) -> PackedVector3Array:
	for i in range(_cache.size() - 1, -1, -1):
		var c: Array = _cache[i]
		if now - float(c[0]) > SHARE_SECONDS:
			break
		if (c[1] as Vector3).distance_to(from) <= Balance.NAV_SHARE_RADIUS and (c[2] as Vector3).distance_to(to) <= SHARE_GOAL:
			var p: PackedVector3Array = c[3]
			if p.size() >= 2:
				return p
	return PackedVector3Array()


func clear() -> void:
	_queue.clear()
	_pending.clear()
	_cache.clear()
