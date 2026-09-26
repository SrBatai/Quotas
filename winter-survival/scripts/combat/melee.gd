class_name Melee
## Server-side melee validation and resolution (ARQ v2 §6.8 / §11, GDD v2 §7.1 / §7.5 / §7.6). A request carries
## the attack mode, the yaw the owner was facing and the net id it aimed at (0 = none). The server checks the
## attacker (alive, not downed, cadence, stamina), then looks for victims in a cone of Balance.MELEE_CONE_DEG
## around that yaw within the weapon reach + Balance.MELEE_REACH_TOLERANCE, testing each zombie both where it is now
## and where it was `rewind` seconds ago (hit history: ½ RTT + the 100 ms interpolation delay, ≤ MELEE_REWIND_MAX),
## so what the attacker saw is what it hits. Up to `targets` victims (nearest first); players too when the server
## rules allow it (DamageResolver decides the multiplier). Modes:
##   LIGHT    weapon damage, crit ×3 with the weapon's chance, knockdown chance of blunt weapons;
##   CHARGED  ×1.5 damage, +0.4 s wind-up, knockdown chance ×1.5, noise +4, 12 stamina (needs ≥ 20);
##   SHOVE    no damage: knockdown 35 %, else a stagger, 8 stamina;
##   STOMP    kills a knocked-down zombie at the feet (1 s, noise 6);
##   EXECUTE  knife only: kills a frozen or unaware zombie silently (1.5 s lock, no noise).
## Every swing makes noise (hit / miss radius of the weapon) through SoundEvents, wears the weapon and plays the
## swing on every client (Player.swing_seq).
## Timing (ASSET_SPEC v2 M4.3): the request is validated at once (cadence, stamina, the execution victim), the
## swing starts on every client, and the damage is evaluated `Weapons.hit_delay` s later — the clip's `hit_start`
## in data/anim_events.json (0.27 s one-handed, 0.36 s two-handed, 0.06 s after a charged release, shove 0.25,
## stomp 0.46, execution 0.7) — with the attacker's position at that moment and the request's yaw. `tick()` (called
## by NetWorld every physics tick on the server) resolves the due swings and sends the outcome to the attacker.

const MAX_RTT_S := 0.4

## Accepted swings waiting for their damage frame (server).
static var _pending: Array[Dictionary] = []


static func clear() -> void:
	_pending.clear()


## Validates one request and schedules its damage. Returns {ok, reason, hits, kills, mode, pending}: `pending` =
## the hits arrive later through NetWorld.send_melee_result; refusals and instant resolutions come back complete.
static func perform(player: Player, mode: int, yaw: float, aim_id: int) -> Dictionary:
	var out := {"ok": false, "reason": "", "hits": 0, "kills": 0, "mode": mode, "pending": false}
	var now := Time.get_ticks_msec() / 1000.0
	if player == null or player.dead or player.downed:
		out["reason"] = "muerto"
		return out
	if now < player.melee_ready_at:
		out["reason"] = "cadencia"
		return out
	var hand := player.state.hand_tool()
	var w := Weapons.of(hand)
	var sys := ZombieSystem.instance
	var stats := player.state.stats
	# stamina (GDD §5): light 8, charged 12 (needs 20), shove 8; stomp / execute are free
	match mode:
		Weapons.Mode.LIGHT:
			if not stats.spend_stamina(Balance.STAMINA_MELEE):
				out["reason"] = "aguante"
				return out
		Weapons.Mode.CHARGED:
			if not stats.spend_stamina(Balance.STAMINA_CHARGED, Balance.STAMINA_MIN_RUN):
				mode = Weapons.Mode.LIGHT
				if not stats.spend_stamina(Balance.STAMINA_MELEE):
					out["reason"] = "aguante"
					return out
		Weapons.Mode.SHOVE:
			if not stats.spend_stamina(Balance.STAMINA_SHOVE):
				out["reason"] = "aguante"
				return out
		Weapons.Mode.EXECUTE:
			if not Weapons.can_execute(hand):
				out["reason"] = "arma"
				return out
	out["mode"] = mode
	player.melee_ready_at = now + Weapons.cadence(hand, mode)
	yaw = wrapf(yaw, -PI, PI) if is_finite(yaw) else player.aim_yaw
	player.aim_yaw = yaw
	player.play_swing(Weapons.clip(hand, mode))
	var pin := -1
	if mode == Weapons.Mode.EXECUTE:
		# the victim must be unaware when the knife hand grabs it; it is held still until the stab
		pin = _execute_target(player, yaw, aim_id)
		if pin >= 0 and sys != null:
			sys.hold(pin, Weapons.hit_delay(hand, mode) + 0.2)
	var delay := Weapons.hit_delay(hand, mode)
	if delay <= 0.0 or (mode == Weapons.Mode.EXECUTE and pin < 0):
		return resolve(player, mode, yaw, aim_id, hand, pin)
	_pending.append({"due": now + delay, "player": player, "mode": mode, "yaw": yaw, "aim": aim_id, "hand": hand, "pin": pin,
		"id": sys.net_id[pin] if pin >= 0 else 0})
	out["ok"] = true
	out["pending"] = true
	return out


## Server, every physics tick: resolves the swings whose damage frame has come.
static func tick() -> void:
	if _pending.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var due: Array[Dictionary] = []
	for e in _pending:
		if now >= float(e["due"]):
			due.append(e)
	for e in due:
		_pending.erase(e)
		var player := e["player"] as Player
		if not is_instance_valid(player) or player.dead or player.downed or player.disconnected:
			continue
		var pin := int(e["pin"])
		var sys := ZombieSystem.instance
		if pin >= 0 and (sys == null or sys.net_id[pin] != int(e["id"])):
			pin = -1   # the held victim went away (despawn): the stab finds nothing
		var res := resolve(player, int(e["mode"]), float(e["yaw"]), int(e["aim"]), StringName(e["hand"]), pin)
		if NetWorld.instance != null:
			NetWorld.instance.send_melee_result(player.peer_id, res)


## The unaware zombie a knife execution grabs (in reach and in the cone, the aimed one first), or -1.
static func _execute_target(player: Player, yaw: float, aim_id: int) -> int:
	var sys := ZombieSystem.instance
	if sys == null:
		return -1
	for c in _candidates(player, Weapons.Mode.EXECUTE, yaw, aim_id, Balance.EXECUTE_RANGE + Balance.MELEE_REACH_TOLERANCE):
		var i := int(c[1])
		if sys.is_unaware(i, player.peer_id):
			return i
	return -1


## Zombies in the cone within `reach`, now or `rewind` s ago (the aimed one first on ties): [[dist, slot], …].
static func _candidates(player: Player, _mode: int, yaw: float, aim_id: int, reach: float) -> Array:
	var sys := ZombieSystem.instance
	var cands: Array = []
	if sys == null:
		return cands
	var origin := player.global_position
	var fwd := Vector2(sin(yaw), cos(yaw))
	var half := deg_to_rad(Balance.MELEE_CONE_DEG * 0.5)
	var rewind := clampf(_rtt(player.peer_id) * 0.5 + Balance.NET_INTERP_DELAY, 0.0, Balance.MELEE_REWIND_MAX)
	for i in sys.near_any(origin, reach + 2.0):
		if not sys.is_alive(i):
			continue
		var best := INF
		for q in [sys.pos[i], sys.pos_ago(i, rewind)]:
			var dv := Vector2(q.x - origin.x, q.z - origin.z)
			var d := dv.length()
			if d <= reach and (d < 0.6 or absf(fwd.angle_to(dv)) <= half):
				best = minf(best, d)
		if best < INF:
			cands.append([best - (0.5 if sys.net_id[i] == aim_id else 0.0), i])
	cands.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	return cands


## The damage frame of an accepted swing: victims in the cone, damage, noise, wear. `pin` = the execution victim
## held since the request (-1 none).
static func resolve(player: Player, mode: int, yaw: float, aim_id: int, hand: StringName, pin: int) -> Dictionary:
	var out := {"ok": true, "reason": "", "hits": 0, "kills": 0, "mode": mode, "pending": false}
	var now := Time.get_ticks_msec() / 1000.0
	var w := Weapons.of(hand)
	var sys := ZombieSystem.instance
	var origin := player.global_position
	var fwd := Vector2(sin(yaw), cos(yaw))
	var reach := float(w["reach"])
	if mode == Weapons.Mode.SHOVE:
		reach = Balance.SHOVE_RANGE
	elif mode == Weapons.Mode.EXECUTE or mode == Weapons.Mode.STOMP:
		reach = Balance.EXECUTE_RANGE
	reach += Balance.MELEE_REACH_TOLERANCE
	var half := deg_to_rad(Balance.MELEE_CONE_DEG * 0.5)
	var cands: Array = [] if mode == Weapons.Mode.EXECUTE else _candidates(player, mode, yaw, aim_id, reach)
	var max_t := int(w["targets"])
	var hit_any := false
	match mode:
		Weapons.Mode.EXECUTE:
			if pin >= 0 and sys != null and sys.is_alive(pin):
				var dir := sys.pos[pin] - origin
				sys.execute(pin, player.peer_id, dir, true)
				player.melee_ready_at = maxf(player.melee_ready_at, now + 0.3)
				out["hits"] = 1
				out["kills"] = 1
				hit_any = true
				print("[EVT] player %d executes zombie %d silently" % [player.peer_id, sys.net_id[pin]])
			else:
				out["reason"] = "no_objetivo"
		Weapons.Mode.STOMP:
			for c in cands:
				var i := int(c[1])
				if sys.state[i] == ZombieKinds.State.KNOCKED or sys.kind[i] == ZombieKinds.Kind.CRAWLER:
					sys.execute(i, player.peer_id, sys.pos[i] - origin, false, true)   # the heel crushes the skull
					out["hits"] = 1
					out["kills"] = 1
					hit_any = true
					break
			SoundEvents.emit(origin, Balance.STOMP_NOISE, 1, SoundEvents.Kind.SHOVE, player.peer_id, player.in_house)
		Weapons.Mode.SHOVE:
			var n := 0
			for c in cands:
				if n >= 2:
					break
				var i := int(c[1])
				var dir := sys.pos[i] - origin
				if sys.rng.randf() < Balance.SHOVE_KNOCKDOWN:
					sys.knock(i, dir)
				else:
					sys.stagger(i, dir)
				n += 1
			out["hits"] = n
			hit_any = n > 0
			SoundEvents.emit(origin, Balance.SHOVE_NOISE, 1, SoundEvents.Kind.SHOVE, player.peer_id, player.in_house)
		_:
			var charged := mode == Weapons.Mode.CHARGED
			var n := 0
			for c in cands:
				if n >= max_t:
					break
				var i := int(c[1])
				var res := _hit_zombie(player, i, w, charged)
				n += 1
				if bool(res["killed"]):
					out["kills"] = int(out["kills"]) + 1
			# players (pvp / friendly fire: DamageResolver decides; off = the swing passes through)
			if n < max_t:
				n += _hit_players(player, w, charged, origin, fwd, reach, half, max_t - n)
			out["hits"] = n
			hit_any = n > 0
			# GDD §6.3: hit 10 (bat, axe) / knife 3 / miss 8 (the knife stays quiet either way)
			var noise := float(w["noise"])
			if not hit_any and hand != &"cuchillo":
				noise = Balance.MELEE_MISS_NOISE
			if charged:
				noise += Balance.MELEE_CHARGED_NOISE
			SoundEvents.emit(origin, noise, 1, SoundEvents.Kind.MELEE if hit_any else SoundEvents.Kind.MISS, player.peer_id, player.in_house)
	if hit_any and mode != Weapons.Mode.SHOVE:
		player.state.inventory.wear_hand(sys.rng if sys != null else RandomNumberGenerator.new())
	return out


static func _hit_zombie(player: Player, i: int, w: Dictionary, charged: bool) -> Dictionary:
	var sys := ZombieSystem.instance
	var dmg := float(w["dmg"])
	var crit := sys.rng.randf() < float(w["crit"])
	if charged:
		dmg *= Balance.MELEE_CHARGED_MULT
	var knock := float(w.get("knock", 0.0)) * (1.5 if charged else 1.0)
	var res := DamageResolver.apply(DamageResolver.ref(DamageResolver.Kind.PLAYER, player.peer_id),
		DamageResolver.ref(DamageResolver.Kind.ZOMBIE, sys.net_id[i]), null, dmg, int(w["kind"]), WorldState.rules_now(),
		player, {"slot": i, "crit": crit, "knock": knock, "dir": sys.pos[i] - player.global_position,
		"gore": w.get("model", "") != "knife"})
	return res


static func _hit_players(player: Player, w: Dictionary, charged: bool, origin: Vector3, fwd: Vector2, reach: float, half: float, max_n: int) -> int:
	var world := player.get_tree().get_first_node_in_group("world") as World
	if world == null:
		return 0
	var n := 0
	for c in world.get_node("Players").get_children():
		if n >= max_n:
			break
		var v := c as Player
		if v == null or v == player or v.dead or v.disconnected:
			continue
		var dv := Vector2(v.global_position.x - origin.x, v.global_position.z - origin.z)
		if dv.length() > reach or (dv.length() > 0.6 and absf(fwd.angle_to(dv)) > half):
			continue
		var a_ref := DamageResolver.ref(DamageResolver.Kind.PLAYER, player.peer_id)
		var v_ref := DamageResolver.ref(DamageResolver.Kind.PLAYER, v.peer_id)
		var dmg := float(w["dmg"]) * (Balance.MELEE_CHARGED_MULT if charged else 1.0)
		var res := DamageResolver.apply(a_ref, v_ref, v, dmg, int(w["kind"]), WorldState.rules_now(), player)
		print("[EVT] melee %d -> player %d dmg=%.0f -> %s" % [player.peer_id, v.peer_id, dmg,
			"BLOCKED (%s)" % res["reason"] if res["blocked"] else "applied %.0f" % res["applied"]])
		if not bool(res["blocked"]):
			n += 1
		Net.rpc_to(NetWorld.instance, &"hit_result", player.peer_id, [v.peer_id, bool(res["blocked"]), str(res["reason"])])
	return n


## Round-trip time to a peer in seconds (0 for the local / offline player).
static func _rtt(peer: int) -> float:
	if Net.enet == null or peer == Net.local_peer_id() or not Net.multiplayer.get_peers().has(peer):
		return 0.0
	var pp := Net.enet.get_peer(peer)
	if pp == null:
		return 0.0
	return clampf(float(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) / 1000.0, 0.0, MAX_RTT_S)
