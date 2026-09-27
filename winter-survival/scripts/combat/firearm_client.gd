class_name FirearmClient
extends Node
## Owner client side of the firearms (M5; GDD v2 §7.1, §7.4; ARQ v2 §6.8). Child of the local Player. It predicts
## what the server will decide so the gun answers on the click (muzzle flash, recoil, the shoot clip, the reticle
## opening) and sends the intention; the server's result and the `gun` mirror correct it.
##   trigger   Interactor forwards the click when a firearm is in hand and no interactable is under the cursor: a gun
##             fires at once (semi-automatic, one shot per click, cadence respected locally), the bow draws while the
##             button is held (Bow_Draw) and looses on release (draw time → damage / range).
##   aim       the cursor point on the chest plane, snapped to a zombie within 1.2 m of it (magnetism; off for the
##             rifle beyond 25 m); the view delay of that zombie (its interpolation) goes with the request.
##   reload    R (the `interact` key, Interactor asks `wants_reload()` first) reloads or clears a jam.
##   throw     G with a can / a flare in hand throws it at the cursor (≤ 12 m).
##   reticle   Events.reticle_changed(spread°, band, aim point, radius at the aim distance) at 30 Hz while a firearm is
##             in hand (spread −1 once when it is put away); Events.weapon_state_changed carries the mirror (ammo,
##             magazine, reserve, jam, reload). The UI lane (H3) draws them; ReticleHook is the minimal stand-in.
##   camera    CameraRig.lean toward the cursor: 3 m (rifle 6 m), GDD §3.1.

var player: Player
var ws := WeaponState.new()
var weapon: StringName = &""
## Predicted rounds in the magazine (the mirror's `ammo` corrects it).
var ammo: int = 0
var seq: int = 0
var drawing: bool = false
var draw_t0: float = 0.0
var aim_point: Vector3 = Vector3.ZERO
var aim_zombie: int = 0
var band: int = Firearms.Band.GREEN
## Tests: shots requested / results received.
var shots_sent: int = 0
var results: Array = []
var _reticle_t: float = 0.0
var _hidden_sent: bool = true


func _ready() -> void:
	player = get_parent() as Player
	name = "Firearm"
	Events.weapon_state_changed.connect(_on_mirror)
	Events.fire_result.connect(_on_result)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func has_firearm() -> bool:
	return player != null and Firearms.is_firearm(player.state.hand_tool())


func has_throwable() -> bool:
	return player != null and Items.is_throwable(player.state.hand_tool())


func _on_mirror(d: Dictionary) -> void:
	if StringName(str(d.get("w", ""))) == weapon:
		ammo = int(d.get("ammo", ammo))
		ws.jammed = bool(d.get("jammed", false))
		var rl := float(d.get("reload_left", -1.0))
		ws.reload_until = _now() + rl if rl >= 0.0 else -1.0


func _on_result(s: int, ok: bool, reason: String, _hits: int, _kills: int, _crit: bool) -> void:
	results.append([s, ok, reason])
	if results.size() > 32:
		results.pop_front()
	if not ok:
		match reason:
			"sin_municion":
				Events.notify.emit("Sin munición · R para recargar" if reserve() > 0 else "Sin munición", 1.2)
			"encasquillada":
				ws.jammed = true
			"frio":
				pass


## Rounds of the hand weapon's ammo in the inventory mirror.
func reserve() -> int:
	return player.state.count(Firearms.ammo_of(weapon)) if weapon != &"" else 0


func _physics_process(delta: float) -> void:
	if player == null or not player.is_local:
		return
	var hand := player.state.hand_tool()
	if not Firearms.is_firearm(hand):
		if weapon != &"":
			weapon = &""
			drawing = false
			ws.reset(&"")
			_set_lean(Vector3.ZERO)
		if not _hidden_sent:
			_hidden_sent = true
			Events.reticle_changed.emit(-1.0, &"green", Vector3.ZERO, 0.0)
		return
	if hand != weapon:
		weapon = hand
		ws.reset(hand)
		ammo = int(player.state.slots[0].get("ammo", player.state.gun_view.get("ammo", 0))) if not player.state.slots[0].is_empty() else 0
		if player.state.gun_view.get("w", "") == String(hand):
			ammo = int(player.state.gun_view.get("ammo", ammo))
		drawing = false
	var v := Vector2(player.velocity.x, player.velocity.z).length()
	ws.spread = Firearms.step_spread(ws.spread, Firearms.target_spread(hand, v, player.running, player.crouching, player.state.warmth), delta)
	if ws.reload_until >= 0.0 and _now() > ws.reload_until + 0.5:
		ws.reload_until = -1.0
	_update_aim()
	var f := Firearms.of(hand)
	var lean := aim_point - player.global_position
	lean.y = 0.0
	_set_lean(lean.limit_length(float(f.get("lean", 3.0))))
	_reticle_t -= delta
	if _reticle_t <= 0.0:
		_reticle_t = 1.0 / 30.0
		_hidden_sent = false
		var dist := Vector2(aim_point.x - player.global_position.x, aim_point.z - player.global_position.z).length()
		var shown := ws.spread
		if drawing:
			shown = maxf(ws.spread, lerpf(Balance.GUN_BAND_RED + 2.0, ws.spread, clampf((_now() - draw_t0) / float(f["cadence"]), 0.0, 1.0)))
		band = Firearms.band(shown)
		if _ally_in_line():
			band = Firearms.Band.GREY
		var radius := dist * tan(deg_to_rad(shown + float(f.get("cone", 0.0))))
		Events.reticle_changed.emit(shown, Firearms.band_name(band), aim_point, radius)


## Cursor point on the chest plane (PlayerInput) with the zombie magnetism of GDD §7.1.
func _update_aim() -> void:
	var cur: Vector3 = player.input.get("_aim_point") if player.input != null else Vector3.INF
	if cur == Vector3.INF or cur == Vector3.ZERO:
		cur = player.global_position + player.facing() * 5.0
	aim_point = cur
	aim_zombie = 0
	var zc := ZombieClient.instance
	if zc == null:
		return
	var z := zc.nearest_to(cur, Balance.GUN_MAGNET_RADIUS)
	if z == null:
		return
	var d := Vector2(z.render_pos.x - player.global_position.x, z.render_pos.z - player.global_position.z).length()
	if weapon == &"rifle" and d > Balance.GUN_MAGNET_RIFLE_MAX:
		return
	aim_point = z.render_pos + Vector3(0, 1.1, 0)
	aim_zombie = z.id


func _ally_in_line() -> bool:
	if bool(WorldState.rules_now().get("pvp", false)) or str(WorldState.rules_now().get("friendly_fire", "off")) != "off":
		return false
	var o := Vector2(player.global_position.x, player.global_position.z)
	var to := Vector2(aim_point.x, aim_point.z) - o
	var len := to.length()
	if len < 0.5:
		return false
	var dir := to / len
	for n in player.get_parent().get_children():
		var other := n as Player
		if other == null or other == player or other.dead:
			continue
		var oc := Vector2(other.global_position.x, other.global_position.z) - o
		var t := oc.dot(dir)
		if t > 0.5 and t < len and absf(oc.cross(dir)) < Balance.GUN_HIT_RADIUS:
			return true
	return false


func _set_lean(v: Vector3) -> void:
	if player.camera_rig != null:
		player.camera_rig.lean = v


## Interactor: the click with a firearm in hand (`z` = the hovered zombie record or null).
func trigger_pressed(z: ZombieClient.ZRec = null) -> void:
	if z != null:
		aim_point = z.render_pos + Vector3(0, 1.1, 0)
		aim_zombie = z.id
	if Firearms.is_bow(weapon):
		if player.state.count(&"flechas") <= 0:
			Events.notify.emit("No tienes flechas", 1.2)
			return
		drawing = true
		draw_t0 = _now()
		if player.view != null:
			player.view.play_local_swing(Firearms.clip(weapon, &"reload"))   # Bow_Draw
		return
	fire()


func trigger_released() -> void:
	if drawing:
		drawing = false
		fire(int((_now() - draw_t0) * 1000.0))


## Sends a shot (predicting it when the local state says it will go off). Returns true when a request was sent.
func fire(draw_ms: int = 0) -> bool:
	if not has_firearm():
		return false
	var f := Firearms.of(weapon)
	var now := _now()
	if now - ws.last_shot < float(f["cadence"]) * Balance.GUN_CADENCE_TOLERANCE:
		return false
	var bow := Firearms.is_bow(weapon)
	var predicted := not ws.jammed and ws.reload_until < 0.0 and (ammo > 0 or bow)
	ws.last_shot = now
	seq += 1
	shots_sent += 1
	var to := aim_point - player.global_position
	player.face_toward(aim_point)
	if predicted:
		if not bow:
			ammo -= 1
		ws.spread += float(f["recoil"])
		if player.view != null:
			player.view.play_local_swing(Firearms.clip(weapon, &"shoot"))
		Events.local_shot.emit(weapon, ws.spread)
		Events.camera_shake.emit(0.25 if weapon == &"escopeta" else Balance.GUN_SHAKE)
	elif ammo <= 0 and not bow:
		AudioManager.play(&"gun_dry")
	var view_ms := 100
	if aim_zombie != 0 and ZombieClient.instance != null:
		var r := ZombieClient.instance.record(aim_zombie)
		if r != null:
			view_ms = int(clampf(r.interval * 1.2, 0.1, 0.3) * 1000.0)
	Net.rpc_server(NetWorld.instance, &"request_fire", [seq, player.global_position + to.limit_length(Balance.GUN_MAX_AIM), view_ms, draw_ms])
	return true


func wants_reload() -> bool:
	if not has_firearm() or Firearms.is_bow(weapon):
		return false
	return ws.jammed or (ammo < Firearms.mag_of(weapon) and reserve() > 0 and ws.reload_until < 0.0)


func reload() -> void:
	if not has_firearm():
		return
	if not ws.jammed:
		var t := Firearms.reload_time(weapon)
		ws.reload_until = _now() + t
		if player.view != null:
			player.view.play_local_swing(Firearms.clip(weapon, &"reload"))
	elif player.view != null:
		player.view.play_local_swing(&"Act_Unjam")
	Net.rpc_server(NetWorld.instance, &"request_reload", [])


## G: throws the hand's can / flare at the cursor.
func throw_at(target: Vector3) -> void:
	if not has_throwable():
		return
	player.face_toward(target)
	if player.view != null:
		player.view.play_local_swing(&"Act_Throw")
	Net.rpc_server(NetWorld.instance, &"request_throw", [target])


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.is_local or player.dead or not GameFlow.in_game:
		return
	if event.is_action_pressed("throw") and has_throwable():
		var cur: Vector3 = player.input.get("_aim_point") if player.input != null else player.global_position + player.facing() * 6.0
		throw_at(cur)
		get_viewport().set_input_as_handled()
