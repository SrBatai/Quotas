class_name PlayerView
extends Node3D
## Client presentation of any player (local or remote): skeletal CharacterVisual (jacket variant = replicated
## `outfit`), tool in the hand socket, footprints, breath, name label and hover ring (local only). Remote
## players are placed by RemoteInterp 100 ms in the past and animate from the interpolated velocity.

var player: Player
var interp := RemoteInterp.new()
@onready var visual: CharacterVisual = $Visual
@onready var tool_holder: ToolHolder = $ToolHolder
@onready var footprints: FootprintEmitter = $FootprintEmitter
@onready var hover_ring: HoverRing = $HoverRing
var _target_yaw: float = 0.0
var _speed: float = 0.0
var _last_tick_pos: Vector3 = Vector3.INF
var _label: Label3D
## The model root (rigid placeholder or the skeletal survivor).
var model: Node3D:
	get: return visual.model if visual != null else null


func setup(p: Player) -> void:
	player = p
	visual.setup(player.outfit)
	tool_holder.setup(player, visual)
	footprints.setup(player, visual)
	_setup_breath()
	_target_yaw = player.aim_yaw
	visual.rotation.y = _target_yaw
	if not player.is_local:
		hover_ring.queue_free()
		# remote poses arrive through the poses packet (PlayerNet.on_remote_pose → interp.push)
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


## Breath puffs (CPUParticles3D one-shot bursts, PLAN C4) from the head socket toward the model's front (+Z).
func _setup_breath() -> void:
	var breath := visual.breath
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


## The locomotion cycle is driven per physics tick from the real ground displacement (not `velocity`: on a
## slope or against an obstacle the body covers less ground than its velocity says, and the feet would slide).
## The AnimationTree advances in the physics callback right after this node, so foot and body stay coherent.
func _physics_process(delta: float) -> void:
	if player == null:
		return
	var speed := 0.0
	if player.is_local or Net.is_server:
		if _last_tick_pos != Vector3.INF:
			var d := player.global_position - _last_tick_pos
			speed = Vector2(d.x, d.z).length() / maxf(delta, 0.0001)
			if speed > Balance.RUN_SPEED * 3.0:
				speed = Vector2(player.velocity.x, player.velocity.z).length()   # teleport / respawn
		_last_tick_pos = player.global_position
		_speed = speed
	else:
		# remote: the interpolation buffer's velocity (quantized 30 Hz samples), smoothed
		speed = Vector2(interp.last_velocity.x, interp.last_velocity.z).length()
		_speed = lerpf(_speed, speed, 1.0 - exp(-14.0 * delta))
	visual.set_motion(0.0 if player.dead else _speed, player.running, player.crouching, player.cold, player.dead)


func _process(delta: float) -> void:
	if player == null:
		return
	var aim := player.aim_point
	if player.is_local or Net.is_server:
		if player.is_local:
			_target_yaw = player.input.get("_yaw")
			aim = player.input.get("_aim_point")
		else:
			_target_yaw = player.aim_yaw
	else:
		var s := interp.sample()
		if s.is_empty():
			player.global_position = player.net_position
			_target_yaw = player.aim_yaw
		else:
			player.global_position = s["pos"]
			_target_yaw = float(s["yaw"])
			aim = s["aim"]
	visual.rotation.y = lerp_angle(visual.rotation.y, _target_yaw, 1.0 - exp(-Balance.TURN_SPEED * delta))
	visual.set_aim(aim)
	visual.set_breathing((WorldState.is_night_now() or WorldState.weather_now() == &"blizzard") and not player.in_house and not player.dead)
	var dead_x := -PI * 0.45 if player.dead else 0.0
	visual.rotation.x = lerpf(visual.rotation.x, dead_x, 1.0 - exp(-6.0 * delta))
	if _label != null:
		_label.modulate.a = 0.35 if player.disconnected else 1.0


func on_chop() -> void:
	visual.play_action(&"chop")


func on_tool_changed(id: StringName) -> void:
	if tool_holder != null:
		tool_holder.apply(id)


func on_outfit_changed(v: int) -> void:
	if visual == null or player == null or visual.variant == posmod(v, CharacterVisual.VARIANTS.size()):
		return
	visual.setup(v)
	tool_holder.setup(player, visual)
	tool_holder.apply(player.hand_tool, true)


func on_dead_changed(_dead: bool) -> void:
	pass
