class_name Player
extends CharacterBody3D
## Player root (ARQ v2 §7). Node name = owning peer id. Replicated by ServerSync (authority = server):
## ALWAYS 30 Hz `net_position` / `aim_yaw` / `aim_point`; ON_CHANGE the public flags below. The server-only
## state lives in State/* (inventory, stats, quests, mirrored to the owner); presentation in View / Input /
## Interactor / Placement / CameraRig, stripped at runtime where they do not belong.

# --- replicated by ServerSync (written only by the server) ---
@export var net_position: Vector3 = Vector3.ZERO
@export var aim_yaw: float = 0.0
@export var aim_point: Vector3 = Vector3.ZERO
@export var display_name: String = ""
@export var hand_tool: StringName = &"":
	set(v):
		hand_tool = v
		if view != null:
			view.on_tool_changed(v)
@export var torch_lit: bool = false
@export var running: bool = false
@export var crouching: bool = false
@export var dead: bool = false:
	set(v):
		dead = v
		if view != null:
			view.on_dead_changed(v)
@export var in_house: bool = false
@export var chop_seq: int = 0:
	set(v):
		var changed := v != chop_seq
		chop_seq = v
		if changed and view != null:
			view.on_chop()
@export var speed_mult: float = 1.0
@export var can_run: bool = true
@export var disconnected: bool = false
## Jacket variant (0 red, 1 blue, 2 green, 3 mustard), assigned by the server so every peer sees the same colour.
@export var outfit: int = 0:
	set(v):
		outfit = v
		if view != null:
			view.on_outfit_changed(v)
## Warmth below the cold threshold (server) → shivering idle on every client.
@export var cold: bool = false

var peer_id: int = 1
var is_local: bool = false
var token_hash: String = ""
var pending_profile: Dictionary = {}
var stove_on: bool = false
## World-space move direction of the last command (camera look-ahead).
var move_dir: Vector3 = Vector3.ZERO
var input_enabled: bool = true:
	set(v):
		input_enabled = v
		if input != null:
			input.enabled = v

@onready var state: PlayerState = $State
@onready var net: PlayerNet = $Net
var view: PlayerView
var input: PlayerInput
var interactor: Interactor
var placement: PlacementController
var camera_rig: CameraRig
var model: Node3D:
	get: return view.model if view != null else null
var tool_holder: ToolHolder:
	get: return view.tool_holder if view != null else null
## Server-side stats component (null on a pure client; the mirror lives in `state`).
var stats: StatsComponent:
	get: return state.stats if state != null else null
var auto_target: InteractableComponent:
	get: return input.auto_target if input != null else null
	set(v):
		if input != null:
			input.auto_target = v

var _attack_cd: float = 0.0


func _enter_tree() -> void:
	# Children read these in their own _ready (which runs before ours).
	peer_id = str(name).to_int()
	if peer_id == 0:
		peer_id = 1
	is_local = Net.has_client and peer_id == Net.local_peer_id()


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4
	position = net_position
	velocity = Vector3.ZERO
	view = get_node_or_null("View")
	input = get_node_or_null("Input")
	interactor = get_node_or_null("Interactor")
	placement = get_node_or_null("Placement")
	camera_rig = get_node_or_null("CameraRig")
	if not Net.has_client:
		_strip([view, input, interactor, placement, camera_rig])
		view = null
		input = null
		interactor = null
		placement = null
		camera_rig = null
	elif not is_local:
		_strip([input, interactor, placement, camera_rig])
		input = null
		interactor = null
		placement = null
		camera_rig = null
	if view != null:
		view.setup(self)
	# M3 interest (ARQ v2 §6.5): other peers only get this player while it is in their 3 × 3 chunks
	if Net.is_dedicated:
		var sync := get_node_or_null("ServerSync") as MultiplayerSynchronizer
		if sync != null:
			sync.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_PHYSICS
			# peer 0 = "everyone": answer false so the replication interface asks peer by peer (true would take its
			# visible-to-all fast path and never despawn anything)
			sync.add_visibility_filter(func(for_peer: int) -> bool:
				if for_peer == 0:
					return false
				return for_peer == peer_id or for_peer == 1 or NetWorld.instance == null or NetWorld.instance.sees(for_peer, global_position))
	# M3: the chunks under a simulated body must exist before it moves (spawn / restored profile far away)
	if (Net.is_server or is_local) and World.instance != null:
		World.instance.ensure_area(position, 1)
	if Net.is_server:
		state.server_setup()
		Events.stove_changed.connect(func(lit: bool) -> void: stove_on = lit)
		var stoves := get_tree().get_nodes_in_group("stove")
		if not stoves.is_empty():
			stove_on = stoves[0].is_lit
	if is_local:
		camera_rig.snap_to_player()
		Events.local_player_ready.emit(self)


func _strip(nodes: Array) -> void:
	for n in nodes:
		if n != null:
			remove_child(n)
			n.queue_free()


func _physics_process(delta: float) -> void:
	if Net.is_server:
		_attack_cd = maxf(_attack_cd - delta, 0.0)


## World direction the survivor is looking at (the model's +Z after the replicated yaw).
func facing() -> Vector3:
	return Vector3(sin(aim_yaw), 0.0, cos(aim_yaw))


## Owner client: turn toward a point for a moment (interaction); travels to the server in the next command.
func face_toward(pos: Vector3) -> void:
	if input != null:
		input.face_toward(pos)


## Chop animation + face the tree (called by trees on each hit, server side).
func play_chop(at: Vector3) -> void:
	face_toward(at)
	chop_seq += 1


## Server: melee attack on an animal (null = swing in the air). Returns true when a swing happened.
func attack(target: Node) -> bool:
	if not Net.is_server or _attack_cd > 0.0 or dead:
		return false
	var axe := state.hand_tool() == &"hacha"
	_attack_cd = Balance.AXE_COOLDOWN if axe else Balance.HAND_COOLDOWN
	chop_seq += 1
	if target != null and is_instance_valid(target) and target.has_method("take_damage"):
		face_toward(target.global_position)
		var dmg := Balance.AXE_DAMAGE if axe else Balance.HAND_DAMAGE
		var kind := DamageResolver.DamageKind.MELEE_SHARP if axe else DamageResolver.DamageKind.MELEE_BLUNT
		var res := DamageResolver.apply(DamageResolver.ref(DamageResolver.Kind.PLAYER, peer_id),
			DamageResolver.ref(DamageResolver.Kind.ANIMAL), target, dmg, kind, WorldState.rules_now(), self)
		if not bool(res["blocked"]) and target is CharacterBody3D:
			(target as CharacterBody3D).velocity += res["knockback"] as Vector3
		fx(&"shake", 0.1)
	return true


## Server: damage from wolves / other players (through DamageResolver).
func take_damage(amount: float, source: StringName) -> void:
	if not Net.is_server or state.stats == null:
		return
	state.stats.take_damage(amount, source)
	if source == &"lobo":
		fx(&"shake", 0.35)


## Server → owner presentation effect (camera shake, sounds).
func fx(kind: StringName, value: float) -> void:
	Net.rpc_to(net, &"_fx", peer_id, [kind, value])


func is_near_fire() -> bool:
	for c in get_tree().get_nodes_in_group("heat_source"):
		if c is Node3D:
			var d := Vector2(c.global_position.x - global_position.x, c.global_position.z - global_position.z).length()
			if d <= 3.0:
				return true
	return false


func is_in_house_with_stove_on() -> bool:
	return in_house and stove_on


## Server: overflow from crafting lands on the ground as drops.
func drop_item(id: StringName, n: int) -> void:
	var world := get_tree().get_first_node_in_group("world") as World
	if world == null:
		return
	var model_name := "firewood" if id == &"madera" else "stone"
	for i in n:
		var p := Vector2(global_position.x + randf_range(-1, 1), global_position.z + randf_range(-1, 1))
		world.spawn_drop(id, model_name, Vector3(p.x, world.get_height(p.x, p.y), p.y), 1)


func sim_params() -> Dictionary:
	return {"can_run": can_run, "speed_mult": speed_mult}


## Server: back to the spawn with fresh stats (persistent world: no game over, ARQ v2 §11.5 simplified).
func respawn() -> void:
	if not Net.is_server:
		return
	var world := get_tree().get_first_node_in_group("world") as World
	if world != null:
		net_position = world.get_spawn_point() + Vector3(0, 0.15, 0)
		position = net_position
		velocity = Vector3.ZERO
	state.stats.revive()
	dead = false
	state.dead = false
	state.death_cause = &""
	state.mark(&"dead")
	state.mark(&"stats")
	print("[EVT] player %d respawned" % peer_id)


# ------------------------------------------------------------------ persistence (server)
func to_profile() -> Dictionary:
	var inv := []
	for s in state.slots:
		inv.append({} if s.is_empty() else {"id": String(s["id"]), "count": int(s["count"])})
	return {"name": display_name, "x": position.x, "y": position.y, "z": position.z, "yaw": aim_yaw, "outfit": outfit,
		"health": state.health, "warmth": state.warmth, "hunger": state.hunger, "dead": dead,
		"cause": String(state.death_cause), "has_coat": state.has_coat, "slots": inv,
		"torch": state.torch_seconds_left, "quest": state.quests.to_profile() if state.quests != null else {}}


func apply_profile(p: Dictionary) -> void:
	if p.is_empty():
		return
	state.health = float(p.get("health", Balance.HEALTH_MAX))
	state.warmth = float(p.get("warmth", Balance.WARMTH_START))
	state.hunger = float(p.get("hunger", Balance.HUNGER_START))
	state.has_coat = bool(p.get("has_coat", false))
	state.torch_seconds_left = float(p.get("torch", Balance.TORCH_DURATION))
	dead = bool(p.get("dead", false))
	state.dead = dead
	state.death_cause = StringName(str(p.get("cause", "")))
	var inv: Array = p.get("slots", [])
	for i in mini(inv.size(), state.slots.size()):
		var e: Dictionary = inv[i]
		state.slots[i] = {} if e.is_empty() else {"id": StringName(str(e["id"])), "count": int(e["count"])}
	if state.inventory != null:
		state.inventory.after_load()
	if state.quests != null:
		state.quests.from_profile(p.get("quest", {}))
