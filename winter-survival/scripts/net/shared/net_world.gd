class_name NetWorld
extends Node
## /root/Game/NetWorld: every client intention that touches the world or the player's own state travels through
## here as a validated RPC (ARQ v2 §6.6): distance + tolerance, tool, action list, rate limits and an infraction
## counter per peer (warning at half, kick at NET_INFRACTIONS_KICK). The world's divergence from the seed lives
## in one ChunkDelta per chunk (ARQ v2 §8.8): object fields are broadcast as `_event` when they change and the
## whole chunk travels as `chunk_delta_snapshot` (zstd) to late joiners; the dirty chunks are dumped by the
## persistence backend and re-applied when the server restarts. Same node path on client and server;
## offline = direct calls.
## M3 interest management (ARQ v2 §6.5): every INTEREST_PERIOD the server computes each peer's 3 × 3 chunks
## around its player; chunks entering the set send their `chunk_delta_snapshot`, `_event`s only go to peers
## whose set holds the object's chunk, and `_interest_update(entered, left)` lets the client forget the deltas
## of chunks it no longer follows (a fresh snapshot comes when they re-enter). Chunks the server hibernates
## save their delta and despawn their drops / placed structures (restored on wake).

const REASONS := {
	"lejos": "Acércate", "sin_herramienta": "Necesitas un hacha", "no_disponible": "No disponible",
	"no_existe": "Ya no está", "en_uso": "En uso por otro jugador", "muerto": "Estás muerto",
	"accion": "No puedes hacer eso", "rate": "Demasiado rápido",
}
const RATE_LIMITS := {&"interact": Balance.NET_INTERACT_PER_SECOND, &"craft": Balance.NET_CRAFT_PER_SECOND,
	&"attack": 4.0, &"hit": 4.0, &"slot": 10.0, &"container": 10.0}

static var instance: NetWorld

## chunk key -> ChunkDelta (server authoritative; clients hold the replicated part).
var chunks: Dictionary = {}
## wid -> replicated fields (index over the chunks' objects/structures tables; `delta_of` reads it).
var deltas: Dictionary = {}
## Test hook (client): number of chunk snapshots received (and their keys).
var snapshots_received: int = 0
var snapshot_keys: Dictionary = {}
## wid -> true for every felled tree known here (chunk builders bake stumps / AO from it).
var felled: Dictionary = {}
## Server: peer -> {chunk key: true} (3 × 3 interest). Client: its own interest (from _interest_update).
var interest: Dictionary = {}
var my_interest: Dictionary = {}
## Test hooks (client): events received and their wids.
var events_received: int = 0
var event_wids: Dictionary = {}
var _hibernated: Dictionary = {}    # server: chunk key -> true (drops / structures despawned)
var _interest_t: float = 0.0
var _wid_chunk: Dictionary = {}     # wid -> chunk key
var _rate: Dictionary = {}          # [peer, kind] -> Array of timestamps
var _infractions: Dictionary = {}   # peer -> count


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	if Net.is_server:
		Net.peer_left.connect(func(peer_id: int) -> void:
			_rate.erase([peer_id, &"interact"])
			_infractions.erase(peer_id)
			interest.erase(peer_id))


# ------------------------------------------------------------------ helpers (server)
func _world() -> World:
	return get_tree().get_first_node_in_group("world") as World


func _player_of(peer: int) -> Player:
	var world := _world()
	var players := world.get_node_or_null("Players") if world != null else null
	if players == null:
		return null
	return players.get_node_or_null(str(peer)) as Player


func _allow(peer: int, kind: StringName) -> bool:
	var per_second: float = float(RATE_LIMITS.get(kind, 5.0))
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


func infractions_of(peer: int) -> int:
	return int(_infractions.get(peer, 0))


func _note_infraction(peer: int, reason: String) -> void:
	_infractions[peer] = int(_infractions.get(peer, 0)) + 1
	var n: int = _infractions[peer]
	if n == int(Balance.NET_INFRACTIONS_KICK / 2) and Net.is_dedicated:
		var p := _player_of(peer)
		if p != null:
			p.state.notify("Aviso del servidor: peticiones inválidas", 4.0)
		print("[NET] peer %d warned after %d infractions (%s)" % [peer, n, reason])
	elif n == Balance.NET_INFRACTIONS_KICK and Net.is_dedicated:
		print("[NET] peer %d kicked after %d infractions (%s)" % [peer, n, reason])
		Net.kick(peer, "infractions")


func _deny(peer: int, reason: String, wid: int = 0, action: StringName = &"") -> void:
	_note_infraction(peer, reason)
	var p := _player_of(peer)
	if p != null:
		p.state.notify(REASONS.get(reason, "No puedes hacer eso"), 2.0)
		Net.rpc_to(self, &"_interact_result", peer, [wid, action, false, reason])


## Validates that `player` can perform `action` on `comp` now: distance + tolerance, tool, action, availability.
func _check_interact(player: Player, comp: InteractableComponent, action: StringName) -> String:
	if player.dead:
		return "muerto"
	if comp == null or not is_instance_valid(comp) or not comp.enabled:
		return "no_existe"
	if comp.distance_to(player) > comp.interact_range + Balance.NET_INTERACT_TOLERANCE:
		return "lejos"
	if not comp.actions().has(action):
		return "accion"
	if comp.requires_tool != &"" and player.state.hand_tool() != comp.requires_tool:
		return "sin_herramienta"
	var st := _local_storage(comp.wid())
	if st != null and st.in_use_by_other(player) and _player_of(st.open_by) != null:
		return "en_uso"
	if not comp.can_interact(player):
		return "no_disponible"
	return ""


# ------------------------------------------------------------------ world interaction
## Client → server: perform `action` (with an integer argument) on the object `wid`.
@rpc("any_peer", "call_remote", "reliable", 1)
func request_interact(wid: int, action: StringName, arg: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := Net.sender()
	var player := _player_of(peer)
	if player == null or not _allow(peer, &"interact"):
		return
	var obj := WorldRegistry.resolve(wid)   # materializes a MultiMesh tree of a loaded chunk
	if obj == null:
		_deny(peer, "no_existe", wid, action)
		return
	var comp := InteractableComponent.find_from(obj)
	var why := _check_interact(player, comp, action)
	if why != "":
		_deny(peer, why, wid, action)
		return
	player.face_toward(comp.global_position)
	var ok := comp.server_interact(player, action, arg)
	Net.rpc_to(self, &"_interact_result", peer, [wid, action, ok, ""])


## Server → owner: outcome of a request (optimistic previews are reverted on failure).
@rpc("authority", "call_remote", "reliable", 1)
func _interact_result(wid: int, action: StringName, ok: bool, reason: String) -> void:
	if Net.is_dedicated:
		return
	Events.interact_result.emit(wid, action, ok, reason)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_attack(wid: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := Net.sender()
	var player := _player_of(peer)
	if player == null or player.dead or not _allow(peer, &"attack"):
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
	if attacker == null or attacker.dead or not _allow(peer, &"hit"):
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
	if p != null and not p.dead and _allow(Net.sender(), &"slot"):
		p.state.inventory.use_slot(i)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_toggle_torch() -> void:
	if not multiplayer.is_server():
		return
	var p := _player_of(Net.sender())
	if p != null and not p.dead and _allow(Net.sender(), &"slot"):
		p.state.inventory.toggle_torch()


@rpc("any_peer", "call_remote", "reliable", 1)
func request_eat_best() -> void:
	if not multiplayer.is_server():
		return
	var p := _player_of(Net.sender())
	if p != null and not p.dead and _allow(Net.sender(), &"slot"):
		p.state.inventory.eat_best()


@rpc("any_peer", "call_remote", "reliable", 1)
func request_craft(recipe_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var peer := Net.sender()
	var p := _player_of(peer)
	if p == null or p.dead or not _allow(peer, &"craft"):
		return
	var r := Recipes.by_id(recipe_id)
	if r.is_empty() or r.has("place"):
		_note_infraction(peer, "craft:unknown")
		return
	Recipes.craft(r, p)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_place(kind: String, pos: Vector3, yaw: float) -> void:
	if not multiplayer.is_server():
		return
	var peer := Net.sender()
	var p := _player_of(peer)
	if p == null or p.dead or not _allow(peer, &"craft"):
		return
	var recipe := {}
	for r in Recipes.DB:
		if r.get("place", "") == kind:
			recipe = r
	if recipe.is_empty() or not is_finite(pos.x) or not is_finite(pos.y) or not is_finite(pos.z):
		_note_infraction(peer, "place:unknown")
		return
	if not PlacementController.check_position(p, pos):
		print("[NET] place denied peer %d: position %s" % [peer, pos.snapped(Vector3(0.1, 0.1, 0.1))])
		p.state.notify("No se puede colocar aquí", 2.0)
		return
	if not Recipes.has_materials(recipe, p.state):
		print("[NET] place denied peer %d: materials" % peer)
		p.state.notify(Recipes.STATUS_MISSING, 2.0)
		return
	print("[EVT] peer %d places %s at %s" % [peer, kind, pos.snapped(Vector3(0.1, 0.1, 0.1))])
	for id in recipe["cost"]:
		p.state.inventory.remove(id, int(recipe["cost"][id]))
	var node := _world().spawn_placed(kind, pos, wrapf(yaw, -PI, PI))
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
	if p == null or st == null or not _allow(peer, &"container"):
		return
	p.state.inventory.take_from_container(st, slot, all)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_deposit(wid: int, slot: int, all: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := Net.sender()
	var p := _player_of(peer)
	var st := _storage_for(peer, wid)
	if p == null or st == null or not _allow(peer, &"container"):
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
	var st := _local_storage(wid)
	if st == null or st.open_by != peer:
		return null
	return st


## Server: a player opens a container (mutual exclusion: one user at a time; "en uso" for the others).
func open_storage(player: Player, st: Storage) -> bool:
	var wid := st.wid()
	if st.open_by != 0 and st.open_by != player.peer_id and _player_of(st.open_by) != null:
		player.state.notify(REASONS["en_uso"], 2.0)
		return false
	st.open_by = player.peer_id
	st.is_open = true
	set_delta(wid, {"open_by": player.peer_id})
	set_container(wid, {"open_by": player.peer_id})
	Net.rpc_to(self, &"_storage_opened", player.peer_id, [wid, st.title, st.slots.duplicate(true)])
	return true


func close_storage(st: Storage) -> void:
	var peer := st.open_by
	if peer == 0:
		return
	st.open_by = 0
	st.is_open = false
	set_delta(st.wid(), {"open_by": 0})
	set_container(st.wid(), {"open_by": 0})
	Net.rpc_to(self, &"_storage_closed", peer, [st.wid()])


## Server: called by Storage.changed → refresh the opener's mirror and the persistent copy of the contents.
func push_storage(st: Storage) -> void:
	if not Net.is_server:
		return
	set_container(st.wid(), {"items": st.slots.duplicate(true)})
	if st.open_by != 0:
		Net.rpc_to(self, &"_storage_slots", st.open_by, [st.wid(), st.slots.duplicate(true)])


func _physics_process(delta: float) -> void:
	if not Net.is_server:
		return
	_interest_t -= delta
	if _interest_t <= 0.0:
		_interest_t = WorldConst.INTEREST_PERIOD
		_update_interest()
	if Engine.get_physics_frames() % 30 != 0:
		return
	# containers close when their user walks away or leaves
	for n in get_tree().get_nodes_in_group("storage"):
		var st := n as Storage
		if st == null or st.open_by == 0:
			continue
		var p := _player_of(st.open_by)
		if p == null or p.disconnected:
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


# ------------------------------------------------------------------ chunk deltas / events
func chunk_for(wid: int, hint: Node = null) -> ChunkDelta:
	var key: int
	if _wid_chunk.has(wid):
		key = int(_wid_chunk[wid])
	else:
		var node: Node = hint if hint != null else WorldRegistry.get_object(wid)
		var pos := Vector3.ZERO
		if node is Node3D and (node as Node3D).is_inside_tree():
			pos = (node as Node3D).global_position
		elif World.instance != null and World.instance.is_configured:
			var f := World.instance.streamer.find_scatter(wid)
			if not f.is_empty():
				pos = (f[0] as WorldChunk).entry_position(int(f[1]))
		key = WorldConst.key_of(pos)
		_wid_chunk[wid] = key
	var d: ChunkDelta = chunks.get(key)
	if d == null:
		d = ChunkDelta.make(WorldConst.key_cx(key), WorldConst.key_cz(key))
		chunks[key] = d
	return d


## Server: merges `fields` into the object's replicated delta and sends it to the peers that follow its chunk.
func set_delta(wid: int, fields: Dictionary, table: StringName = &"objects") -> void:
	if not Net.is_server:
		return
	var d := chunk_for(wid)
	var merged := d.merge(table, wid, fields)
	deltas[wid] = merged
	if bool(fields.get("felled", false)):
		felled[wid] = true
	var key := d.key()
	for peer in interest:
		if (interest[peer] as Dictionary).has(key):
			Net.rpc_to(self, &"_event", peer, [wid, fields])


## Server: container contents / opener (persisted, not broadcast).
func set_container(wid: int, fields: Dictionary) -> void:
	if Net.is_server:
		chunk_for(wid).merge(&"containers", wid, fields)


## Server: a placed structure exists (StructureSpawner) → persisted in the chunk of its position.
func register_structure(wid: int, data: Dictionary) -> void:
	if Net.is_server:
		chunk_for(wid, WorldRegistry.get_object(wid)).merge(&"structures", wid, data)


## Server: a replicated drop exists / was taken.
func register_drop(wid: int, data: Dictionary) -> void:
	if Net.is_server:
		chunk_for(wid, WorldRegistry.get_object(wid)).merge(&"drops", wid, data)


func erase_drop(wid: int) -> void:
	if Net.is_server and _wid_chunk.has(wid):
		chunk_for(wid).erase(&"drops", wid)


## Server: peers whose 3 × 3 interest holds the chunk of `pos` (live, from the players' positions).
func sees(peer: int, pos: Vector3) -> bool:
	if peer == 1 or peer == 0:
		return true
	var p := _player_of(peer)
	if p == null:
		return false
	return WorldConst.ring_dist(WorldConst.chunk_of(pos.x), WorldConst.chunk_of(pos.z),
		WorldConst.chunk_of(p.global_position.x), WorldConst.chunk_of(p.global_position.z)) <= WorldConst.INTEREST_RADIUS


## Server: recomputes every peer's 3 × 3 interest; entering chunks send their snapshot.
func _update_interest() -> void:
	var peers := multiplayer.get_peers() if multiplayer.multiplayer_peer != null else PackedInt32Array()
	for peer in interest.keys():
		if not peers.has(peer):
			interest.erase(peer)
	for peer in peers:
		var p := _player_of(peer)
		if p == null or p.disconnected:
			continue
		var now := {}
		for k in WorldConst.ring_keys(WorldConst.chunk_of(p.global_position.x), WorldConst.chunk_of(p.global_position.z), WorldConst.INTEREST_RADIUS):
			now[k] = true
		var old: Dictionary = interest.get(peer, {})
		var entered := PackedInt32Array()
		var left := PackedInt32Array()
		for k in now:
			if not old.has(k):
				entered.append(k)
		for k in old:
			if not now.has(k):
				left.append(k)
		interest[peer] = now
		if entered.is_empty() and left.is_empty():
			continue
		entered.sort()
		for k in entered:
			var d: ChunkDelta = chunks.get(k)
			if d != null and not d.is_empty():
				var packed := d.pack()
				Net.rpc_to(self, &"chunk_delta_snapshot", peer, [int(packed["key"]), int(packed["size"]), packed["bytes"]])
		Net.rpc_to(self, &"_interest_update", peer, [entered, left])


## Server → client: the chunks that entered / left its interest (after their snapshots).
@rpc("authority", "call_remote", "reliable", 1)
func _interest_update(entered: PackedInt32Array, left: PackedInt32Array) -> void:
	if Net.is_server:
		return
	for k in entered:
		my_interest[k] = true
	for k in left:
		my_interest.erase(k)
		forget_chunk(k)


## Client: drops what it knew about a chunk it no longer follows (the next snapshot is the truth).
func forget_chunk(key: int) -> void:
	var d: ChunkDelta = chunks.get(key)
	if d == null:
		return
	for table in [d.objects, d.structures]:
		for wid in table:
			deltas.erase(int(wid))
			felled.erase(int(wid))
			_wid_chunk.erase(int(wid))
	chunks.erase(key)


@rpc("authority", "call_remote", "reliable", 1)
func _event(wid: int, fields: Dictionary) -> void:
	if Net.is_server:
		return
	events_received += 1
	var d: Dictionary = deltas.get(wid, {})
	d.merge(fields, true)
	deltas[wid] = d
	if bool(fields.get("felled", false)):
		felled[wid] = true
	event_wids[wid] = true
	_apply_to(wid, fields, true)


## Server: every chunk with a delta goes to the peer — M2 compatibility (tools); M3 sends by interest instead.
func send_snapshots(peer: int) -> void:
	if not Net.is_server or peer == Net.local_peer_id():
		return
	var keys := chunks.keys()
	keys.sort()
	for key in keys:
		var d: ChunkDelta = chunks[key]
		if d.is_empty():
			continue
		var packed := d.pack()
		Net.rpc_to(self, &"chunk_delta_snapshot", peer, [int(packed["key"]), int(packed["size"]), packed["bytes"]])


@rpc("authority", "call_remote", "reliable", 1)
func chunk_delta_snapshot(key: int, size: int, bytes: PackedByteArray) -> void:
	if Net.is_server:
		return
	var dict := ChunkDelta.unpack(size, bytes)
	if dict.is_empty():
		return
	snapshots_received += 1
	snapshot_keys[key] = true
	var d: ChunkDelta = chunks.get(key)
	if d == null:
		d = ChunkDelta.make(WorldConst.key_cx(key), WorldConst.key_cz(key))
		chunks[key] = d
	d.merge_dict(dict)
	for table in [&"objects", &"structures"]:
		var t: Dictionary = d.get(table)
		for wid in t:
			_wid_chunk[int(wid)] = key
			var fields: Dictionary = deltas.get(int(wid), {})
			fields.merge(t[wid], true)
			deltas[int(wid)] = fields
			if bool(fields.get("felled", false)):
				felled[int(wid)] = true
			_apply_to(int(wid), fields, false)


## Applies replicated fields to the live object, or to the scatter entry of a loaded chunk (felled trees).
## `live` = a real-time event (animate), false = snapshot / restore (instant).
func _apply_to(wid: int, fields: Dictionary, live: bool = false) -> void:
	var obj := WorldRegistry.get_object(wid)
	if obj != null:
		if obj.has_method("apply_net_delta"):
			obj.apply_net_delta(fields)
		return
	if World.instance != null:
		World.instance.apply_scatter_delta(wid, fields, live)


# ------------------------------------------------------------------ server hibernation (ARQ v2 §8.5)
## Chunk leaves memory: its delta is saved, its drops / placed structures despawn (restored on wake).
func hibernate_chunk(key: int) -> void:
	if not Net.is_server:
		return
	var d: ChunkDelta = chunks.get(key)
	_hibernated[key] = true
	if d == null:
		return
	var pm := get_tree().current_scene.get_node_or_null("PlayerManager") if get_tree().current_scene != null else null
	if pm != null and pm.get("backend") != null and d.is_dirty():
		(pm.backend as PersistenceBackend).save_chunk_delta(d)
	for table in [d.structures, d.drops]:
		for wid in table:
			var n := WorldRegistry.get_object(int(wid))
			if n != null:
				n.queue_free()


## Chunk back in memory (the streamer is about to build it): respawn what hibernation despawned.
func wake_chunk(key: int) -> void:
	if not Net.is_server or not _hibernated.has(key):
		return
	_hibernated.erase(key)
	var d: ChunkDelta = chunks.get(key)
	if d == null:
		return
	if StructureSpawner.instance != null:
		StructureSpawner.instance.restore(d.structures)
	if DropSpawner.instance != null:
		DropSpawner.instance.restore(d.drops)
	for wid in d.structures:
		if deltas.has(int(wid)):
			_apply_to(int(wid), deltas[int(wid)])


func is_hibernated(key: int) -> bool:
	return _hibernated.has(key)


## The delta known for an object (objects that spawn after the snapshot arrived read it in _ready).
func delta_of(wid: int) -> Dictionary:
	return deltas.get(wid, {})


## Chunk keys that hold something (tests / admin).
func chunk_keys() -> Array[int]:
	var out: Array[int] = []
	for k in chunks:
		if not (chunks[k] as ChunkDelta).is_empty():
			out.append(int(k))
	out.sort()
	return out


# ------------------------------------------------------------------ persistence (server)
## Dumps every dirty chunk into the backend (Autosave / save-and-quit).
func save_to(backend: PersistenceBackend) -> int:
	var n := 0
	for k in chunks:
		var d: ChunkDelta = chunks[k]
		if d.is_dirty():
			backend.save_chunk_delta(d)
			n += 1
	return n


## Restores the stored chunks into the live world (server, after world_ready): objects get their fields,
## containers their contents, structures and drops are spawned again.
func load_from(backend: PersistenceBackend) -> int:
	if not Net.is_server:
		return 0
	var n := 0
	var world := World.instance
	for k in backend.chunk_keys():
		var d := backend.load_chunk_delta(WorldConst.key_cx(k), WorldConst.key_cz(k))
		if d == null:
			continue
		chunks[k] = d
		n += 1
		# drops / structures of chunks nobody is near stay stored until the streamer wakes the chunk
		var loaded := world != null and world.streamer.chunks.has(k)
		if loaded:
			if StructureSpawner.instance != null:
				StructureSpawner.instance.restore(d.structures)
			if DropSpawner.instance != null:
				DropSpawner.instance.restore(d.drops)
		else:
			_hibernated[k] = true
		for wid in d.objects:
			_wid_chunk[int(wid)] = k
			deltas[int(wid)] = d.objects[wid]
			if bool((d.objects[wid] as Dictionary).get("felled", false)):
				felled[int(wid)] = true
			_apply_to(int(wid), d.objects[wid])
		for wid in d.containers:
			_wid_chunk[int(wid)] = k
			var st := _local_storage(int(wid))
			var e: Dictionary = d.containers[wid]
			if st != null and e.has("items"):
				st.set_slots_from(e["items"])
			if e.has("open_by"):
				d.containers[wid]["open_by"] = 0   # nobody is connected after a restart
		d.clear_dirty()
	return n
