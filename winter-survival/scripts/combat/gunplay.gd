class_name Gunplay
## Server-side firearms (ARQ v2 §6.8, §11.3; GDD v2 §7.1–§7.6; M5). The owner client asks through NetWorld
## (`request_fire`, `request_reload`, `request_throw`); everything is decided here:
##   fire    alive (downed: pistol class only, GDD §12.2), a firearm in hand, not jammed / unjamming, cadence, rounds
##           in the magazine (the HAND slot's "ammo"; the bow takes an arrow from the inventory), cold / wear jam roll,
##           then one Hitscan per bullet / pellet with lag compensation (rewind = ½ RTT + the shooter's view delay,
##           ≤ Balance.GUN_REWIND_MAX) and a seeded spread (Firearms.shot_yaws: reproducible from the shot's seed),
##           damage through DamageResolver (crit roll, falloff, pierce, shotgun knockdown), recoil into the spread,
##           noise (SoundEvents: the zombies hear it, every client in reach sees the ring), durability, the shot event
##           for every client that can see or hear it and the result for the shooter.
##   reload  magazine weapons refill from the ammo items at once when the clip's `mag_in` (data/anim_events.json)
##           comes; the shotgun loads one shell per 0.7 s and a shot interrupts it; R on a jammed gun clears it (1.5 s).
##   tick    spread toward the posture target (Firearms.step_spread), reload / unjam timers, hit history sampling.
## The bow shoots a server-simulated arrow (Projectiles); throwables (can, flare) too.

## Tests / stats.
static var fired: int = 0
static var dry: int = 0
static var jams: int = 0
static var last_rewind: float = 0.0
static var last_shot: Dictionary = {}


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


static func _world(p: Player) -> World:
	return p.get_tree().get_first_node_in_group("world") as World if p != null and p.is_inside_tree() else null


## Rounds in the hand weapon's magazine (-1 without a firearm).
static func ammo_in(p: Player) -> int:
	var slots := p.state.slots
	if slots.is_empty() or slots[0].is_empty() or not Firearms.is_firearm(slots[0]["id"]):
		return -1
	if Firearms.is_bow(slots[0]["id"]):
		return 1 if p.state.count(&"flechas") > 0 else 0
	return int(slots[0].get("ammo", 0))


static func _set_ammo(p: Player, n: int) -> void:
	if not p.state.slots[0].is_empty():
		p.state.slots[0]["ammo"] = n


## Rounds of the hand weapon's ammo type in the inventory.
static func reserve(p: Player) -> int:
	var id := p.state.hand_tool()
	if not Firearms.is_firearm(id):
		return 0
	return p.state.count(Firearms.ammo_of(id))


## Cold jams (GDD §7.3: below −15 °C without gun oil): outdoors at night (−18 °C, the HUD's model until M8).
static func is_cold_for_guns(p: Player) -> bool:
	return not p.in_house and WorldState.is_night_now()


# ------------------------------------------------------------------ tick
static func tick(players: Array, dt: float) -> void:
	var now := _now()
	HitHistory.record(players, now)
	for n in players:
		var p := n as Player
		if p == null or p.disconnected or p.state.gun == null:
			continue
		var ws: WeaponState = p.state.gun
		var hand := p.state.hand_tool()
		if not Firearms.is_firearm(hand) or p.dead:
			if ws.weapon != &"":
				ws.reset(&"")
				p.state.mark(&"gun")
			continue
		if ws.weapon != hand:
			ws.reset(hand)
			p.state.mark(&"gun")
		var v := Vector2(p.velocity.x, p.velocity.z).length()
		ws.spread = Firearms.step_spread(ws.spread, Firearms.target_spread(hand, v, p.running, p.crouching, p.state.warmth), dt)
		if ws.reload_until >= 0.0 and now >= ws.reload_until:
			_finish_reload(p, ws, now)
		if ws.unjam_until >= 0.0 and now >= ws.unjam_until:
			ws.jammed = false
			ws.unjam_until = -1.0
			p.state.mark(&"gun")
			p.state.notify("Arma destrabada", 1.5)


# ------------------------------------------------------------------ reload / unjam
## Starts a reload (or clears a jam). Returns "" when accepted, else the reason.
static func start_reload(p: Player) -> String:
	if p == null or p.dead:
		return "muerto"
	var hand := p.state.hand_tool()
	if not Firearms.is_firearm(hand) or Firearms.is_bow(hand):
		return "arma"
	var ws: WeaponState = p.state.gun
	if ws.weapon != hand:
		ws.reset(hand)
	var now := _now()
	if ws.jammed:
		if ws.unjam_until < 0.0:
			ws.unjam_until = now + Firearms.unjam_time()
			p.play_swing(&"Act_Unjam")
			p.state.mark(&"gun")
		return ""
	if ws.reload_until >= 0.0:
		return "recargando"
	var f := Firearms.of(hand)
	if ammo_in(p) >= int(f["mag"]):
		return "lleno"
	if reserve(p) <= 0:
		p.state.notify("Sin %s" % Items.display_name(Firearms.ammo_of(hand)).to_lower(), 1.5)
		return "sin_municion"
	var t := Firearms.reload_time(hand)
	ws.reload_until = now + t
	ws.reload_total = t
	p.play_swing(Firearms.clip(hand, &"reload"))
	p.state.mark(&"gun")
	AudioManager.play(StringName("reload_%s" % String(f["class"]).to_lower()), p.global_position)
	return ""


## Shove / dodge / weapon change: the reload in progress stops (rounds already loaded stay).
static func cancel_reload(p: Player) -> void:
	if p == null or p.state.gun == null:
		return
	var ws: WeaponState = p.state.gun
	if ws.reload_until >= 0.0:
		ws.reload_until = -1.0
		p.state.mark(&"gun")


static func _finish_reload(p: Player, ws: WeaponState, now: float) -> void:
	var hand := ws.weapon
	var f := Firearms.of(hand)
	var ammo_id := StringName(f["ammo"])
	var loaded := ammo_in(p)
	var mag := int(f["mag"])
	var res := p.state.count(ammo_id)
	if bool(f["per_shell"]):
		if loaded < mag and res > 0:
			p.state.inventory.remove(ammo_id, 1)
			loaded += 1
			res -= 1
		if loaded < mag and res > 0:
			ws.reload_until = now + Firearms.reload_time(hand)   # next shell
			p.play_swing(Firearms.clip(hand, &"reload"))
		else:
			ws.reload_until = -1.0
	else:
		var n := mini(mag - loaded, res)
		if n > 0:
			p.state.inventory.remove(ammo_id, n)
			loaded += n
		ws.reload_until = -1.0
	_set_ammo(p, loaded)
	p.state.mark(&"slots")
	p.state.mark(&"gun")


# ------------------------------------------------------------------ fire
## One trigger pull. `aim` = the cursor point the owner fired at; `view_ms` = its interpolation delay (how far in
## the past it sees the others); `draw_ms` = how long the bow was drawn. Returns {ok, reason, seq, hits, kills, crit,
## ammo, pending}. The result goes back to the shooter through NetWorld.
static func fire(p: Player, seq: int, aim: Vector3, view_ms: int, draw_ms: int) -> Dictionary:
	var out := {"ok": false, "reason": "", "seq": seq, "hits": 0, "kills": 0, "crit": false, "ammo": -1}
	var now := _now()
	if p == null or p.dead:
		out["reason"] = "muerto"
		return out
	var hand := p.state.hand_tool()
	if not Firearms.is_firearm(hand):
		out["reason"] = "arma"
		return out
	var f := Firearms.of(hand)
	var ws: WeaponState = p.state.gun
	if ws.weapon != hand:
		ws.reset(hand)
	var is_bow := Firearms.is_bow(hand)
	if p.downed and StringName(f["class"]) != &"Pistol":
		out["reason"] = "derribado"
		return out
	if ws.jammed or ws.unjam_until >= 0.0:
		out["reason"] = "encasquillada"
		return out
	if ws.reload_until >= 0.0:
		if bool(f["per_shell"]) and ammo_in(p) > 0:
			ws.reload_until = -1.0   # a shot interrupts the shell-by-shell reload (GDD §7.4)
		else:
			out["reason"] = "recargando"
			return out
	if now - ws.last_shot < float(f["cadence"]) * Balance.GUN_CADENCE_TOLERANCE:
		out["reason"] = "cadencia"
		return out
	var world := _world(p)
	if world == null:
		out["reason"] = "mundo"
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldConst.hash64(WorldState.instance.world_seed if WorldState.instance != null else 0, p.peer_id, seq, ws.shots, 77)
	var draw := 1.0
	if is_bow:
		if p.state.warmth < Balance.BOW_WARMTH_MIN and p.state.count(&"guantes") <= 0:
			out["reason"] = "frio"
			p.state.notify("Tienes las manos heladas: no puedes tensar el arco", 2.0)
			return out
		draw = clampf(minf(float(draw_ms) / 1000.0, now - ws.last_shot) / float(f["cadence"]), 0.0, 1.0)
		if p.state.count(&"flechas") <= 0:
			out["reason"] = "sin_municion"
			return out
	else:
		var loaded := ammo_in(p)
		if loaded <= 0:
			ws.last_shot = now
			dry += 1
			out["reason"] = "sin_municion"
			out["ammo"] = 0
			AudioManager.play(&"gun_dry", p.global_position)
			SoundEvents.emit(p.global_position, Balance.GUN_DRY_NOISE, 1, SoundEvents.Kind.OTHER, p.peer_id, p.in_house)
			return out
		# jam (GDD §7.3): cold without gun oil +jam_cold per shot, a worn gun +2 %
		var p_jam := 0.0
		if is_cold_for_guns(p) and now >= ws.oil_until:
			p_jam += float(f["jam_cold"])
		if int(p.state.slots[0].get("dur", 100)) < 30:
			p_jam += Balance.GUN_WORN_JAM
		if p_jam > 0.0 and rng.randf() < p_jam:
			ws.jammed = true
			ws.last_shot = now
			jams += 1
			p.state.mark(&"gun")
			p.state.notify("¡Encasquillada! Pulsa R para destrabar", 2.0)
			AudioManager.play(&"gun_jam", p.global_position)
			out["reason"] = "encasquillada"
			return out
		_set_ammo(p, loaded - 1)
	# the shot
	var low := p.crouching or p.downed
	var origin := p.global_position + Vector3(0.0, 0.6 if low else Balance.GUN_ORIGIN_HEIGHT, 0.0)
	var to := aim - p.global_position
	to.y = 0.0
	if not is_finite(to.x) or to.length() < 0.3:
		to = p.facing()
	var yaw := atan2(to.x, to.z)
	origin += Vector3(sin(yaw), 0.0, cos(yaw)) * 0.35
	var spread := ws.spread * (1.0 if is_bow else 1.0)
	var green := Firearms.band(spread) == Firearms.Band.GREEN
	var crit_p := float(f["crit"]) + (Balance.GUN_CRIT_GREEN if green else 0.0)
	var yaws := Firearms.shot_yaws(hand, yaw, spread, rng.randi())
	# what the shooter saw left the server one down-trip + its interpolation delay before the click, and the request
	# took one up-trip: rewind = RTT + view delay (ARQ v2 §6.8), bounded to GUN_REWIND_MAX (200 ms)
	var rewind := clampf(Melee._rtt(p.peer_id) + clampf(float(view_ms), 0.0, 500.0) / 1000.0, 0.0, Balance.GUN_REWIND_MAX)
	last_rewind = rewind
	var ends := PackedVector3Array()
	var rules := WorldState.rules_now()
	if is_bow:
		p.state.inventory.remove(&"flechas", 1)
		var res := Projectiles.instance.spawn_arrow(p, origin, yaws[0], draw, rng.randf() < crit_p, seq) if Projectiles.instance != null else {}
		ends.append(res.get("end", origin))
		out["pending"] = true
	else:
		var hits := {}   # victim key -> {v, dmg, crit, n}
		var max_victims := int(f.get("max_victims", 99))
		for y in yaws:
			var tr := Hitscan.trace(world, p, origin, y, float(f["max_range"]), rewind, int(f["pierce"]), rules)
			ends.append(tr["end"])
			for v in (tr["victims"] as Array):
				if bool(v.get("pass", false)):
					continue
				var key := _victim_key(v)
				if not hits.has(key) and hits.size() >= max_victims:
					continue
				var e: Dictionary = hits.get(key, {"v": v, "dmg": 0.0, "crit": false, "n": 0})
				var c := rng.randf() < crit_p
				var d := float(f["dmg"]) * Firearms.falloff(hand, float(v["t"])) * (Balance.GUN_CRIT_MULT if c else 1.0)
				e["dmg"] = float(e["dmg"]) + d
				e["crit"] = bool(e["crit"]) or c
				e["n"] = int(e["n"]) + 1
				hits[key] = e
		for key in hits:
			var e: Dictionary = hits[key]
			var r := _damage(p, e["v"], float(e["dmg"]), bool(e["crit"]), f, origin)
			if r.get("applied", 0.0) > 0.0:
				out["hits"] = int(out["hits"]) + 1
			if bool(r.get("killed", false)):
				out["kills"] = int(out["kills"]) + 1
			if bool(e["crit"]):
				out["crit"] = true
	ws.spread += float(f["recoil"])
	ws.last_shot = now
	ws.shots += 1
	fired += 1
	var noise := SoundEvents.emit(origin, float(f["noise"]), 3, SoundEvents.Kind.GUN, p.peer_id, p.in_house)
	p.state.inventory.wear_hand(rng)
	p.play_swing(Firearms.clip(hand, &"shoot"))
	p.fx(&"shake", 0.25 if hand == &"escopeta" else Balance.GUN_SHAKE)
	p.state.mark(&"gun")
	if NetWorld.instance != null:
		NetWorld.instance.broadcast_shot(p, hand, origin, ends, (1 if bool(out["crit"]) else 0), maxf(noise, 30.0))
	out["ok"] = true
	out["ammo"] = ammo_in(p)
	last_shot = {"peer": p.peer_id, "weapon": hand, "origin": origin, "ends": ends, "hits": out["hits"], "kills": out["kills"],
		"rewind": rewind, "spread": spread, "noise": noise}
	if Net.is_dedicated and bool(Net.cfg_get("server", "debug_commands", false)) and not is_bow:
		# test servers: would the same bullet have hit without lag compensation? (net scenario `hitscan`)
		var norewind := 0
		for v in (Hitscan.trace(world, p, origin, yaws[0], float(f["max_range"]), 0.0, int(f["pierce"]), rules)["victims"] as Array):
			if not bool(v.get("pass", false)):
				norewind += 1
		print("[EVT] shot %d %s seq=%d spread=%.1f rewind=%.0fms rtt=%.0fms hits=%d norewind=%d kills=%d ammo=%d" % [p.peer_id, hand, seq, spread,
			rewind * 1000.0, Melee._rtt(p.peer_id) * 1000.0, out["hits"], mini(norewind, 1), out["kills"], out["ammo"]])
	return out


static func _victim_key(v: Dictionary) -> String:
	match int(v["kind"]):
		Hitscan.Victim.ZOMBIE:
			return "z%d" % int(v["id"])
		Hitscan.Victim.PLAYER:
			return "p%d" % (v["player"] as Player).peer_id
	return "a%d" % (v["node"] as Node).get_instance_id()


## Damage to one victim of a shot / an arrow (DamageResolver is the only one that reads pvp / friendly_fire).
static func _damage(p: Player, v: Dictionary, dmg: float, crit: bool, f: Dictionary, origin: Vector3) -> Dictionary:
	var a_ref := DamageResolver.ref(DamageResolver.Kind.PLAYER, p.peer_id)
	var kind: int = f["kind"]
	var rules := WorldState.rules_now()
	match int(v["kind"]):
		Hitscan.Victim.ZOMBIE:
			var sys := ZombieSystem.instance
			var slot := int(v["slot"])
			if sys == null or not sys.is_alive(slot) or sys.net_id[slot] != int(v["id"]):
				return {}
			# `dmg` already carries the per-pellet crits (crit_included): DamageResolver only flags the event / gore
			return DamageResolver.apply(a_ref, DamageResolver.ref(DamageResolver.Kind.ZOMBIE, sys.net_id[slot]), null, dmg, kind, rules, p,
				{"slot": slot, "crit": crit, "crit_included": true, "knock": float(f["knock"]), "dir": sys.pos[slot] - origin, "gore": true})
		Hitscan.Victim.PLAYER:
			var victim := v["player"] as Player
			var res := DamageResolver.apply(a_ref, DamageResolver.ref(DamageResolver.Kind.PLAYER, victim.peer_id), victim, dmg, kind, rules, p)
			print("[EVT] shot %d -> player %d dmg=%.0f -> %s" % [p.peer_id, victim.peer_id, dmg,
				"BLOCKED (%s)" % res["reason"] if res["blocked"] else "applied %.0f" % res["applied"]])
			if NetWorld.instance != null:
				Net.rpc_to(NetWorld.instance, &"hit_result", p.peer_id, [victim.peer_id, bool(res["blocked"]), str(res["reason"])])
			return res
		Hitscan.Victim.ANIMAL:
			var node := v["node"] as Node
			var res := DamageResolver.apply(a_ref, DamageResolver.ref(DamageResolver.Kind.ANIMAL), node, dmg, kind, rules, p)
			if not bool(res["blocked"]) and node is CharacterBody3D:
				(node as CharacterBody3D).velocity += (res["knockback"] as Vector3)
			return res
	return {}
