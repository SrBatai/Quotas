class_name PlayerView
extends Node3D
## Client presentation of any player (local or remote): rigid-part model, procedural animator, tool in hand,
## footprints, breath, hover ring (local only). Remote players are placed by RemoteInterp 100 ms in the past.

var player: Player
var model: Node3D
var interp := RemoteInterp.new()
@onready var visual: Node3D = $Visual
@onready var animator: PlayerAnimator = $Animator
@onready var tool_holder: ToolHolder = $ToolHolder
@onready var footprints: Node = $FootprintEmitter
@onready var hover_ring: HoverRing = $HoverRing
@onready var breath: CPUParticles3D = $BreathParticles
var _target_yaw: float = 0.0
var _last_pos: Vector3 = Vector3.INF
var _label: Label3D


func setup(p: Player) -> void:
	player = p
	model = Assets.spawn_model("player")
	visual.add_child(model)
	animator.setup(model)
	tool_holder.setup(player, model)
	footprints.setup(player, visual)
	_setup_breath()
	_target_yaw = player.aim_yaw
	visual.rotation.y = _target_yaw
	if not player.is_local:
		hover_ring.queue_free()
		var sync: MultiplayerSynchronizer = player.get_node_or_null("ServerSync")
		if sync != null:
			sync.synchronized.connect(_on_synchronized)
		_label = Label3D.new()
		_label.text = player.display_name
		_label.font_size = 40
		_label.pixel_size = 0.006
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.modulate = Color("#DCEBFA")
		_label.outline_modulate = Color(0, 0, 0, 0.8)
		_label.outline_size = 8
		_label.position = Vector3(0, 2.05, 0)
		add_child(_label)
	on_tool_changed(player.hand_tool)
	on_dead_changed(player.dead)


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


func _on_synchronized() -> void:
	interp.push(player.net_position, player.aim_yaw, player.aim_point)


func _process(delta: float) -> void:
	if player == null:
		return
	var speed := 0.0
	if player.is_local or Net.is_server:
		speed = Vector2(player.velocity.x, player.velocity.z).length()
		_target_yaw = player.aim_yaw if not player.is_local else player.input.get("_yaw")
	else:
		var s := interp.sample()
		if s.is_empty():
			player.global_position = player.net_position
			_target_yaw = player.aim_yaw
		else:
			player.global_position = s["pos"]
			_target_yaw = float(s["yaw"])
			speed = Vector2(interp.last_velocity.x, interp.last_velocity.z).length()
	visual.rotation.y = lerp_angle(visual.rotation.y, _target_yaw, 1.0 - exp(-Balance.TURN_SPEED * delta))
	animator.speed = speed if not player.dead else 0.0
	animator.running = player.running
	breath.emitting = (WorldState.is_night_now() or WorldState.weather_now() == &"blizzard") and not player.in_house and not player.dead
	var dead_x := -PI * 0.45 if player.dead else 0.0
	visual.rotation.x = lerpf(visual.rotation.x, dead_x, 1.0 - exp(-6.0 * delta))
	if _label != null:
		_label.modulate.a = 0.35 if player.disconnected else 1.0


func on_chop() -> void:
	animator.chop()


func on_tool_changed(id: StringName) -> void:
	if tool_holder != null:
		tool_holder.apply(id)


func on_dead_changed(_dead: bool) -> void:
	pass
