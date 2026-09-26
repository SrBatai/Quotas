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
## M4: hitstop (s left, the tree does not advance) and the time of this client's last swing (hit feedback).
var hitstop: float = 0.0
var last_swing_t: float = -10.0
var _down_label: Label3D
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
	visual.set_motion(0.0 if player.dead else _speed, player.running and not player.downed, player.crouching, player.cold, player.dead,
		player.downed, _is_reviving())
	if hitstop > 0.0:
		hitstop -= delta
	else:
		visual.advance(delta)


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
	# without the Death_A / Down_* clips (humanoid_combat.glb): tilt the model (dead on the back, downed face down)
	var clips := visual.has_down_clips
	var dead_x := 0.0 if clips else (-PI * 0.45 if player.dead else (PI * 0.42 if player.downed else 0.0))
	visual.rotation.x = lerpf(visual.rotation.x, dead_x, 1.0 - exp(-6.0 * delta))
	visual.position.y = lerpf(visual.position.y, 0.25 if player.downed and not clips else 0.0, 1.0 - exp(-6.0 * delta))
	if _label != null:
		_label.modulate.a = 0.35 if player.disconnected else 1.0
	_update_down_label()


func on_chop() -> void:
	visual.play_action(&"chop")


## A melee swing (remote players through Player.swing_seq; the owner plays its own at once on click). A charged
## swing is only known at its release: the others see it from Melee_Charged `hold_end` (the strike).
func on_swing(clip: StringName) -> void:
	visual.play_action(clip, AnimEvents.at("Melee_Charged", "hold_end", 0.72) if clip == &"Melee_Charged" else 0.0)


## Local prediction of the owner's swing (the request is on its way). A charged release lets the held wind-up go.
func play_local_swing(clip: StringName) -> void:
	last_swing_t = Time.get_ticks_msec() / 1000.0
	if clip == &"Melee_Charged" and visual.is_charging():
		visual.release_charge()
		return
	visual.cancel_charge()
	on_swing(clip)


func on_downed_changed(downed: bool) -> void:
	_update_down_label()
	if visual != null and player != null and not player.dead:
		visual.play_action(&"Down_Fall" if downed else &"Down_Revived")


## True while this survivor holds "reanimar" on someone (their `revive_by` names us).
func _is_reviving() -> bool:
	if player == null or player.get_parent() == null:
		return false
	for o in player.get_parent().get_children():
		if o is Player and (o as Player).downed and (o as Player).revive_by == player.peer_id:
			return true
	return false


## "DERRIBADO · 45 s" over any downed survivor (GDD v2 §12.3: skull + timer visible for everybody).
func _update_down_label() -> void:
	if player == null:
		return
	if not player.downed:
		if _down_label != null:
			_down_label.visible = false
		return
	if _down_label == null:
		_down_label = Label3D.new()
		_down_label.font_size = 44
		_down_label.pixel_size = 0.006
		_down_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_down_label.no_depth_test = true
		_down_label.modulate = Color("#FF6B5A")
		_down_label.outline_modulate = Color(0, 0, 0, 0.85)
		_down_label.outline_size = 10
		_down_label.position = Vector3(0, 1.4, 0)
		add_child(_down_label)
	_down_label.visible = true
	var txt := "☠ DERRIBADO · %d s" % player.bleed
	if player.revive_by != 0:
		txt = "REANIMANDO · %d %%" % player.revive_pct
	_down_label.text = txt


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
