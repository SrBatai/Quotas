class_name NetWorld
extends Node
## /root/Game/NetWorld: every client intention that touches the world or the player's own state travels through
## here as a validated RPC (ARQ v2 §6.6); world object deltas (tree hits, felled, pickups taken, bushes, fires,
## containers "in use") are stored on the server and broadcast as events + sent as a snapshot to late joiners
## (M1 version of the chunk delta, ARQ v2 §8.8). Same node path on client and server; offline = direct calls.

const REASONS := {
	"lejos": "Acércate", "sin_herramienta": "Necesitas un hacha", "no_disponible": "No disponible",
	"no_existe": "Ya no está", "en_uso": "En uso por otro jugador", "muerto": "Estás muerto",
}

static var instance: NetWorld

## wid -> Dictionary of replicated fields (server authoritative; clients hold a copy).
var deltas: Dictionary = {}
var _rate: Dictionary = {}          # [peer, kind] -> Array of timestamps
var _infractions: Dictionary = {}   # peer -> count


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	if Net.is_server:
		Net.peer_joined.connect(func(peer_id: int, _n: String) -> void:
			Net.rpc_to(self, &"_delta_snapshot", peer_id, [deltas]))


# ------------------------------------------------------------------ helpers (server)
func _player_of(peer: int) -> Player:
	var players := get_tree().get_first_node_in_group("world").get_node_or_null("Players") if get_tree().get_first_node_in_group("world") != null else null
	if players == null:
		return null
	return players.get_node_or_null(str(peer)) as Player


func _allow(peer: int, kind: StringName, per_second: float) -> bool:
	var key := [peer, kind]
	var now := Time.get_ticks_msec() / 1000.0
	var arr: Array = _rate.get(key, [])
	while not arr.is_empty() and now - float(arr[0]) > 1.0:
		arr.pop_front()
	if arr.size() >= int(ceil(per_second)):
		_note_infraction(peer, "rate:%s" % kind)
		_rate[key] = arr
		return false
	arr.append(now)
	_rate[key] = arr
	return true


func _note_infraction(peer: int, reason: String) -> void:
	_infractions[peer] = int(_infractions.get(peer, 0)) + 1
	if _infractions[peer] == Balance.NET_INFRACTIONS_KICK and Net.is_dedicated:
		print("[NET] peer %d kicked after %d infractions (%s)" % [peer, _infractions[peer], reason])
		Net.kick(peer, "infractions")


func _deny(peer: int, reason: String) -> void:
	_note_infraction(peer, reason)
	var p := _player_of(peer)
	if p != null:
		p.state.notify(REASONS.get(reason, "No puedes hacer eso"), 2.0)


## Validates that `player` can use `comp` now: distance + tolerance, tool, availability.
func _check_interact(player: Player, comp: InteractableComponent) -> String:
	if player.dead:
		return "muerto"
	if comp == null or not is_instance_valid(comp) or not comp.enabled:
		return "no_existe"
	if comp.distance_to(player) > comp.interact_range + Balance.NET_INTERACT_TOLERANCE:
		return "lejos"
	if comp.requires_tool != &"" and player.state.hand_tool() != comp.requires_tool:
		return "sin_herramienta"
	if not comp.can_interact(player):
		return "no_disponible"
	return ""


# ------------------------------------------------------------------ world interaction
@rpc("any_peer", "call_remote", "reliable", 1)
func request_interact(wid: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := Net.sender()
	var player := _player_of(peer)
	if player == null or not _allow(peer, &"interact", Balance.NET_INTERACT_PER_SECOND):
		return
	var obj := WorldRegistry.get_object(wid)
	if obj == null:
		_deny(peer, "no_existe")
		return
	var comp := InteractableComponent.find_from(obj)
	var why := _check_interact(player, comp)
	if why != "":
		_deny(peer, why)
		return
	player.face_toward(comp.global_position)
	comp.interact(player)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_attack(wid: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := Net.sender()
	var player := _player_of(peer)
	if player == null or player.dead or not _allow(peer, &"attack", 4.0):
		return
	var target: Node = WorldRegistry.get_object(wid) if wid != 0 else null
	if target != null and target is Node3D:
		var d := Vector2(target.global_position.x - player.global_position.x, target.global_position.z - player.global_position.z).length()
		if d > Balance.ATTACK_RANGE + Balance.NET_INTERACT_TOLERANCE:
			target = null
	player.attack(target)


## PvP / friendly-fire gate (PLAN C20): only DamageResolver reads the rules.
@rpc("any_peer", "call_remote", "reliable", 1)
func request_hit_player(victim_peer: int, dmg: float) -> void:
	if not multiplayer.is_server():
		return
	var peer := Net.sender()
	var attacker := _player_of(peer)
	var victim := _player_of(victim_peer)
	if attacker == null or attacker.dead or not _allow(peer, &"hit", 4.0):
		return
	var result := {"applied": 0.0, "blocked": true, "reason": "no_victim"}
	if victim != null and victim != attacker:
		var a_ref := DamageResolver.ref(DamageResolver.Kind.PLAYER, peer)
		var v_ref := DamageResolver.ref(DamageResolver.Kind.PLAYER, victim_peer)
		var kind := DamageResolver.DamageKind.MELEE_SHARP
		# policy first (PLAN C20), then the M1 sanity range (M4 replaces it by the validated melee cone/reach)
		if DamageResolver.player_vs_player_mult(WorldState.rules_now(), a_ref, v_ref, kind) <= 0.0:
			result["reason"] = "friendly_fire"
		elif attacker.global_position.distance_to(victim.global_position) > Balance.NET_MAX_AIM_DIST:
			result["reason"] = "lejos"
		else:
			result = DamageResolver.apply(a_ref, v_ref, victim, clampf(dmg, 0.0, Balance.AXE_DAMAGE), kind, WorldState.rules_now(), attacker)
	print("[EVT] request_hit_player from %d on %d dmg=%.0f -> %s" % [peer, victim_peer, dmg,
		"BLOCKED (%s)" % result["reason"] if result["blocked"] else "applied %.0f" % result["applied"]])
	Net.rpc_to(self, &"hit_result", peer, [victim_peer, bool(result["blocked"]), str(result["reason"])])


@rpc("authority", "call_remote", "reliable", 1)
func hit_result(victim_peer: int, blocked: bool, reason: String) -> void:
	if Net.is_dedicated:
		return
	Events.hit_result.emit(victim_peer, blocked, reason)


# ------------------------------------------------------------------ own state
@rpc("any_peer", "call_remote", "reliable", 1)
func request_use_slot(i: int) -> void:
	if not multiplayer.is_server():
		return
	var p := _player_of(Net.sender())
	if p != null and not p.dead and _allow(Net.sender(), &"slot", 10.0):
		p.state.inventory.use_slot(i)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_toggle_torch() -> void:
	if not multiplayer.is_server():
		return
	var p := _player_of(Net.sender())
	if p != null and not p.dead and _allow(Net.sender(), &"slot", 10.0):
		p.state.inventory.toggle_torch()


@rpc("any_peer", "call_remote", "reliable", 1)
func request_eat_best() -> void:
	if not multiplayer.is_server():
		return
	var p := _player_of(Net.sender())
	if p != null and not p.dead and _allow(Net.sender(), &"slot", 10.0):
		p.state.inventory.eat_best()


@rpc("any_peer", "call_remote", "reliable", 1)
func request_craft(recipe_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var peer := Net.sender()
	var p := _player_of(peer)
	if p == null or p.dead or not _allow(peer, &"craft", Balance.NET_CRAFT_PER_SECOND):
		return
	var r := Recipes.by_id(recipe_id)
	if r.is_empty() or r.has("place"):
		return
	Recipes.craft(r, p)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_place(kind: String, pos: Vector3, yaw: float) -> void:
	if not multiplayer.is_server():
		return
	var peer := Net.sender()
	var p := _player_of(peer)
	if p == null or p.dead or not _allow(peer, &"craft", Balance.NET_CRAFT_PER_SECOND):
		return
	var recipe := {}
	for r in Recipes.DB:
		if r.get("place", "") == kind:
			recipe = r
	if recipe.is_empty():
		return
	if not PlacementController.check_position(p, pos):
		p.state.notify("No se puede colocar aquí", 2.0)
		return
	if not Recipes.has_materials(recipe, p.state):
		p.state.notify(Recipes.STATUS_MISSING, 2.0)
		return
	for id in recipe["cost"]:
		p.state.inventory.remove(id, int(recipe["cost"][id]))
	var world: World = get_tree().get_first_node_in_group("world")
	var node := world.spawn_placed(kind, pos, yaw)
	if kind == "campfire":
		p.state.emit_sim(&"campfire_placed", [node])
		p.state.notify("Fogata colocada", 2.5)
	p.state.emit_sim(&"crafted", [recipe["id"]])
	AudioManager.play(&"place", pos)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_respawn() -> void:
	if not multiplayer.is_server():
		return
	var p := _player_of(Net.sender())
	if p != null and p.dead:
		p.respawn()


# ------------------------------------------------------------------ containers (server state, mirrored to the opener)
@rpc("any_peer", "call_remote", "reliable", 1)
func request_take(wid: int, slot: int, all: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := Net.sender()
	var p := _player_of(peer)
	var st := _storage_for(peer, wid)
	if p == null or st == null or not _allow(peer, &"container", 10.0):
		return
	p.state.inventory.take_from_container(st, slot, all)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_deposit(wid: int, slot: int, all: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := Net.sender()
	var p := _player_of(peer)
	var st := _storage_for(peer, wid)
	if p == null or st == null or not _allow(peer, &"container", 10.0):
		return
	p.state.inventory.deposit_to_container(st, slot, all)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_close_storage(wid: int) -> void:
	if not multiplayer.is_server():
		return
	var st := _storage_for(Net.sender(), wid)
	if st != null:
		close_storage(st)


func _storage_for(peer: int, wid: int) -> Storage:
	var obj := WorldRegistry.get_object(wid)
	if obj == null:
		return null
	var st: Storage = obj.get_node_or_null("Storage") as Storage if not (obj is Storage) else obj
	if st == null or st.open_by != peer:
		return null
	return st


## Server: a player opens a container (exclusion: one user at a time, ARQ v2 §10.2 of the research).
func open_storage(player: Player, st: Storage) -> void:
	var wid := WorldRegistry.wid_of(st.get_parent())
	if st.open_by != 0 and st.open_by != player.peer_id and _player_of(st.open_by) != null:
		player.state.notify(REASONS["en_uso"], 2.0)
		return
	if st.open_by != 0 and st.open_by != player.peer_id:
		st.open_by = 0
	st.open_by = player.peer_id
	st.is_open = true
	set_delta(wid, {"open_by": player.peer_id})
	Net.rpc_to(self, &"_storage_opened", player.peer_id, [wid, st.title, st.slots.duplicate(true)])


func close_storage(st: Storage) -> void:
	var peer := st.open_by
	if peer == 0:
		return
	st.open_by = 0
	st.is_open = false
	set_delta(WorldRegistry.wid_of(st.get_parent()), {"open_by": 0})
	Net.rpc_to(self, &"_storage_closed", peer, [WorldRegistry.wid_of(st.get_parent())])


## Server: called by Storage.changed while someone has it open → refresh the opener's mirror.
func push_storage(st: Storage) -> void:
	if Net.is_server and st.open_by != 0:
		Net.rpc_to(self, &"_storage_slots", st.open_by, [WorldRegistry.wid_of(st.get_parent()), st.slots.duplicate(true)])


func _physics_process(_delta: float) -> void:
	if not Net.is_server or Engine.get_physics_frames() % 30 != 0:
		return
	# containers close when their user walks away
	for n in get_tree().get_nodes_in_group("storage"):
		var st := n as Storage
		if st == null or st.open_by == 0:
			continue
		var p := _player_of(st.open_by)
		if p == null:
			close_storage(st)
			continue
		var a := st.anchor_position()
		if Vector2(a.x - p.global_position.x, a.z - p.global_position.z).length() > 3.5:
			close_storage(st)


@rpc("authority", "call_remote", "reliable", 1)
func _storage_opened(wid: int, title: String, slots: Array) -> void:
	if Net.is_dedicated:
		return
	var st := _local_storage(wid)
	if st == null:
		return
	st.title = title
	if not Net.is_server:
		st.set_slots_from(slots)   # offline: the local node already holds the authoritative slots
	st.is_open = true
	st.open_by = Net.local_peer_id()
	Events.storage_opened.emit(st)
	AudioManager.play(&"ui_open")


@rpc("authority", "call_remote", "reliable", 1)
func _storage_slots(wid: int, slots: Array) -> void:
	if Net.is_server:
		return   # dedicated: nothing to show; offline: the panel already listens to the authoritative Storage.changed
	var st := _local_storage(wid)
	if st != null:
		st.set_slots_from(slots)


@rpc("authority", "call_remote", "reliable", 1)
func _storage_closed(wid: int) -> void:
	if Net.is_dedicated:
		return
	var st := _local_storage(wid)
	if st != null:
		st.is_open = false
		st.open_by = 0
		Events.storage_closed.emit()


func _local_storage(wid: int) -> Storage:
	var obj := WorldRegistry.get_object(wid)
	if obj == null:
		return null
	return obj as Storage if obj is Storage else obj.get_node_or_null("Storage") as Storage


# ------------------------------------------------------------------ world deltas / events
## Server: merges `fields` into the object's delta, applies it locally (offline) and broadcasts it.
func set_delta(wid: int, fields: Dictionary) -> void:
	if not Net.is_server:
		return
	var d: Dictionary = deltas.get(wid, {})
	d.merge(fields, true)
	deltas[wid] = d
	Net.rpc_all(self, &"_event", [wid, fields])


@rpc("authority", "call_remote", "reliable", 1)
func _event(wid: int, fields: Dictionary) -> void:
	if Net.is_server:
		return
	var d: Dictionary = deltas.get(wid, {})
	d.merge(fields, true)
	deltas[wid] = d
	_apply_to(wid, fields)


@rpc("authority", "call_remote", "reliable", 1)
func _delta_snapshot(all: Dictionary) -> void:
	if Net.is_server:
		return
	deltas = all.duplicate(true)
	for wid in deltas:
		_apply_to(int(wid), deltas[wid])


func _apply_to(wid: int, fields: Dictionary) -> void:
	var obj := WorldRegistry.get_object(wid)
	if obj != null and obj.has_method("apply_net_delta"):
		obj.apply_net_delta(fields)


## Client-side: the delta known for an object (used by objects that spawn after the snapshot arrived).
func delta_of(wid: int) -> Dictionary:
	return deltas.get(wid, {})
