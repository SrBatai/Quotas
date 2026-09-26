class_name CharacterVisual
extends Node3D
## Skeletal presentation of a humanoid (ARQ v2 §7, ASSET_SPEC v2 §6.5, M2 subset): one of the four survivor
## variants (chars/survivor_<jacket>.glb, GeneralSkeleton) + AnimationPlayer with the `loco` library
## (anims/humanoid_loco.glb) + an AnimationTree built here:
##
##   Transition "loco" (Idle | Cold | Walk | Run | CrouchIdle | CrouchWalk, xfade 0.12 s)
##     Walk / Run / CrouchWalk go through a TimeScale = ground speed / authored speed (2.2 / 6.0 / 1.3 m/s):
##     the dominant cycle is played at the real speed instead of blending two cycles (Opus M1 note: blending
##     between BlendSpace points slides the feet 21–75 %; the time-scaled single cycle keeps it under 2 %).
##   → Blend2 "upper" (torso filter; placeholder for the weapon-class layer of M4/M5, amount 0)
##   → OneShot "action" (torso filter): `Act_Chop`, generated from the idle pose until Opus delivers Melee2H_Swing_A
##   → output
##
## Modifiers under GeneralSkeleton: LookAtModifier3D (Head → AimTarget = the replicated aim_point). Sockets:
## BoneAttachment3D on RightHandSocket (tools) and HeadSocket (breath). Without the skeletal .glb the rigid
## `player.glb` is spawned as a static fallback (ToolSocket, BreathAnchor) and the tree stays inactive.

const VARIANTS := ["red", "blue", "green", "mustard"]
const LOCO_LIB := "res://assets/models/anims/humanoid_loco.glb"
## M4 (ASSET_SPEC v2 §6.2): Melee1H_*, Melee2H_*, Melee_Charged, Act_Shove/Stomp/Execute/Revive, Hit_*, Down_*,
## Death_A. Until the file exists (or for a clip it lacks) PoseAnim stand-ins with the same names are used.
const COMBAT_LIB := "res://assets/models/anims/humanoid_combat.glb"
const COMBAT_CLIPS := ["Melee1H_Light_A", "Melee1H_Light_B", "Melee2H_Swing_A", "Melee2H_Swing_B", "Melee_Charged",
	"Act_Shove", "Act_Stomp", "Act_Execute", "Act_Revive", "Hit_Front", "Hit_Back"]
const AUTHORED := {&"Walk": 2.2, &"Run": 6.0, &"CrouchWalk": 1.3, &"DownCrawl": 0.8}
const UPPER_BONES := ["Spine", "Chest", "Neck", "Head", "HeadSocket", "LeftShoulder", "LeftUpperArm", "LeftLowerArm",
	"LeftHand", "LeftHandSocket", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand", "RightHandSocket", "BackSocket"]
## Full-body one-shots (the torso filter would freeze the legs of a stomp / a kneeling execution).
const FULL_BODY := ["Act_Stomp", "Act_Execute", "Down_Fall", "Down_Revived", "Hit_Stagger"]
const RUN_ENTER := 4.2
const RUN_EXIT := 3.4
const MOVE_MIN := 0.25
const XFADE := 0.12

@onready var model_root: Node3D = $Model
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var tree: AnimationTree = $AnimationTree
@onready var hand_socket: BoneAttachment3D = $HandSocket
@onready var head_socket: BoneAttachment3D = $HeadSocket
@onready var breath: CPUParticles3D = $HeadSocket/Breath
@onready var aim_target: Node3D = $AimTarget

var model: Node3D
var skeleton: Skeleton3D
var look_at: LookAtModifier3D
var variant: int = 0
var is_skeletal: bool = false
## M4: the delivered combat library has the downed / death full-body clips (else PlayerView tilts the model).
var has_down_clips: bool = false
var state: StringName = &"Idle"
var speed: float = 0.0
var time_scale: float = 1.0
## Fallback sockets (rigid model).
var tool_socket: Node3D
var breath_anchor: Node3D
var _running_state: bool = false
var _look_disabled: bool = false
var _charge_hold: bool = false   # holding the Melee_Charged wind-up (owner)
var _charge_t: float = 0.0


func _ready() -> void:
	tree.active = false


## Spawns the model for `p_variant` (0 red, 1 blue, 2 green, 3 mustard) and builds the animation graph.
func setup(p_variant: int) -> void:
	variant = posmod(p_variant, VARIANTS.size())
	_clear()
	var name_glb := "chars/survivor_%s" % VARIANTS[variant]
	if Assets.force_placeholders or not Assets.has_model(name_glb):
		model = Assets.spawn_model("player")   # rigid placeholder (ToolSocket / BreathAnchor anchors)
	else:
		model = Assets.spawn_model(name_glb)
	model_root.add_child(model)
	skeleton = model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	is_skeletal = skeleton != null
	if is_skeletal:
		_setup_skeletal()
	else:
		tool_socket = model.find_child("ToolSocket", true, false)
		breath_anchor = model.find_child("BreathAnchor", true, false)
		if breath_anchor != null:
			breath.reparent(self, false)
			breath.position = model_root.transform * breath_anchor.position
		else:
			breath.position = Vector3(0, 1.52, 0.2)


func _clear() -> void:
	tree.active = false
	if look_at != null and is_instance_valid(look_at):
		look_at.queue_free()
		look_at = null
	if model != null and is_instance_valid(model):
		model_root.remove_child(model)
		model.queue_free()
	model = null
	skeleton = null
	is_skeletal = false


func _setup_skeletal() -> void:
	# AnimationPlayer resolves the `%GeneralSkeleton:Bone` tracks from the imported scene root (its unique node).
	anim_player.root_node = anim_player.get_path_to(model)
	if not anim_player.has_animation_library("loco"):
		var lib: AnimationLibrary = load(LOCO_LIB)
		if lib == null:
			push_warning("CharacterVisual: cannot load %s" % LOCO_LIB)
			return
		var own := lib.duplicate()
		own.add_animation("Act_Chop", _make_chop_animation())
		var idle := lib.get_animation("Loco_Idle")
		for n in COMBAT_CLIPS:
			own.add_animation(n, _make_combat_clip(n, idle))
		anim_player.add_animation_library("loco", own)
	if not anim_player.has_animation_library("combat") and ResourceLoader.exists(COMBAT_LIB):
		var res := load(COMBAT_LIB)
		var clib: AnimationLibrary = res as AnimationLibrary
		if clib == null and res is PackedScene:
			var inst := (res as PackedScene).instantiate()
			var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if ap != null and not ap.get_animation_library_list().is_empty():
				clib = ap.get_animation_library(ap.get_animation_library_list()[0])
			inst.free()
		if clib != null:
			anim_player.add_animation_library("combat", clib)
	has_down_clips = anim_player.has_animation("combat/Down_Idle") and anim_player.has_animation("combat/Down_Crawl") \
		and anim_player.has_animation("combat/Death_A")
	# sockets follow the animated bones (external skeleton: the attachments live outside the imported scene)
	for att in [hand_socket, head_socket]:
		att.external_skeleton = att.get_path_to(skeleton)
		att.bone_name = att.bone_name   # re-resolve the index on the new skeleton
	breath.position = Vector3(0, -0.04, 0.16)
	# head aim
	look_at = LookAtModifier3D.new()
	look_at.name = "HeadLook"
	skeleton.add_child(look_at)
	look_at.bone_name = "Head"
	look_at.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	look_at.primary_rotation_axis = 1   # Y (yaw), pitch as the secondary rotation
	look_at.use_secondary_rotation = true
	look_at.use_angle_limitation = true
	look_at.symmetry_limitation = true
	look_at.primary_limit_angle = deg_to_rad(75.0)
	look_at.secondary_limit_angle = deg_to_rad(35.0)
	look_at.duration = 0.2
	look_at.target_node = look_at.get_path_to(aim_target)
	look_at.influence = 1.0
	aim_target.global_position = global_position + global_basis * Vector3(0, 1.5, 4.0)
	# The tree is advanced by hand from PlayerView._physics_process (`advance(dt)`) right after the tick's ground
	# displacement set the TimeScale: the cycle and the body move in the same tick with the same speed (no feet
	# jitter between the 60 Hz simulation and a free-running render loop; the smoke test measures per tick).
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	tree.tree_root = _build_tree()
	tree.active = true
	_set_state(&"Idle", true)


# ------------------------------------------------------------------ animation graph
func _build_tree() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var clips := {"Idle": "loco/Loco_Idle", "Cold": "loco/Loco_Idle_Cold", "Walk": "loco/Loco_Walk", "Run": "loco/Loco_Run",
		"CrouchIdle": "loco/Crouch_Idle", "CrouchWalk": "loco/Crouch_Walk",
		# M4 full-body states: downed (still / crawling), dead (Death_A holds its last pose), reviving a teammate
		"DownIdle": "combat/Down_Idle" if has_down_clips else "loco/Loco_Idle",
		"DownCrawl": "combat/Down_Crawl" if has_down_clips else "loco/Loco_Walk",
		"Dead": "combat/Death_A" if has_down_clips else "loco/Loco_Idle",
		"Revive": "combat/Act_Revive" if anim_player.has_animation("combat/Act_Revive") else "loco/Act_Revive"}
	var names := ["Idle", "Cold", "Walk", "Run", "CrouchIdle", "CrouchWalk", "DownIdle", "DownCrawl", "Dead", "Revive"]
	for n in names:
		var a := AnimationNodeAnimation.new()
		a.animation = clips[n]
		bt.add_node("%s_anim" % n, a)
	for n in ["Walk", "Run", "CrouchWalk", "DownCrawl"]:
		bt.add_node("%s_scale" % n, AnimationNodeTimeScale.new())
		bt.connect_node("%s_scale" % n, 0, "%s_anim" % n)
	var loco := AnimationNodeTransition.new()
	loco.input_count = names.size()
	loco.xfade_time = XFADE
	loco.allow_transition_to_self = false
	for i in names.size():
		loco.set_input_name(i, names[i])
		loco.set_input_reset(i, true)
	bt.add_node("loco", loco)
	for i in names.size():
		var n: String = names[i]
		bt.connect_node("loco", i, "%s_scale" % n if AUTHORED.has(StringName(n)) else "%s_anim" % n)
	# upper-body layer placeholder (M4/M5 weapon classes): torso filter, amount 0
	var upper_pose := AnimationNodeAnimation.new()
	upper_pose.animation = "loco/Loco_Idle"
	bt.add_node("upper_pose", upper_pose)
	var upper := AnimationNodeBlend2.new()
	_filter_upper(upper)
	bt.add_node("upper", upper)
	bt.connect_node("upper", 0, "loco")
	bt.connect_node("upper", 1, "upper_pose")
	# torso actions (chop, melee swings, shove): the clip → TimeSeek (a charged swing released mid wind-up jumps to
	# Melee_Charged hold_end) → TimeScale (0 = holding the charged wind-up pose) → OneShot
	var chop := AnimationNodeAnimation.new()
	chop.animation = "loco/Act_Chop"
	bt.add_node("chop_anim", chop)
	bt.add_node("action_seek", AnimationNodeTimeSeek.new())
	bt.connect_node("action_seek", 0, "chop_anim")
	bt.add_node("action_ts", AnimationNodeTimeScale.new())
	bt.connect_node("action_ts", 0, "action_seek")
	var action := AnimationNodeOneShot.new()
	action.fadein_time = 0.05
	action.fadeout_time = 0.15
	_filter_upper(action)
	bt.add_node("action", action)
	bt.connect_node("action", 0, "upper")
	bt.connect_node("action", 1, "action_ts")
	# full-body actions (stomp, execution): unfiltered one-shot on top
	var full := AnimationNodeAnimation.new()
	full.animation = "loco/Act_Chop"
	bt.add_node("full_anim", full)
	var action_full := AnimationNodeOneShot.new()
	action_full.fadein_time = 0.08
	action_full.fadeout_time = 0.2
	bt.add_node("action_full", action_full)
	bt.connect_node("action_full", 0, "action")
	bt.connect_node("action_full", 1, "full_anim")
	# hit reactions: Hit_Front / Hit_Back are additive (delta from the rest pose, ASSET_SPEC v2 M4.2) → Add2 at
	# amount 1; the non-looping clip rests on its last key (= rest, zero delta) until the next seek to 0
	var hit := AnimationNodeAnimation.new()
	hit.animation = "combat/Hit_Front" if anim_player.has_animation("combat/Hit_Front") else "loco/Loco_Idle"
	bt.add_node("hit_anim", hit)
	bt.add_node("hit_seek", AnimationNodeTimeSeek.new())
	bt.connect_node("hit_seek", 0, "hit_anim")
	bt.add_node("hit_add", AnimationNodeAdd2.new())
	bt.connect_node("hit_add", 0, "action_full")
	bt.connect_node("hit_add", 1, "hit_seek")
	bt.connect_node("output", 0, "hit_add")
	return bt


func _filter_upper(node: AnimationNode) -> void:
	node.filter_enabled = true
	for b in UPPER_BONES:
		node.set_filter_path(NodePath("%%GeneralSkeleton:%s" % b), true)


## Placeholder chop: the idle pose with the right arm swung overhead and down (0.5 s = CHOP_COOLDOWN) and a
## forward lean. Built from the skeleton's rest so the arm axes are right whatever the retarget did.
func _make_chop_animation() -> Animation:
	var a := Animation.new()
	a.length = 0.5
	a.loop_mode = Animation.LOOP_NONE
	var lib: AnimationLibrary = load(LOCO_LIB)
	var idle := lib.get_animation("Loco_Idle")
	# pose the skeleton with idle t=0 to read the parent bases
	var idle_rot := {}
	for t in idle.get_track_count():
		if idle.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(idle.track_get_path(t)).get_slice(":", 1)
		idle_rot[bone] = idle.rotation_track_interpolate(t, 0.0)
		var bi := skeleton.find_bone(bone)
		if bi >= 0:
			skeleton.set_bone_pose_rotation(bi, idle_rot[bone])
	var upper_i := skeleton.find_bone("RightUpperArm")
	var shoulder_i := skeleton.find_bone("RightShoulder")
	var spine_i := skeleton.find_bone("Spine")
	if upper_i < 0 or shoulder_i < 0 or spine_i < 0:
		skeleton.reset_bone_poses()
		return a
	var parent_g: Basis = skeleton.get_bone_global_pose(shoulder_i).basis
	var upper_g: Basis = skeleton.get_bone_global_pose(upper_i).basis
	var spine_q: Quaternion = idle_rot.get("Spine", Quaternion.IDENTITY)
	skeleton.reset_bone_poses()
	# keys: (time, arm pitch about the character's X axis from the idle pose; negative = forward/up, spine lean)
	var keys := [[0.0, 0.0, 0.0], [0.14, -150.0, -0.12], [0.26, -35.0, 0.22], [0.5, 0.0, 0.0]]
	var t_arm := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(t_arm, NodePath("%GeneralSkeleton:RightUpperArm"))
	var t_spine := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(t_spine, NodePath("%GeneralSkeleton:Spine"))
	for k in keys:
		var swing := Basis(Vector3.RIGHT, deg_to_rad(float(k[1])))
		var local: Basis = parent_g.inverse() * (swing * upper_g)
		a.rotation_track_insert_key(t_arm, float(k[0]), local.get_rotation_quaternion())
		a.rotation_track_insert_key(t_spine, float(k[0]), spine_q * Quaternion(Vector3.RIGHT, float(k[2])))
	return a


# ------------------------------------------------------------------ per-frame drive
## `p_speed` = horizontal ground speed (local: velocity; remote: interpolation velocity).
func set_motion(p_speed: float, running: bool, crouching: bool, cold: bool, dead: bool, downed: bool = false, reviving: bool = false) -> void:
	speed = p_speed
	if not is_skeletal:
		return
	var next: StringName
	if dead:
		next = &"Dead" if has_down_clips else &"Idle"
	elif downed and has_down_clips:
		next = &"DownCrawl" if speed > MOVE_MIN else &"DownIdle"
	elif reviving:
		next = &"Revive"
	elif crouching:
		next = &"CrouchWalk" if speed > MOVE_MIN else &"CrouchIdle"
	elif speed < MOVE_MIN:
		next = &"Cold" if cold else &"Idle"
	else:
		if _running_state:
			_running_state = speed >= RUN_EXIT
		else:
			_running_state = speed >= RUN_ENTER or (running and speed >= 3.0)
		next = &"Run" if _running_state else &"Walk"
	_set_state(next)
	if AUTHORED.has(state):
		time_scale = clampf(speed / float(AUTHORED[state]), 0.3, 2.2)
		tree.set("parameters/%s_scale/scale" % state, time_scale)
	else:
		time_scale = 0.0 if dead and not has_down_clips else 1.0
	if look_at != null:
		look_at.active = not dead and not downed and not _look_disabled


## Advances the animation graph (called once per physics tick by the owner view after set_motion).
func advance(dt: float) -> void:
	if is_skeletal and tree.active:
		if _charge_hold:
			_charge_t += dt
			if _charge_t >= AnimEvents.at("Melee_Charged", "hold_start", 0.55):
				tree.set("parameters/action_ts/scale", 0.0)
		tree.advance(dt)


func _set_state(next: StringName, force: bool = false) -> void:
	if next == state and not force:
		return
	state = next
	if state != &"Run" and state != &"Walk":
		_running_state = false
	tree.set("parameters/loco/transition_request", String(state))


## World point the head looks at (aim_point).
func set_aim(point: Vector3) -> void:
	if not is_skeletal:
		return
	var eye := global_position + Vector3(0, 1.55, 0)
	var d := point - eye
	if d.length() < 0.6:
		point = eye + global_basis * Vector3(0, 0, 4.0)
	aim_target.global_position = point


func set_breathing(on: bool) -> void:
	breath.emitting = on


## Torso action: &"chop" / &"attack" (the tool swing) or a clip name of ASSET_SPEC v2 §6.2 (Melee1H_Light_A,
## Act_Shove…): the delivered `combat` library first, else the generated stand-in of the same name. Hit_Front /
## Hit_Back go to the additive layer. `from` > 0 starts the clip there (a charged swing seen by others: hold_end).
func play_action(action: StringName, from: float = 0.0) -> void:
	if not is_skeletal:
		return
	if action == &"Hit_Front" or action == &"Hit_Back":
		play_hit(action == &"Hit_Back")
		return
	_charge_hold = false
	var clip := "loco/Act_Chop"
	if action != &"chop" and action != &"attack":
		if anim_player.has_animation("combat/%s" % action):
			clip = "combat/%s" % action
		elif anim_player.has_animation("loco/%s" % action):
			clip = "loco/%s" % action
		else:
			return   # e.g. Down_Fall without humanoid_combat.glb: the model tilt of PlayerView carries it
	elif anim_player.has_animation("combat/Melee2H_Swing_A"):
		clip = "combat/Melee2H_Swing_A"
	if String(action) in FULL_BODY:
		(tree.tree_root as AnimationNodeBlendTree).get_node("full_anim").set("animation", clip)
		tree.set("parameters/action_full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		return
	(tree.tree_root as AnimationNodeBlendTree).get_node("chop_anim").set("animation", clip)
	tree.set("parameters/action_ts/scale", 1.0)
	tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if from > 0.0:
		tree.set("parameters/action_seek/seek_request", from)


## Additive flinch (a bite, a blow): Hit_Front, or Hit_Back when struck from behind.
func play_hit(from_behind: bool = false) -> void:
	if not is_skeletal or not anim_player.has_animation("combat/Hit_Front"):
		return
	var clip := "combat/Hit_Back" if from_behind and anim_player.has_animation("combat/Hit_Back") else "combat/Hit_Front"
	(tree.tree_root as AnimationNodeBlendTree).get_node("hit_anim").set("animation", clip)
	tree.set("parameters/hit_add/add_amount", 1.0)
	tree.set("parameters/hit_seek/seek_request", 0.0)


## Charged swing, owner side (ASSET_SPEC v2 M4.3): the wind-up plays while the click is held and stops on the
## Melee_Charged `hold_start` pose; `release_charge` jumps to `hold_end` and lets the strike go.
func begin_charge() -> void:
	play_action(&"Melee_Charged")
	_charge_hold = true
	_charge_t = 0.0


func is_charging() -> bool:
	return _charge_hold


func release_charge() -> void:
	if not is_skeletal:
		return
	_charge_hold = false
	tree.set("parameters/action_ts/scale", 1.0)
	tree.set("parameters/action_seek/seek_request", AnimEvents.at("Melee_Charged", "hold_end", 0.72))


## The held wind-up is dropped (weapon changed, a light swing instead): the one-shot fades out.
func cancel_charge() -> void:
	if not is_skeletal or not _charge_hold:
		return
	_charge_hold = false
	tree.set("parameters/action_ts/scale", 1.0)
	tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


## PoseAnim stand-ins for the M4 player clips (character frame: −X pitch swings an arm forward/up).
func _make_combat_clip(n: String, idle: Animation) -> Animation:
	var r := "RightUpperArm"
	var l := "LeftUpperArm"
	match n:
		"Melee1H_Light_A", "Melee1H_Light_B":
			var side := 1.0 if n.ends_with("A") else -1.0
			return PoseAnim.build(skeleton, idle, 0.55, false, [
				[0.0, {r: [Vector3.RIGHT, 0.0], "Chest": [Vector3.UP, 0.0]}],
				[0.16, {r: [[Vector3.RIGHT, -130.0], [Vector3.FORWARD, 40.0 * side]], "Chest": [Vector3.UP, 25.0 * side]}],
				[0.3, {r: [[Vector3.RIGHT, -40.0], [Vector3.FORWARD, -30.0 * side]], "Chest": [Vector3.UP, -25.0 * side]}],
				[0.55, {r: [Vector3.RIGHT, 0.0], "Chest": [Vector3.UP, 0.0]}]])
		"Melee2H_Swing_A", "Melee2H_Swing_B":
			var side := 1.0 if n.ends_with("A") else -1.0
			return PoseAnim.build(skeleton, idle, 0.9, false, [
				[0.0, {r: [Vector3.RIGHT, 0.0], l: [Vector3.RIGHT, 0.0], "Spine": [Vector3.UP, 0.0]}],
				[0.3, {r: [Vector3.RIGHT, -150.0], l: [Vector3.RIGHT, -140.0], "Spine": [Vector3.UP, 30.0 * side]}],
				[0.45, {r: [Vector3.RIGHT, -35.0], l: [Vector3.RIGHT, -40.0], "Spine": [Vector3.UP, -25.0 * side]}],
				[0.9, {r: [Vector3.RIGHT, 0.0], l: [Vector3.RIGHT, 0.0], "Spine": [Vector3.UP, 0.0]}]])
		"Melee_Charged":
			return PoseAnim.build(skeleton, idle, 1.3, false, [
				[0.0, {r: [Vector3.RIGHT, 0.0], l: [Vector3.RIGHT, 0.0], "Spine": [Vector3.RIGHT, 0.0]}],
				[0.5, {r: [Vector3.RIGHT, -170.0], l: [Vector3.RIGHT, -150.0], "Spine": [Vector3.RIGHT, -12.0]}],
				[0.8, {r: [Vector3.RIGHT, -175.0], l: [Vector3.RIGHT, -155.0], "Spine": [Vector3.RIGHT, -14.0]}],
				[0.92, {r: [Vector3.RIGHT, -30.0], l: [Vector3.RIGHT, -35.0], "Spine": [Vector3.RIGHT, 28.0]}],
				[1.3, {r: [Vector3.RIGHT, 0.0], l: [Vector3.RIGHT, 0.0], "Spine": [Vector3.RIGHT, 0.0]}]])
		"Act_Shove":
			return PoseAnim.build(skeleton, idle, 0.5, false, [
				[0.0, {r: [Vector3.RIGHT, 0.0], l: [Vector3.RIGHT, 0.0], "Spine": [Vector3.RIGHT, 0.0]}],
				[0.12, {r: [Vector3.RIGHT, -45.0], l: [Vector3.RIGHT, -45.0], "Spine": [Vector3.RIGHT, -6.0]}],
				[0.22, {r: [Vector3.RIGHT, -88.0], l: [Vector3.RIGHT, -88.0], "Spine": [Vector3.RIGHT, 16.0]}],
				[0.5, {r: [Vector3.RIGHT, 0.0], l: [Vector3.RIGHT, 0.0], "Spine": [Vector3.RIGHT, 0.0]}]])
		"Act_Stomp":
			return PoseAnim.build(skeleton, idle, 1.0, false, [
				[0.0, {"Spine": [Vector3.RIGHT, 0.0], r: [Vector3.RIGHT, 0.0], l: [Vector3.RIGHT, 0.0]}],
				[0.35, {"Spine": [Vector3.RIGHT, -10.0], r: [Vector3.RIGHT, 25.0], l: [Vector3.RIGHT, 25.0]}],
				[0.5, {"Spine": [Vector3.RIGHT, 32.0], r: [Vector3.RIGHT, -20.0], l: [Vector3.RIGHT, -20.0]}],
				[1.0, {"Spine": [Vector3.RIGHT, 0.0], r: [Vector3.RIGHT, 0.0], l: [Vector3.RIGHT, 0.0]}]])
		"Act_Execute":
			return PoseAnim.build(skeleton, idle, 1.5, false, [
				[0.0, {"Spine": [Vector3.RIGHT, 0.0], r: [Vector3.RIGHT, 0.0], l: [Vector3.RIGHT, 0.0]}],
				[0.5, {"Spine": [Vector3.RIGHT, 25.0], r: [Vector3.RIGHT, -140.0], l: [Vector3.RIGHT, -60.0]}],
				[0.75, {"Spine": [Vector3.RIGHT, 40.0], r: [Vector3.RIGHT, -35.0], l: [Vector3.RIGHT, -55.0]}],
				[1.5, {"Spine": [Vector3.RIGHT, 0.0], r: [Vector3.RIGHT, 0.0], l: [Vector3.RIGHT, 0.0]}]])
		"Act_Revive":
			return PoseAnim.build(skeleton, idle, 2.0, true, [
				[0.0, {"Spine": [Vector3.RIGHT, 48.0], r: [Vector3.RIGHT, -55.0], l: [Vector3.RIGHT, -50.0]}],
				[1.0, {"Spine": [Vector3.RIGHT, 52.0], r: [Vector3.RIGHT, -62.0], l: [Vector3.RIGHT, -44.0]}],
				[2.0, {"Spine": [Vector3.RIGHT, 48.0], r: [Vector3.RIGHT, -55.0], l: [Vector3.RIGHT, -50.0]}]])
		"Hit_Back":
			return PoseAnim.build(skeleton, idle, 0.25, false, [
				[0.0, {"Spine": [Vector3.RIGHT, 0.0]}], [0.08, {"Spine": [Vector3.RIGHT, 14.0]}], [0.25, {"Spine": [Vector3.RIGHT, 0.0]}]])
		_:
			return PoseAnim.build(skeleton, idle, 0.25, false, [
				[0.0, {"Spine": [Vector3.RIGHT, 0.0]}], [0.08, {"Spine": [Vector3.RIGHT, -14.0]}], [0.25, {"Spine": [Vector3.RIGHT, 0.0]}]])


## Node tools attach to (BoneAttachment3D on RightHandSocket, or the rigid model's ToolSocket).
func tool_parent() -> Node3D:
	if is_skeletal:
		return hand_socket
	return tool_socket


## World positions of the feet bones (tests: ankle height / sliding metric).
func foot_positions() -> Dictionary:
	var out := {}
	if skeleton == null:
		return out
	for b in ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]:
		var i := skeleton.find_bone(b)
		if i >= 0:
			out[b] = skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
	return out


func hips_height() -> float:
	if skeleton == null:
		return 0.0
	var i := skeleton.find_bone("Hips")
	return skeleton.get_bone_global_pose(i).origin.y if i >= 0 else 0.0


## Direction the head faces after the LookAtModifier3D (bone attachments see the modified pose; the skeleton's
## `get_bone_global_pose` is restored to the animation pose after the skin update).
func head_forward() -> Vector3:
	if not is_skeletal:
		return global_basis.z
	return head_socket.global_basis.z.normalized()
