class_name Projectiles
extends Node
## Server-simulated projectiles of M5 (ARQ v2 §11.3 `projectile.gd`; GDD v2 §7.6 rows 7 and 14):
##   arrows      flat flight at the bow's speed (×draw), tested step by step with the same 2D victim test as a bullet
##               (Hitscan over each physics step, pierce 1), damage ×draw, 60 % of the arrows can be picked up again
##               (a `flechas` drop where it hit or fell);
##   throwables  a can (lands → a 15 m noise that lures the zombies) and a flare (no noise: its light draws the zombies
##               within 40 m to it for 30 s). Parabolic flight of `THROW_RANGE` m max; the landing is decided here.
## Clients only draw them (NetWorld `_projectile` → Events.projectile_spawned → FirearmFx).

enum Kind { ARROW, CAN, FLARE }

static var instance: Projectiles

var _arrows: Array[Dictionary] = []
var _throws: Array[Dictionary] = []
var _flares: Array[Dictionary] = []
## Tests / stats.
var arrows_fired: int = 0
var arrow_hits: int = 0
var landed: int = 0
var lures: int = 0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func active_flares() -> Array[Dictionary]:
	return _flares


## Server: looses an arrow. Returns {"end": the point where it would stop without hitting anyone (for the visual)}.
func spawn_arrow(p: Player, origin: Vector3, yaw: float, draw: float, crit: bool, seq: int) -> Dictionary:
	var f := Firearms.of(&"arco")
	var d := maxf(draw, Balance.BOW_MIN_DRAW)
	var speed := float(f["arrow_speed"]) * (0.5 + 0.5 * d)
	var dist := float(f["range"]) * d
	var dir := Vector3(sin(yaw), 0.0, cos(yaw))
	var world := p.get_tree().get_first_node_in_group("world") as World
	var end := origin + dir * dist
	if world != null:
		var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, end, 1, [p.get_rid()]))
		if not hit.is_empty():
			end = hit.position
	_arrows.append({"p": p, "peer": p.peer_id, "pos": origin, "dir": dir, "yaw": yaw, "speed": speed, "left": origin.distance_to(end),
		"dmg": float(f["dmg"]) * d, "crit": crit, "seq": seq, "t0": _now()})
	arrows_fired += 1
	if NetWorld.instance != null:
		NetWorld.instance.broadcast_projectile(Kind.ARROW, origin, end, origin.distance_to(end) / speed, p.peer_id)
	return {"end": end}


## Server: throws the hand's throwable toward `target` (≤ THROW_RANGE m). Returns "" or the refusal reason.
func throw_item(p: Player, target: Vector3) -> String:
	if p == null or p.dead or p.downed:
		return "muerto"
	var id := p.state.hand_tool()
	if not Items.is_throwable(id):
		return "arma"
	if not is_finite(target.x) or not is_finite(target.z):
		return "args"
	var from := p.global_position + Vector3(0, 1.5, 0)
	var flat := Vector3(target.x - from.x, 0.0, target.z - from.z).limit_length(Balance.THROW_RANGE)
	var world := p.get_tree().get_first_node_in_group("world") as World
	var to := from + flat
	if world != null:
		# a wall in the way stops the throw there
		var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, Vector3(to.x, from.y, to.z), 1, [p.get_rid()]))
		if not hit.is_empty():
			to = hit.position - flat.normalized() * 0.3
		to.y = world.get_height(to.x, to.z) + 0.05
	p.state.inventory.remove(id, 1)
	var kind := Kind.FLARE if id == &"bengala" else Kind.CAN
	var flight := maxf(flat.length() / Balance.THROW_SPEED, 0.25)
	_throws.append({"kind": kind, "to": to, "at": _now() + flight, "peer": p.peer_id})
	p.play_swing(&"Act_Throw")
	if NetWorld.instance != null:
		NetWorld.instance.broadcast_projectile(kind, from, to, flight, p.peer_id)
	return ""


func _physics_process(dt: float) -> void:
	if not Net.is_server:
		return
	var now := _now()
	if not _arrows.is_empty():
		_step_arrows(dt, now)
	for i in range(_throws.size() - 1, -1, -1):
		var t: Dictionary = _throws[i]
		if now >= float(t["at"]):
			_throws.remove_at(i)
			_land(t, now)
	for i in range(_flares.size() - 1, -1, -1):
		var fl: Dictionary = _flares[i]
		if now >= float(fl["until"]):
			_flares.remove_at(i)
		elif now >= float(fl["next"]):
			fl["next"] = now + 1.0
			if ZombieSystem.instance != null:
				lures += ZombieSystem.instance.lure(fl["pos"], Balance.FLARE_LURE_RADIUS)


func _land(t: Dictionary, now: float) -> void:
	landed += 1
	var pos: Vector3 = t["to"]
	if int(t["kind"]) == Kind.CAN:
		SoundEvents.emit(pos, Balance.CAN_NOISE, 1, SoundEvents.Kind.THROW, int(t["peer"]))
		AudioManager.play(&"can_land", pos)
	else:
		_flares.append({"pos": pos, "until": now + Balance.FLARE_SECONDS, "next": now})
		if ZombieSystem.instance != null:
			lures += ZombieSystem.instance.lure(pos, Balance.FLARE_LURE_RADIUS)
		# the flare warms whoever stands at it (GDD §7.6: Calor +5)
		for n in get_tree().get_nodes_in_group("player"):
			var pl := n as Player
			if pl != null and pl.state != null and pl.state.stats != null and pl.global_position.distance_to(pos) < 3.0:
				pl.state.warmth = minf(pl.state.warmth + Balance.FLARE_WARMTH, Balance.WARMTH_MAX)


func _step_arrows(dt: float, now: float) -> void:
	var rules := WorldState.rules_now()
	for i in range(_arrows.size() - 1, -1, -1):
		var a: Dictionary = _arrows[i]
		var p := a["p"] as Player
		var step := minf(float(a["speed"]) * dt, float(a["left"]))
		var pos: Vector3 = a["pos"]
		var done := false
		if is_instance_valid(p):
			var world := p.get_tree().get_first_node_in_group("world") as World
			var tr := Hitscan.trace(world, p, pos, float(a["yaw"]), step, 0.0, 1, rules)
			for v in (tr["victims"] as Array):
				if bool(v.get("pass", false)):
					continue
				var res := Gunplay._damage(p, v, float(a["dmg"]) * (Balance.GUN_CRIT_MULT if bool(a["crit"]) else 1.0), bool(a["crit"]),
					Firearms.of(&"arco"), pos)
				arrow_hits += 1
				if NetWorld.instance != null:
					NetWorld.instance.send_fire_result(int(a["peer"]), {"ok": true, "reason": "", "seq": int(a["seq"]), "hits": 1,
						"kills": 1 if bool(res.get("killed", false)) else 0, "crit": bool(a["crit"]), "ammo": -1})
				_recover(world, tr["end"], int(a["seq"]) + int(a["peer"]))
				done = true
				break
			if not done and bool(tr["wall"]):
				_recover(world, tr["end"], int(a["seq"]) + int(a["peer"]))
				done = true
		a["pos"] = pos + (a["dir"] as Vector3) * step
		a["left"] = float(a["left"]) - step
		if not done and (float(a["left"]) <= 0.01 or now - float(a["t0"]) > Balance.ARROW_LIFETIME):
			if is_instance_valid(p):
				_recover(p.get_tree().get_first_node_in_group("world") as World, a["pos"], int(a["seq"]) + int(a["peer"]))
			done = true
		if done:
			_arrows.remove_at(i)


## 60 % of the arrows can be picked up where they stopped (GDD §7.2).
func _recover(world: World, at: Vector3, salt: int) -> void:
	if world == null:
		return
	if WorldConst.unit(WorldConst.hash64(salt, 0x4152524F57)) >= float(Firearms.of(&"arco").get("recover", 0.6)):
		return
	world.spawn_drop(&"flechas", "arrow", Vector3(at.x, world.get_height(at.x, at.z), at.z), 1)
