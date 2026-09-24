class_name Wolf
extends CharacterBody3D
## Night predator state machine (GDD §12).

enum State { ROAM, STALK, CHASE, ATTACK, FLEE, LEAVE, DEAD }

const PICKUP_SCENE := preload("res://scenes/world/pickup.tscn")

@onready var health: HealthComponent = $Health
@onready var steering: Steering = $Steering
@onready var animator: QuadrupedAnimator = $Animator
@onready var interactable: InteractableComponent = $Interactable
@onready var visual: Node3D = $Visual

var state: State = State.ROAM
var player: Node3D
var _timer: float = 0.0
var _bite_cd: float = 0.0
var _flee_from: Vector3 = Vector3.ZERO
var _wander_target: Vector3 = Vector3.INF
var _stalk_dir: float = 1.0
var _stalk_radius: float = 10.0
var _rng := RandomNumberGenerator.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _model: Node3D


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	floor_max_angle = deg_to_rad(50.0)
	add_to_group("wolves")
	_rng.randomize()
	_model = Assets.spawn_model("wolf")
	visual.add_child(_model)
	animator.setup(_model)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.1
	var cs := CollisionShape3D.new()
	cs.shape = cap
	cs.rotation_degrees.x = 90.0
	cs.position = Vector3(0, 0.45, 0)
	add_child(cs)
	var sh := SphereShape3D.new()
	sh.radius = 1.0
	interactable.set_shape(sh, Vector3(0, 0.5, 0))
	interactable.interact_range = Balance.ATTACK_RANGE
	interactable.ring_radius = 0.8
	health.max_health = Balance.WOLF_HEALTH
	health.health = Balance.WOLF_HEALTH
	health.died.connect(_on_died)
	for pair in [["WhiskerL", 25.0], ["WhiskerR", -25.0]]:
		var ray := RayCast3D.new()
		ray.name = pair[0]
		ray.position = Vector3(0, 0.5, 0)
		ray.target_position = Vector3(0, 0, 2.5).rotated(Vector3.UP, deg_to_rad(pair[1]))  # whiskers ahead (+Z front)
		ray.collision_mask = 1
		ray.enabled = true
		add_child(ray)
	steering._ready()
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		player = players[0]
	_timer = _rng.randf_range(3.0, 6.0)
	_stalk_radius = _rng.randf_range(Balance.WOLF_STALK_MIN, Balance.WOLF_STALK_MAX)
	_stalk_dir = 1.0 if _rng.randf() < 0.5 else -1.0


func get_interact_label(_player: Node) -> String:
	return "Atacar lobo (hacha)" if Inventory.hand_tool() == &"hacha" else "Atacar lobo"


func can_interact(_player: Node) -> bool:
	return state != State.DEAD


func interact(p: Node) -> void:
	if p.has_method("attack"):
		p.attack(self)


func _enter(s: State) -> void:
	state = s
	match s:
		State.ROAM:
			_timer = _rng.randf_range(4.0, 8.0)
			_wander_target = Vector3.INF
		State.STALK:
			_timer = _rng.randf_range(4.0, 8.0)
			_stalk_dir = 1.0 if _rng.randf() < 0.5 else -1.0
			AudioManager.play(&"wolf_growl", global_position)
		State.FLEE:
			_timer = Balance.WOLF_FLEE_TIME
	animator.chasing = s == State.CHASE or s == State.ATTACK


func leave() -> void:
	if state != State.DEAD:
		_enter(State.LEAVE)


func _fear_source() -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for c in get_tree().get_nodes_in_group("heat_source"):
		if c is Node3D:
			var d := _dist_to(c.global_position)
			if d < Balance.CAMPFIRE_FEAR_RADIUS and d < best_d:
				best_d = d
				best = c.global_position
	if player != null and bool(player.get("torch_lit")):
		var d := _dist_to(player.global_position)
		if d < Balance.TORCH_FEAR_RADIUS and d < best_d:
			best = player.global_position
	return best


func _dist_to(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = -0.5
	_bite_cd = maxf(_bite_cd - delta, 0.0)
	if player == null or not is_instance_valid(player):
		var players := get_tree().get_nodes_in_group("player")
		player = players[0] if not players.is_empty() else null
	var desired := Vector3.ZERO
	var fear := _fear_source()
	if fear != Vector3.INF and state != State.FLEE and state != State.LEAVE:
		_flee_from = fear
		_enter(State.FLEE)
	var player_in_house: bool = player != null and bool(player.get("in_house"))
	var pdist := _dist_to(player.global_position) if player != null else INF
	match state:
		State.ROAM:
			_timer -= delta
			if player != null:
				if player_in_house:
					desired = _orbit(Vector3(0, 0, 0), 8.0, Balance.WOLF_WALK)
				else:
					if _wander_target == Vector3.INF or _dist_to(_wander_target) < 1.5:
						var ang := _rng.randf_range(0.0, TAU)
						var r := _rng.randf_range(15.0, 25.0)
						_wander_target = player.global_position + Vector3(cos(ang) * r, 0, sin(ang) * r)
					desired = steering.seek(_wander_target, Balance.WOLF_WALK)
					if _timer <= 0.0 or pdist < 14.0:
						_enter(State.STALK)
		State.STALK:
			_timer -= delta
			if player_in_house:
				_enter(State.ROAM)
			else:
				desired = _orbit(player.global_position, _stalk_radius, Balance.WOLF_WALK * 1.3)
				if _timer <= 0.0 or GameState.is_game_over:
					_enter(State.CHASE)
		State.CHASE:
			if player_in_house or GameState.is_game_over:
				_enter(State.ROAM)
			elif pdist <= Balance.WOLF_BITE_RANGE:
				_enter(State.ATTACK)
			else:
				desired = steering.seek(player.global_position, Balance.WOLF_RUN)
		State.ATTACK:
			if player_in_house or GameState.is_game_over:
				_enter(State.ROAM)
			elif pdist > Balance.WOLF_BITE_RANGE * 1.3:
				_enter(State.CHASE)
			else:
				_face(player.global_position, delta)
				if _bite_cd <= 0.0:
					_bite_cd = Balance.WOLF_BITE_COOLDOWN
					animator.lunge()
					AudioManager.play(&"wolf_bite", global_position)
					if player.has_method("take_damage"):
						player.take_damage(Balance.WOLF_BITE, &"lobo")
		State.FLEE:
			_timer -= delta
			desired = steering.flee(_flee_from, Balance.WOLF_RUN)
			if _timer <= 0.0:
				_enter(State.ROAM)
		State.LEAVE:
			var from := player.global_position if player != null else Vector3.ZERO
			desired = steering.flee(from, Balance.WOLF_RUN)
			if _dist_to(from) > Balance.WOLF_DESPAWN_DIST:
				queue_free()
				return
	if desired != Vector3.ZERO:
		desired = Steering.keep_out(global_position, desired.normalized(), Vector3.ZERO, 5.5) * desired.length()
	velocity.x = move_toward(velocity.x, desired.x, 14.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 14.0 * delta)
	move_and_slide()
	var hv := Vector2(velocity.x, velocity.z)
	if hv.length() > 0.3 and state != State.ATTACK:
		var target_yaw := atan2(velocity.x, velocity.z)  # model front = +Z
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-8.0 * delta))
	animator.speed = hv.length()
	animator.running = hv.length() > 3.5


func _orbit(center: Vector3, radius: float, speed: float) -> Vector3:
	var to_me := Steering.flat(global_position - center)
	var d := to_me.length()
	if d < 0.1:
		to_me = Vector3.MODEL_FRONT
		d = 1.0
	var radial := to_me / d
	var tangent := Vector3(-radial.z, 0, radial.x) * _stalk_dir
	var correction := radial * clampf((radius - d) * 0.4, -1.0, 1.0)
	return steering.avoid((tangent + correction).normalized()) * speed


func _face(target: Vector3, delta: float) -> void:
	var d := Steering.flat(target - global_position)
	if d.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), 1.0 - exp(-10.0 * delta))


func take_damage(amount: float, from: Node) -> void:
	if state == State.DEAD:
		return
	health.take_damage(amount, from)
	animator.hit()
	AudioManager.play(&"wolf_hurt", global_position)
	if from is Node3D:
		var away := Steering.flat(global_position - from.global_position).normalized()
		velocity += away * Balance.KNOCKBACK * 4.0
	if state != State.DEAD and _rng.randf() < Balance.WOLF_HIT_FLEE_CHANCE:
		_flee_from = from.global_position if from is Node3D else global_position
		_enter(State.FLEE)


func _on_died(_killer: Node) -> void:
	state = State.DEAD
	interactable.enabled = false
	remove_from_group("wolves")
	collision_layer = 0
	collision_mask = 1
	AudioManager.play(&"wolf_die", global_position)
	Events.wolf_died.emit(self)
	_drop(&"carne_cruda", 2)
	_drop(&"piel", 1)
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3(0.05, 0.05, 0.05), 1.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _drop(id: StringName, n: int) -> void:
	var world := get_tree().get_first_node_in_group("world")
	var parent: Node = world.get_node("Actors") if world != null else get_parent()
	for i in n:
		var p: Node3D = PICKUP_SCENE.instantiate()
		p.item_id = id
		p.model = "stone" if id == &"piel" else "firewood"
		p.model = "pelt" if id == &"piel" else "meat"
		parent.add_child(p)
		var ang := _rng.randf_range(0.0, TAU)
		var pos := global_position + Vector3(cos(ang) * 0.9, 0.0, sin(ang) * 0.9)
		if world != null:
			pos.y = world.get_height(pos.x, pos.z)
		p.global_position = pos
