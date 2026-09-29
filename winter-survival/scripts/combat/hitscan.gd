class_name Hitscan
## Server hit test of one bullet / pellet (ARQ v2 §6.8, M5). The camera is high above a 2D battlefield, so a shot
## is a horizontal segment from the muzzle along `yaw`: it stops at the first world collider (a ray on the `world`
## layer at muzzle height: walls, trunks, rocks, rising ground) or at the weapon's max range, and the victims are
## the circles (Balance.GUN_HIT_RADIUS) the segment crosses before that point:
##   zombies  at their position `rewind` s ago (ZombieSystem.pos_ago, L0 ring; L1 records have no body: now),
##   players  at HitHistory.pos_ago (other players only; allies with friendly fire off do not stop the bullet),
##   animals  (wolves, deer: nodes, where they are now).
## Sorted by distance and cut to `pierce` victims. No physics rewind, no raycast per target: cheap and exact for
## what the player sees from above (GDD §7.1: no aiming by body part, a crit is a roll).

enum Victim { ZOMBIE, PLAYER, ANIMAL }

## Tests / stats.
static var traces: int = 0


## Returns {"end": Vector3, "dist": float, "wall": bool, "victims": [{kind, t, slot|node|player, pos}]}.
static func trace(world: World, shooter: Player, origin: Vector3, yaw: float, max_range: float, rewind: float, pierce: int,
		rules: Dictionary) -> Dictionary:
	traces += 1
	var dir2 := Vector2(sin(yaw), cos(yaw))
	var dir3 := Vector3(dir2.x, 0.0, dir2.y)
	var d_wall := max_range
	var wall := false
	if world != null and world.is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir3 * max_range, 1, [shooter.get_rid()] if shooter != null else [])
		var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			d_wall = Vector2(hit.position.x - origin.x, hit.position.z - origin.z).length()
			wall = true
	var cands: Array = []
	var o2 := Vector2(origin.x, origin.z)
	var r := Balance.GUN_HIT_RADIUS
	var now := Time.get_ticks_msec() / 1000.0
	# zombies (records: L0 with the rewound position, L1 where they are)
	var sys := ZombieSystem.instance
	if sys != null:
		var mid := origin + dir3 * (d_wall * 0.5)
		for i in sys.near_any(mid, d_wall * 0.5 + r + 1.0):
			if not sys.is_alive(i):
				continue
			var p := sys.pos_ago(i, rewind)
			var t := _t_on_segment(o2, dir2, Vector2(p.x, p.z), d_wall, r + (0.1 if sys.kind[i] == ZombieKinds.Kind.BLOATER else 0.0))
			if t >= 0.0:
				cands.append({"kind": Victim.ZOMBIE, "t": t, "slot": i, "id": sys.net_id[i], "pos": sys.pos[i]})
	# players (lag-compensated; friendly fire off = the bullet passes through allies)
	if world != null:
		for n in world.get_node("Players").get_children():
			var pl := n as Player
			if pl == null or pl == shooter or pl.dead or pl.disconnected:
				continue
			var p := HitHistory.pos_ago(pl, rewind, now)
			var t := _t_on_segment(o2, dir2, Vector2(p.x, p.z), d_wall, r)
			if t < 0.0:
				continue
			var mult := DamageResolver.player_vs_player_mult(rules, DamageResolver.ref(DamageResolver.Kind.PLAYER, shooter.peer_id if shooter != null else 0),
				DamageResolver.ref(DamageResolver.Kind.PLAYER, pl.peer_id), DamageResolver.DamageKind.BULLET)
			cands.append({"kind": Victim.PLAYER, "t": t, "player": pl, "pos": pl.global_position, "pass": mult <= 0.0})
		# animals (hunting: deer → meat / pelt; wolves)
		for group in ["deer", "wolves"]:
			for a in world.get_tree().get_nodes_in_group(group):
				var an := a as Node3D
				if an == null or (an.has_method("is_dead") and bool(an.call("is_dead"))):
					continue
				var p := an.global_position
				var t := _t_on_segment(o2, dir2, Vector2(p.x, p.z), d_wall, 0.55 if group == "deer" else 0.45)
				if t >= 0.0:
					cands.append({"kind": Victim.ANIMAL, "t": t, "node": an, "pos": p})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	var victims: Array = []
	var end_t := d_wall
	for c in cands:
		victims.append(c)
		if bool(c.get("pass", false)):
			continue   # an ally the bullet goes through (it is still reported: the reticle turns grey)
		if _solid_count(victims) >= pierce:
			end_t = float(c["t"])
			break
	var end := origin + dir3 * end_t
	return {"end": end, "dist": end_t, "wall": wall and end_t >= d_wall - 0.01, "victims": victims}


static func _solid_count(victims: Array) -> int:
	var n := 0
	for v in victims:
		if not bool((v as Dictionary).get("pass", false)):
			n += 1
	return n


## Distance along the segment [o, o + dir · len] where a circle (c, radius) is crossed first, or -1.
static func _t_on_segment(o: Vector2, dir: Vector2, c: Vector2, length: float, radius: float) -> float:
	var oc := c - o
	var t := oc.dot(dir)
	if t < -radius or t > length + radius:
		return -1.0
	var lateral := absf(oc.cross(dir))
	if lateral > radius:
		return -1.0
	var back := sqrt(maxf(radius * radius - lateral * lateral, 0.0))
	var t_in := t - back
	if t_in > length:
		return -1.0
	return maxf(t_in, 0.0)
