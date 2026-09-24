class_name Player
extends CharacterBody3D
## The survivor: camera-relative WASD movement, auto-walk to click targets, attack, flags for stats.

@onready var stats: PlayerStats = $Stats
@onready var animator: PlayerAnimator = $Animator
@onready var interactor: Interactor = $Interactor
@onready var tool_holder: ToolHolder = $ToolHolder
@onready var placement: PlacementController = $Placement
@onready var camera_rig: CameraRig = $CameraRig
@onready var visual: Node3D = $Visual
@onready var breath: CPUParticles3D = $BreathParticles

var model: Node3D
var auto_target: InteractableComponent
var is_running: bool = false
var in_house: bool = false
var stove_on: bool = false
var torch_lit: bool = false
var move_dir: Vector3 = Vector3.ZERO
var input_enabled: bool = true
var _auto_timer: float = 0.0
var _attack_cd: float = 0.0
var _face_target: Vector3 = Vector3.INF
var _face_timer: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _spawned: bool = false


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4
	model = Assets.spawn_model("player")
	visual.add_child(model)
	animator.setup(model)
	tool_holder.setup(model)
	_setup_breath()
	Events.shelter_changed.connect(func(inside: bool) -> void: in_house = inside)
	Events.stove_changed.connect(func(lit: bool) -> void: stove_on = lit)
	Events.world_ready.connect(_snap_to_spawn)
	var world := get_tree().get_first_node_in_group("world")
	if world != null and world.is_ready:
		_snap_to_spawn()
	var stoves := get_tree().get_nodes_in_group("stove")
	if not stoves.is_empty():
		stove_on = stoves[0].is_lit


## Breath puffs (CPUParticles3D one-shot bursts, PLAN C4): parented to the visual so the direction is the
## model's front (+Z) whatever the BreathAnchor's own orientation; position taken from the anchor.
func _setup_breath() -> void:
	var anchor: Node3D = model.find_child("BreathAnchor", true, false)
	breath.amount = 6
	breath.lifetime = 1.4
	breath.explosiveness = 0.9
	breath.direction = Vector3(0, 0.3, 1)
	breath.spread = 15.0
	breath.initial_velocity_min = 0.3
	breath.initial_velocity_max = 0.5
	breath.gravity = Vector3(0, 0.15, 0)
	breath.scale_amount_min = 0.5
	breath.scale_amount_max = 0.8
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.4))
	breath.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.35))
	g.set_color(1, Color(1, 1, 1, 0.0))
	breath.color_ramp = g
	breath.mesh = FireEffect.make_quad(0.18, FireEffect.make_particle_material(false))
	breath.emitting = false
	breath.reparent(visual, false)
	if anchor != null:
		breath.position = visual.global_transform.affine_inverse() * anchor.global_position
	else:
		breath.position = Vector3(0, 1.52, 0.2)


func _snap_to_spawn() -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	global_position = world.get_spawn_point() + Vector3(0, 0.15, 0)
	visual.rotation.y = world.get_spawn_yaw()
	velocity = Vector3.ZERO
	camera_rig.snap_to_player()
	_spawned = true


func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	var input := Vector2.ZERO
	var can_move := input_enabled and GameState.is_running and not GameState.is_game_over and not get_tree().paused
	if can_move:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input != Vector2.ZERO and auto_target != null:
		auto_target = null
		interactor.pending = null
	var dir := Vector3.ZERO
	if input != Vector2.ZERO:
		dir = Vector3(input.x, 0, input.y).rotated(Vector3.UP, camera_rig.get_yaw()).normalized()
	elif auto_target != null:
		if not is_instance_valid(auto_target):
			auto_target = null
		else:
			_auto_timer += delta
			var tp := auto_target.global_position
			var flat := Vector3(tp.x - global_position.x, 0, tp.z - global_position.z)
			if flat.length() <= auto_target.interact_range * 0.9 or _auto_timer > Balance.AUTO_WALK_TIMEOUT:
				var reached := flat.length() <= auto_target.interact_range
				auto_target = null
				_auto_timer = 0.0
				if reached:
					interactor.perform_pending()
				else:
					interactor.pending = null
			else:
				dir = flat.normalized()
	if auto_target == null:
		_auto_timer = 0.0
	is_running = can_move and Input.is_action_pressed("run") and input != Vector2.ZERO and stats.hunger > 0.0
	var speed := Balance.RUN_SPEED if is_running else Balance.WALK_SPEED
	if stats.warmth < Balance.FREEZING_SLOW_BELOW:
		speed *= Balance.FREEZING_SPEED_MULT
	var target_vel := dir * speed
	velocity.x = move_toward(velocity.x, target_vel.x, Balance.ACCEL * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, Balance.ACCEL * delta)
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
	move_dir = dir
	# facing
	var face_dir := dir
	if _face_timer > 0.0:
		_face_timer -= delta
		if _face_target != Vector3.INF:
			var f := _face_target - global_position
			f.y = 0.0
			if f.length() > 0.05:
				face_dir = f.normalized()
	if face_dir.length() > 0.01:
		var target_yaw := atan2(face_dir.x, face_dir.z)  # model front = +Z (Vector3.MODEL_FRONT)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, 1.0 - exp(-Balance.TURN_SPEED * delta))
	animator.speed = Vector2(velocity.x, velocity.z).length()
	animator.running = is_running
	breath.emitting = (GameState.is_night or GameState.weather == &"blizzard") and not in_house


func _unhandled_input(event: InputEvent) -> void:
	if not GameState.is_running or GameState.is_game_over:
		return
	if event.is_action_pressed("toggle_torch"):
		Inventory.toggle_torch()
	elif event.is_action_pressed("eat"):
		Inventory.eat_best()


func face_toward(pos: Vector3) -> void:
	_face_target = pos
	_face_timer = 0.6


## World direction the survivor is looking at (the visual's +Z).
func facing() -> Vector3:
	return visual.global_basis.z


## Chop animation + face the tree (called by trees on each hit).
func play_chop(at: Vector3) -> void:
	face_toward(at)
	animator.chop()


func attack(wolf: Node) -> void:
	if _attack_cd > 0.0:
		return
	var axe := Inventory.hand_tool() == &"hacha"
	_attack_cd = Balance.AXE_COOLDOWN if axe else Balance.HAND_COOLDOWN
	animator.chop()
	if wolf != null and is_instance_valid(wolf):
		face_toward(wolf.global_position)
		var dmg := Balance.AXE_DAMAGE if axe else Balance.HAND_DAMAGE
		wolf.take_damage(dmg, self)
		Events.camera_shake.emit(0.1)


func take_damage(amount: float, source: StringName) -> void:
	stats.take_damage(amount, source)
	if source == &"lobo":
		Events.camera_shake.emit(0.35)


func is_near_fire() -> bool:
	for c in get_tree().get_nodes_in_group("heat_source"):
		if c is Node3D:
			var d := Vector2(c.global_position.x - global_position.x, c.global_position.z - global_position.z).length()
			if d <= 3.0:
				return true
	return false


func is_in_house_with_stove_on() -> bool:
	return in_house and stove_on


func drop_item(id: StringName, n: int) -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var model_name := "firewood" if id == &"madera" else ("stone" if id == &"piedra" else "stone")
	var scatter: Scatter = world.get_node("Scatter")
	for i in n:
		scatter.spawn_pickup(id, model_name, Vector2(global_position.x + randf_range(-1, 1), global_position.z + randf_range(-1, 1)))
