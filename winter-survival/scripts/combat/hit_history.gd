class_name HitHistory
## Lag-compensation history of the players (ARQ v2 §6.8, M5): the server records every player's position at
## 30 Hz for Balance.GUN_HISTORY (1 s = 30 samples, a ring per peer). A shot is tested against where the targets
## were `rewind` s ago (½ RTT + the shooter's interpolation delay, ≤ Balance.GUN_REWIND_MAX = 200 ms): what the
## shooter saw is what it hits. Zombies keep their own ring in ZombieSystem (`pos_ago`, same 1 s at 30 Hz); the
## physics server is never rewound, the test is a 2D segment against circles (Hitscan).

const RATE := 30.0

## peer -> {"pos": PackedVector3Array, "t": PackedFloat64Array, "head": int}
static var _rings: Dictionary = {}
static var _last_t: float = -1.0


static func size() -> int:
	return int(ceil(Balance.GUN_HISTORY * RATE))


static func clear() -> void:
	_rings.clear()
	_last_t = -1.0


static func forget(peer: int) -> void:
	_rings.erase(peer)


## Server, every physics tick: samples the players (Node3D bodies with a `peer_id`) at RATE Hz.
static func record(players: Array, now: float) -> void:
	if _last_t >= 0.0 and now - _last_t < 1.0 / RATE - 0.002:
		return
	_last_t = now
	var n := size()
	for p in players:
		var pl := p as Node3D
		if pl == null or not is_instance_valid(pl) or not pl.is_inside_tree() or pl.get("peer_id") == null:
			continue
		var peer := int(pl.get("peer_id"))
		var r: Dictionary = _rings.get(peer, {})
		if r.is_empty():
			var pos := PackedVector3Array()
			pos.resize(n)
			var ts := PackedFloat64Array()
			ts.resize(n)
			ts.fill(-1.0)
			r = {"pos": pos, "t": ts, "head": 0}
		var head := (int(r["head"]) + 1) % n
		var pa: PackedVector3Array = r["pos"]
		var ta: PackedFloat64Array = r["t"]
		pa[head] = pl.global_position
		ta[head] = now
		r["pos"] = pa        # packed arrays in a Dictionary are values: write them back
		r["t"] = ta
		r["head"] = head
		_rings[peer] = r


## Where `peer` was `ago` s before `now` (the newest sample not after that instant, linearly interpolated with the
## next one). The live position when there is no history (offline tests, a player that just joined).
static func pos_ago(p: Node3D, ago: float, now: float) -> Vector3:
	var peer := int(p.get("peer_id")) if p.get("peer_id") != null else -1
	if ago <= 0.0 or not _rings.has(peer):
		return p.global_position
	var r: Dictionary = _rings[peer]
	var pa: PackedVector3Array = r["pos"]
	var ta: PackedFloat64Array = r["t"]
	var n := pa.size()
	var want := now - ago
	var head := int(r["head"])
	var newer := -1
	for k in n:
		var idx := (head - k + n) % n
		var t := ta[idx]
		if t < 0.0:
			break
		if t <= want:
			if newer < 0:
				return pa[idx]
			var t1 := ta[newer]
			var f := clampf((want - t) / maxf(t1 - t, 0.001), 0.0, 1.0)
			return pa[idx].lerp(pa[newer], f)
		newer = idx
	return pa[newer] if newer >= 0 else p.global_position
