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
const AUTHORED := {&"Walk": 2.2, &"Run": 6.0, &"CrouchWalk": 1.3}
const UPPER_BONES := ["Spine", "Chest", "Neck", "Head", "HeadSocket", "LeftShoulder", "LeftUpperArm", "LeftLowerArm",
	"LeftHand", "LeftHandSocket", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand", "RightHandSocket", "BackSocket"]
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
var state: StringName = &"Idle"
var speed: float = 0.0
var time_scale: float = 1.0
## Fallback sockets (rigid model).
var tool_socket: Node3D
var breath_anchor: Node3D
var _running_state: bool = false
var _look_disabled: bool = false


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
		anim_player.add_animation_library("loco", own)
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
	var clips := {"Idle": "Loco_Idle", "Cold": "Loco_Idle_Cold", "Walk": "Loco_Walk", "Run": "Loco_Run",
		"CrouchIdle": "Crouch_Idle", "CrouchWalk": "Crouch_Walk"}
	var names := ["Idle", "Cold", "Walk", "Run", "CrouchIdle", "CrouchWalk"]
	for n in names:
		var a := AnimationNodeAnimation.new()
		a.animation = "loco/%s" % clips[n]
		bt.add_node("%s_anim" % n, a)
	for n in ["Walk", "Run", "CrouchWalk"]:
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
	# torso actions (chop now; melee/shoot/reload later)
	var chop := AnimationNodeAnimation.new()
	chop.animation = "loco/Act_Chop"
	bt.add_node("chop_anim", chop)
	var action := AnimationNodeOneShot.new()
	action.fadein_time = 0.05
	action.fadeout_time = 0.15
	_filter_upper(action)
	bt.add_node("action", action)
	bt.connect_node("action", 0, "upper")
	bt.connect_node("action", 1, "chop_anim")
	bt.connect_node("output", 0, "action")
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
func set_motion(p_speed: float, running: bool, crouching: bool, cold: bool, dead: bool) -> void:
	speed = p_speed
	if not is_skeletal:
		return
	var next: StringName
	if dead:
		next = &"Idle"
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
		time_scale = 0.0 if dead else 1.0
	if look_at != null:
		look_at.active = not dead and not _look_disabled


## Advances the animation graph (called once per physics tick by the owner view after set_motion).
func advance(dt: float) -> void:
	if is_skeletal and tree.active:
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


## Torso action (chop / attack swing).
func play_action(action: StringName) -> void:
	if not is_skeletal:
		return
	if action == &"chop" or action == &"attack":
		tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


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
