class_name Deer
extends CharacterBody3D
## Ambient wildlife: graze, wander, flee from the nearest player; huntable (action `attack` → Player.attack →
## DamageResolver v0 → HealthComponent; drops raw meat). Server AI; clients interpolate the replicated body
## (ActorSpawner + ActorSync) and follow the replicated state.

enum State { GRAZE, WANDER, FLEE, DEAD }

@export var net_position: Vector3 = Vector3.ZERO
@export var net_yaw: float = 0.0
## Quantized position + yaw in one int (Packets.pack_pose): the only ALWAYS property (12 B on the wire).
@export var net_pose: int = 0:
	set(v):
		net_pose = v
		if not Net.is_server:
			var d := Packets.unpack_pose(v)
			net_position = d["pos"]
			net_yaw = d["yaw"]
@export var net_state: int = State.GRAZE:
	set(v):
		var changed := v != net_state
		net_state = v
		if changed and not Net.is_server:
			_apply_remote_state(v)

@onready var steering: Steering = $Steering
@onready var animator: QuadrupedAnimator = $Animator
@onready var visual: Node3D = $Visual
@onready var health: HealthComponent = $Health
@onready var interactable: InteractableComponent = $Interactable
@onready var footprints: FootprintEmitter = $FootprintEmitter

var state: State = State.GRAZE
var _timer: float = 3.0
var _target: Vector3 = Vector3.INF
## Where the deer spawned (wander targets drift back toward it near unloaded ground).
var _home: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	floor_max_angle = deg_to_rad(50.0)
	add_to_group("deer")
	_rng.randomize()
	if Net.has_client:
		var model := Assets.spawn_model("deer")
		visual.add_child(model)
		animator.setup(model)
		footprints.setup(self, self, Balance.FOOTPRINT_STEP * 1.1, 0.5, false)
	else:
		footprints.queue_free()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.4
	var cs := CollisionShape3D.new()
	cs.shape = cap
	cs.rotation_degrees.x = 90.0
	cs.position = Vector3(0, 0.7, 0)
	add_child(cs)
	var sh := SphereShape3D.new()
	sh.radius = 1.1
	interactable.set_shape(sh, Vector3(0, 0.7, 0))
	interactable.interact_range = Balance.ATTACK_RANGE
	interactable.ring_radius = 0.9
	interactable.default_action = &"attack"
	health.max_health = Balance.DEER_HEALTH
	health.health = Balance.DEER_HEALTH
	health.died.connect(_on_died)
	global_position = net_position
	if not Net.is_server:
		set_physics_process(false)
		collision_layer = 0
		collision_mask = 0
		_apply_remote_state(net_state)
		return
	_home = net_position
	ActorInterest.install($ActorSync, self, 60.0)   # only peers with a player within 60 m receive it
	for pair in [["WhiskerL", 25.0], ["WhiskerR", -25.0]]:
		var ray := RayCast3D.new()
		ray.name = pair[0]
		ray.position = Vector3(0, 0.7, 0)
		ray.target_position = Vector3(0, 0, 2.5).rotated(Vector3.UP, deg_to_rad(pair[1]))  # whiskers ahead (+Z front)
		ray.collision_mask = 1
		add_child(ray)
	steering._ready()
	_timer = _rng.randf_range(3.0, 8.0)


func _player() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("player"):
		if p is Player and ((p as Player).dead or (p as Player).disconnected):
			continue
		var d := Vector2((p as Node3D).global_position.x - global_position.x, (p as Node3D).global_position.z - global_position.z).length()
		if d < best_d:
			best_d = d
			best = p
	return best


func interact_actions() -> Array:
	return [&"attack"]


func get_interact_label(p: Node) -> String:
	var axe := p is Player and (p as Player).state.hand_tool() == &"hacha"
	return "Cazar ciervo (hacha)" if axe else "Atacar ciervo"


func can_interact(_player: Node) -> bool:
	return state != State.DEAD


func is_dead() -> bool:
	return state == State.DEAD


## Server only: the player's melee goes through Player.attack → DamageResolver.
func server_interact(p: Node, action: StringName, _arg: int) -> bool:
	if action != &"attack" or not p.has_method("attack"):
		return false
	return bool(p.attack(self))


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	# M3: never simulate over a chunk whose collider is not loaded (the server streams around the players)
	var world := World.instance
	if world != null and not world.has_collision_at(global_position):
		velocity = Vector3.ZERO
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = -0.5
	var desired := Vector3.ZERO
	var p := _player()
	var pdist := INF
	if p != null:
		pdist = Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
	if pdist < Balance.DEER_FLEE_RADIUS and state != State.FLEE:
		state = State.FLEE
	match state:
		State.GRAZE:
			_timer -= delta
			if _timer <= 0.0:
				state = State.WANDER
				var ang := _rng.randf_range(0.0, TAU)
				var r := _rng.randf_range(5.0, 15.0)
				_target = global_position + Vector3(cos(ang) * r, 0, sin(ang) * r)
				if not WorldConst.in_playable(_target.x, _target.z) or (World.instance != null and not World.instance.has_collision_at(_target)):
					_target = global_position.lerp(_home, 0.3)
		State.WANDER:
			desired = steering.seek(_target, 1.5)
			if Vector2(_target.x - global_position.x, _target.z - global_position.z).length() < 1.0:
				state = State.GRAZE
				_timer = _rng.randf_range(3.0, 8.0)
		State.FLEE:
			if p != null:
				desired = steering.flee(p.global_position, Balance.DEER_SPEED)
			if pdist > 25.0:
				state = State.GRAZE
				_timer = _rng.randf_range(3.0, 8.0)
	velocity.x = move_toward(velocity.x, desired.x, 16.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 16.0 * delta)
	move_and_slide()
	var hv := Vector2(velocity.x, velocity.z)
	if hv.length() > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z), 1.0 - exp(-8.0 * delta))  # model front = +Z
	net_position = global_position
	net_yaw = rotation.y
	net_pose = Packets.pack_pose(global_position, rotation.y)
	net_state = state
	if animator != null:
		animator.speed = hv.length()
		animator.running = hv.length() > 3.5


func _process(delta: float) -> void:
	if Net.is_server or animator == null or state == State.DEAD:
		return
	var prev := global_position
	global_position = global_position.lerp(net_position, 1.0 - exp(-12.0 * delta))
	rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - exp(-10.0 * delta))
	var hv := Vector2(global_position.x - prev.x, global_position.z - prev.z).length() / maxf(delta, 0.001)
	animator.speed = hv
	animator.running = hv > 3.5


func _apply_remote_state(s: int) -> void:
	state = s as State
	if s == State.DEAD:
		_die_visual()


## Server only (DamageResolver → HealthComponent).
func take_damage(amount: float, from: Node) -> void:
	if state == State.DEAD or not Net.is_server:
		return
	health.take_damage(amount, from)
	if animator != null:
		animator.hit()
	AudioManager.play(&"wolf_hurt", global_position)
	if state != State.DEAD:
		state = State.FLEE


func _on_died(_killer: Node) -> void:
	state = State.DEAD
	net_state = State.DEAD
	interactable.enabled = false
	remove_from_group("deer")
	collision_layer = 0
	collision_mask = 1
	Events.deer_died.emit(self)
	_drop(&"carne_cruda", Balance.DEER_MEAT)
	_die_visual()


func _die_visual() -> void:
	interactable.enabled = false
	if is_in_group("deer"):
		remove_from_group("deer")
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3(0.05, 0.05, 0.05), 1.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if Net.is_server:
		tw.tween_callback(queue_free)


func _drop(id: StringName, n: int) -> void:
	var world := get_tree().get_first_node_in_group("world") as World
	if world == null:
		return
	for i in n:
		var ang := _rng.randf_range(0.0, TAU)
		var pos := global_position + Vector3(cos(ang) * 0.9, 0.0, sin(ang) * 0.9)
		pos.y = world.get_height(pos.x, pos.z)
		world.spawn_drop(id, "meat", pos, 1)
