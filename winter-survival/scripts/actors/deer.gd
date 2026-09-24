class_name Deer
extends CharacterBody3D
## Ambient wildlife: graze, wander, flee from the player.

enum State { GRAZE, WANDER, FLEE }

@onready var steering: Steering = $Steering
@onready var animator: QuadrupedAnimator = $Animator
@onready var visual: Node3D = $Visual

var state: State = State.GRAZE
var _timer: float = 3.0
var _target: Vector3 = Vector3.INF
var _rng := RandomNumberGenerator.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	floor_max_angle = deg_to_rad(50.0)
	add_to_group("deer")
	_rng.randomize()
	var model := Assets.spawn_model("deer")
	visual.add_child(model)
	animator.setup(model)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.4
	var cs := CollisionShape3D.new()
	cs.shape = cap
	cs.rotation_degrees.x = 90.0
	cs.position = Vector3(0, 0.7, 0)
	add_child(cs)
	for pair in [["WhiskerL", 25.0], ["WhiskerR", -25.0]]:
		var ray := RayCast3D.new()
		ray.name = pair[0]
		ray.position = Vector3(0, 0.7, 0)
		ray.target_position = Vector3(0, 0, -2.5).rotated(Vector3.UP, deg_to_rad(pair[1]))
		ray.collision_mask = 1
		add_child(ray)
	steering._ready()
	_timer = _rng.randf_range(3.0, 8.0)


func _player() -> Node3D:
	var ps := get_tree().get_nodes_in_group("player")
	return ps[0] if not ps.is_empty() else null


func _physics_process(delta: float) -> void:
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
				if absf(_target.x) > Balance.BOUNDS - 4.0 or absf(_target.z) > Balance.BOUNDS - 4.0:
					_target = global_position * 0.8
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
		rotation.y = lerp_angle(rotation.y, atan2(-velocity.x, -velocity.z), 1.0 - exp(-8.0 * delta))
	animator.speed = hv.length()
	animator.running = hv.length() > 3.5
