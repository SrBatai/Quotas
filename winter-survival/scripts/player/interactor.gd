class_name Interactor
extends Node
## Owner client: cursor raycast → hovered InteractableComponent; click → predicted auto-walk when far, then a
## validated `NetWorld.request_interact(wid, action, arg)` with an optimistic `client_preview` (reverted on a
## denial); attack → `request_attack`. Labels use the owner's state mirror.
## M3: trees are MultiMesh instances; a ray that meets a chunk's scatter trunk, or passes through a tree's crown
## (World.pick_scatter over the scatter index), materializes that one tree so the usual component takes over.
## M4 melee (GDD v2 §7.1, §3.2): a zombie under the cursor (its view's pick capsule, or within the 1.2 m
## magnetism of the cursor's ground point) wins the hover; click = light attack, hold ≥ MELEE_CHARGE_HOLD =
## charged on release; with the knife a frozen / unaware zombie is executed, a knocked-down one (or a crawler) is
## stomped. With a weapon and nothing under the cursor the click swings toward it. Space attacks the nearest enemy,
## V / LT shoves. A downed teammate under the cursor or within reach: hold R (or the click) to revive. Downed
## yourself: hold X to give up. The swing plays at once (prediction); the server validates and resolves.

var target: InteractableComponent
var pending: InteractableComponent
var hover_text: String = ""
## M4: hovered zombie record (ZombieClient) / downed teammate, and the melee hold in progress.
var zombie_target: ZombieClient.ZRec
var revive_target: Player
var _hold_t: float = -1.0
var _hold_zombie: int = 0
var _hold_point: Vector3 = Vector3.INF
var _reviving: int = 0
var _give_up_t: float = -1.0
var _player: Player
var _ring: HoverRing
var _previews: Dictionary = {}   # wid -> [comp, action] awaiting the server's answer


func _ready() -> void:
	_player = get_parent()
	_ring = _player.get_node_or_null("View/HoverRing")
	Events.interact_result.connect(_on_interact_result)


func _camera() -> Camera3D:
	return get_viewport().get_camera_3d()


func _active() -> bool:
	return GameFlow.in_game and not _player.dead


func _physics_process(delta: float) -> void:
	_update_holds(delta)
	if _player.downed and not _player.dead:
		zombie_target = null
		revive_target = null
		_set_hover(null, "Mantén X para rendirte" if _give_up_t < 0.0 else "Rindiéndote… %d" % int(ceil(Balance.GIVE_UP_HOLD - _give_up_t)))
		return
	if not _active():
		_set_hover(null, "")
		return
	if _player.placement != null and _player.placement.active:
		_set_hover(null, "")
		return
	if get_viewport().gui_get_hovered_control() != null:
		_set_hover(null, "")
		return
	var cam := _camera()
	if cam == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * 120.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 8 | 128, [_player.get_rid()])
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(q)
	var found: InteractableComponent = null
	if not hit.is_empty() and hit.collider != null:
		found = InteractableComponent.find_from(hit.collider)
		if found == null and hit.collider.has_meta("scatter_chunk"):
			var ch: WorldChunk = hit.collider.get_meta("scatter_chunk")
			var i := ch.entry_of_hit(hit.collider, int(hit.get("shape", -1)))
			if i >= 0 and ScatterCatalog.is_choppable(int(ch.data.entries[i]["v"])):
				var t := ch.materialize(i)
				found = t.interactable if t != null else null
	if found == null and World.instance != null:
		var ground: Vector3 = hit.position if not hit.is_empty() else to
		var t := World.instance.pick_scatter(from, (to - from).normalized(), ground)
		if t != null and t.is_inside_tree():
			found = t.interactable
	if found != null and not is_instance_valid(found):
		found = null
	# M4: zombies (pick capsule or cursor magnetism) and downed teammates win over the scenery
	zombie_target = null
	revive_target = null
	var ground: Vector3 = hit.position if not hit.is_empty() else to
	if not hit.is_empty() and hit.collider != null and hit.collider.has_meta("zombie_view"):
		var zv: ZombieView = hit.collider.get_meta("zombie_view")
		if ZombieClient.instance != null and is_instance_valid(zv):
			zombie_target = ZombieClient.instance.record(zv.id)
	if zombie_target == null and ZombieClient.instance != null:
		zombie_target = ZombieClient.instance.nearest_to(ground, 1.2)
	if zombie_target == null:
		revive_target = _downed_near(ground, 1.4)
	var text := ""
	if zombie_target != null and zombie_target.state != ZombieKinds.State.DEAD:
		found = null
		text = _zombie_label(zombie_target)
	elif revive_target != null:
		found = null
		text = "Reanimar a %s (mantén R · %d s)" % [revive_target.display_name, int(Balance.REVIVE_TIME)]
		if _player.global_position.distance_to(revive_target.global_position) > Balance.REVIVE_RANGE:
			text += " · acércate"
	elif found != null:
		text = found.get_label(_player)
		if found.can_interact(_player) and found.distance_to(_player) > found.interact_range:
			text += " · acércate"
	_set_hover(found, text)


func _set_hover(found: InteractableComponent, text: String) -> void:
	target = found
	if _ring != null and is_instance_valid(_ring):
		if found != null:
			_ring.show_at(found.get_ring_position(), found.ring_radius, found.can_interact(_player))
		else:
			_ring.hide_ring()
	if text != hover_text:
		hover_text = text
		Events.hover_changed.emit(text)


func _unhandled_input(event: InputEvent) -> void:
	if _player.downed and not _player.dead:
		if event.is_action_pressed("give_up"):
			_give_up_t = 0.0
		elif event.is_action_released("give_up"):
			_give_up_t = -1.0
		return
	if not _active():
		return
	if _player.placement != null and _player.placement.active:
		return
	if event.is_action_pressed("interact_click"):
		if zombie_target != null and zombie_target.state != ZombieKinds.State.DEAD:
			begin_melee(zombie_target.id, zombie_target.render_pos)
		elif revive_target != null:
			start_revive(revive_target)
		elif target == null and Weapons.is_weapon(_player.state.hand_tool()):
			begin_melee(0, _cursor_point())
		else:
			_click()
	elif event.is_action_released("interact_click"):
		if _hold_t >= 0.0:
			release_melee()
		elif _reviving != 0:
			stop_revive()
	elif event.is_action_pressed("interact"):
		var d := _downed_near(_player.global_position, Balance.REVIVE_RANGE)
		if d != null:
			start_revive(d)
		else:
			_interact_nearest()
	elif event.is_action_released("interact"):
		if _reviving != 0:
			stop_revive()
	elif event.is_action_pressed("attack"):
		attack_nearest()
	elif event.is_action_released("attack"):
		if _hold_t >= 0.0:
			release_melee()
	elif event.is_action_pressed("shove"):
		shove()


func _click() -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.can_interact(_player):
		var t := target.get_label(_player)
		if t != "":
			Events.notify.emit(t, 1.5)
		return
	_go_or_interact(target)


func _go_or_interact(comp: InteractableComponent) -> void:
	if comp.distance_to(_player) <= comp.interact_range:
		pending = null
		_player.auto_target = null
		send_interact(comp)
	else:
		pending = comp
		_player.auto_target = comp


## Sends the component's default action (or `action`) and previews it locally on a pure client.
func send_interact(comp: InteractableComponent, action: StringName = &"", arg: int = 0) -> void:
	if action == &"":
		action = comp.default_action
	_player.face_toward(comp.global_position)
	var wid := comp.wid()
	Net.rpc_server(NetWorld.instance, &"request_interact", [wid, action, arg])
	if Net.is_client:
		comp.client_preview(_player, action)
		_previews[wid] = [comp, action]


func _on_interact_result(wid: int, action: StringName, ok: bool, _reason: String) -> void:
	if not _previews.has(wid):
		return
	var e: Array = _previews[wid]
	_previews.erase(wid)
	var comp: InteractableComponent = e[0]
	if not ok and comp != null and is_instance_valid(comp):
		comp.client_preview_cancel(_player, action)


## Called by the player input when auto-walk reaches the pending target.
func perform_pending() -> void:
	if pending != null and is_instance_valid(pending) and pending.can_interact(_player):
		send_interact(pending)
	pending = null


func _interact_nearest() -> void:
	var best: InteractableComponent = null
	var best_d := 2.6
	for n in get_tree().get_nodes_in_group("interactable"):
		var comp := InteractableComponent.find_from(n)
		if comp == null or not comp.can_interact(_player):
			continue
		var d := comp.distance_to(_player)
		if d < best_d:
			best_d = d
			best = comp
	# M3: the nearest MultiMesh tree / log in reach counts too (materialized when chosen)
	if World.instance != null and World.instance.is_configured:
		var f := World.instance.nearest_scatter(_player.global_position, "", 0)
		if not f.is_empty():
			var ch: WorldChunk = f[0]
			var d := Vector2(ch.entry_position(f[1]).x - _player.global_position.x, ch.entry_position(f[1]).z - _player.global_position.z).length()
			if d < best_d:
				var t := ch.materialize(int(f[1]))
				if t != null and t.interactable.can_interact(_player):
					best = t.interactable
	if best != null:
		_go_or_interact(best)


# ------------------------------------------------------------------ M4 melee (owner client)
func _cursor_point() -> Vector3:
	var aim: Vector3 = _player.input.get("_aim_point") if _player.input != null else Vector3.INF
	return aim if aim != Vector3.INF else _player.global_position + _player.facing() * 2.0


func _zombie_label(z: ZombieClient.ZRec) -> String:
	var name_k := String(ZombieKinds.row(z.kind)["name"])
	var hand := _player.state.hand_tool()
	var w := Weapons.of(hand)
	var mode := _mode_for(z)
	var t := "Atacar a %s" % name_k.to_lower()
	match mode:
		Weapons.Mode.EXECUTE:
			t = "Ejecutar a %s (cuchillo, en silencio)" % name_k.to_lower()
		Weapons.Mode.STOMP:
			t = "Pisotear a %s" % name_k.to_lower()
	if z.state == ZombieKinds.State.FROZEN and mode != Weapons.Mode.EXECUTE:
		t += " (congelado)"
	if hand != &"" and Weapons.is_weapon(hand):
		t += " · %s" % String(w["name"]).to_lower()
	var d := Vector2(z.render_pos.x - _player.global_position.x, z.render_pos.z - _player.global_position.z).length()
	if d > float(w["reach"]) + 0.6:
		t += " · acércate"
	return t


## The attack a click on `z` becomes: execution (knife + frozen / unaware), stomp (knocked down, crawler), light.
func _mode_for(z: ZombieClient.ZRec) -> int:
	if z == null:
		return Weapons.Mode.LIGHT
	if Weapons.can_execute(_player.state.hand_tool()) and z.state in [ZombieKinds.State.FROZEN, ZombieKinds.State.WAKING, ZombieKinds.State.IDLE, ZombieKinds.State.WANDER]:
		return Weapons.Mode.EXECUTE
	if z.state == ZombieKinds.State.KNOCKED or z.kind == ZombieKinds.Kind.CRAWLER:
		return Weapons.Mode.STOMP
	return Weapons.Mode.LIGHT


func begin_melee(zombie_id: int, at: Vector3) -> void:
	_hold_t = 0.0
	_hold_zombie = zombie_id
	_hold_point = at
	_player.face_toward(at)


## Click released (or held long enough): light / charged / execution / stomp toward the target.
func release_melee() -> void:
	if _hold_t < 0.0:
		return
	var charged := _hold_t >= Balance.MELEE_CHARGE_HOLD
	_hold_t = -1.0
	var z: ZombieClient.ZRec = ZombieClient.instance.record(_hold_zombie) if ZombieClient.instance != null and _hold_zombie != 0 else null
	var at := z.render_pos if z != null else _hold_point
	var mode := _mode_for(z)
	if mode == Weapons.Mode.LIGHT and charged and _player.state.stamina >= Balance.STAMINA_MIN_RUN:
		mode = Weapons.Mode.CHARGED
	send_melee(mode, at, _hold_zombie)


func send_melee(mode: int, at: Vector3, zombie_id: int) -> void:
	var dir := at - _player.global_position
	var yaw := atan2(dir.x, dir.z) if Vector2(dir.x, dir.z).length() > 0.05 else _player.aim_yaw
	_player.face_toward(at)
	if _player.view != null:
		_player.view.play_local_swing(Weapons.clip(_player.state.hand_tool(), mode))
	Events.local_swing.emit(Weapons.clip(_player.state.hand_tool(), mode))
	Net.rpc_server(NetWorld.instance, &"request_melee", [mode, yaw, zombie_id])


## V / LT: shove toward the nearest zombie in front (or straight ahead).
func shove() -> void:
	var z: ZombieClient.ZRec = ZombieClient.instance.nearest_to(_player.global_position, Balance.SHOVE_RANGE + 0.8) if ZombieClient.instance != null else null
	var at := z.render_pos if z != null else _player.global_position + _player.facing() * 1.5
	send_melee(Weapons.Mode.SHOVE, at, z.id if z != null else 0)


func _update_holds(delta: float) -> void:
	if _hold_t >= 0.0:
		var was := _hold_t
		_hold_t += delta
		# held past the light-click time: the Melee_Charged wind-up starts and waits on its hold pose
		if was < Balance.MELEE_CHARGE_HOLD and _hold_t >= Balance.MELEE_CHARGE_HOLD and _player.view != null \
				and _player.state.stamina >= Balance.STAMINA_MIN_RUN:
			var z: ZombieClient.ZRec = ZombieClient.instance.record(_hold_zombie) if ZombieClient.instance != null and _hold_zombie != 0 else null
			if _mode_for(z) == Weapons.Mode.LIGHT:
				_player.view.visual.begin_charge()
		if _hold_t >= Balance.MELEE_CHARGE_HOLD + 0.8:
			release_melee()   # a held click lets the charged swing go by itself
	if _give_up_t >= 0.0:
		_give_up_t += delta
		if _give_up_t >= Balance.GIVE_UP_HOLD:
			_give_up_t = -1.0
			Net.rpc_server(NetWorld.instance, &"request_give_up", [])
	if _reviving != 0:
		var t := _player.get_parent().get_node_or_null(str(_reviving)) as Player
		if t == null or not t.downed:
			_reviving = 0


func _downed_near(p: Vector3, r: float) -> Player:
	var best: Player = null
	var best_d := r
	for n in _player.get_parent().get_children():
		var o := n as Player
		if o == null or o == _player or not o.downed or o.dead:
			continue
		var d := Vector2(o.global_position.x - p.x, o.global_position.z - p.z).length()
		if d <= best_d:
			best_d = d
			best = o
	return best


func start_revive(t: Player) -> void:
	_reviving = t.peer_id
	_player.face_toward(t.global_position)
	Net.rpc_server(NetWorld.instance, &"request_revive", [t.peer_id, true])


func stop_revive() -> void:
	if _reviving != 0:
		Net.rpc_server(NetWorld.instance, &"request_revive", [_reviving, false])
	_reviving = 0


## Space: the nearest enemy in reach — a zombie (melee light, stomp or execution) or, as in the slice, a wolf /
## deer (request_attack) — or a swing in the air.
func attack_nearest() -> void:
	if ZombieClient.instance != null:
		var z := ZombieClient.instance.nearest_to(_player.global_position, maxf(Balance.ATTACK_RANGE, float(Weapons.of(_player.state.hand_tool())["reach"]) + 0.6))
		if z != null:
			var wolf_closer := false
			for w in get_tree().get_nodes_in_group("wolves"):
				if (w as Node3D).global_position.distance_to(_player.global_position) < z.render_pos.distance_to(_player.global_position):
					wolf_closer = true
			if not wolf_closer:
				begin_melee(z.id, z.render_pos)   # released → light (or charged when held)
				return
	_attack_animal_nearest()


func _attack_animal_nearest() -> void:
	var best: Node = null
	var best_d := Balance.ATTACK_RANGE
	var p: Vector3 = _player.global_position
	for group in ["wolves", "deer"]:
		for w in get_tree().get_nodes_in_group(group):
			if w.has_method("is_dead") and w.is_dead():
				continue
			var d := Vector2(w.global_position.x - p.x, w.global_position.z - p.z).length()
			if d < best_d:
				best_d = d
				best = w
	if best != null:
		_player.face_toward(best.global_position)
	Net.rpc_server(NetWorld.instance, &"request_attack", [WorldRegistry.wid_of(best) if best != null else 0])
