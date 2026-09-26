class_name ZombieView
extends Node3D
## Client presentation of one replicated zombie (ARQ v2 §10.5), taken from ZombieClient's pool. Model =
## `zombies/zombie_<kind>_<nn>.glb` (ASSET_SPEC v2 §5.2, skinned to the humanoid skeleton); while Opus has not
## delivered it, a survivor body in zombie colours (a tinted material override) stands in, and without any
## skeletal model the rigid `player` placeholder. Animations: `anims/zombie_anims.glb` (Zom_* of ASSET_SPEC v2
## §6.3) when it exists; otherwise the survivor's `Loco_Walk/Run` time-scaled to the zombie speed under an
## upper-body layer with the arms forward (PoseAnim), plus generated attack / hit / wake clips and a
## code-driven fall for death and knockdowns. AnimationTree advanced by hand with an animation LOD: every frame
## < 30 m, 15 Hz up to 60 m, frozen beyond (ARQ v2 §10.5). Death: the clip (or the fall) then a held pose.

const ZOM_LIB := "res://assets/models/anims/zombie_anims.glb"
const LOCO_LIB := "res://assets/models/anims/humanoid_loco.glb"
const SURVIVOR := "chars/survivor_%s"
const SURVIVOR_VARIANTS := ["red", "blue", "green", "mustard"]
const UPPER_BONES := ["Spine", "Chest", "Neck", "Head", "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
## Placeholder tints (material override on the survivor stand-in) per kind; frozen = ice blue.
const TINTS := [Color(0.62, 0.72, 0.56), Color(0.70, 0.66, 0.60), Color(0.58, 0.62, 0.54), Color(0.74, 0.86, 1.0), Color(0.74, 0.76, 0.46)]
const FROZEN_TINT := Color(0.74, 0.86, 1.0)
## zombie_anims.glb clips the graph uses (ASSET_SPEC v2 M4.2); all present → no generated stand-ins.
const NEEDED_CLIPS := ["Zom_Idle_A", "Zom_Idle_B", "Zom_Shamble_A", "Zom_Shamble_B", "Zom_Shamble_C", "Zom_Shamble_D",
	"Zom_Investigate", "Zom_Run", "Zom_Run_Tired", "Zom_Crawl", "Zom_Walk_Heavy", "Zom_Frozen_Idle", "Zom_Death_A",
	"Zom_Death_B", "Zom_Crawl_Death", "Zom_Knockdown", "Zom_Alert", "Zom_Attack_A", "Zom_Attack_B", "Zom_Crawl_Grab",
	"Zom_Hit", "Zom_Wake", "Zom_Stagger", "Zom_GetUp", "Zom_Bloat_Pop"]

static var _libs: Dictionary = {}        # "zom" / "loco" -> AnimationLibrary (or null)
static var _gen_cache: Dictionary = {}   # model file -> {clip name: Animation} (generated once per skeleton)
static var _tint_mats: Dictionary = {}
static var _ice_overlay: StandardMaterial3D

var id: int = 0
var kind: int = 0
var variant: int = 0
var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var is_skeletal: bool = false
var has_zom_clips: bool = false
var is_placeholder_model: bool = true
var state: int = 0
var dead: bool = false
var frozen_look: bool = false
## Animation LOD: seconds accumulated since the last advance, advance period (0 = every frame, -1 = frozen).
var anim_period: float = 0.0
var hitstop: float = 0.0
var _acc: float = 0.0
var _loco: StringName = &""
var _fall: float = 0.0            # 0 standing … 1 on the ground (placeholder death / knockdown)
var _fall_target: float = 0.0
var _fall_dir: float = -1.0
var _pick: Area3D
var _model_root: Node3D
var _ice: Node3D                 # the frozen bodies' `Ice` mesh (null on the others)
var _head_bone: int = -1
var _head_popped: bool = false


func _init() -> void:
	_model_root = Node3D.new()
	_model_root.name = "Model"
	add_child(_model_root)
	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	add_child(anim_player)
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	add_child(tree)
	tree.anim_player = NodePath("../AnimationPlayer")
	tree.active = false


static func _lib(which: String) -> AnimationLibrary:
	if _libs.has(which):
		return _libs[which]
	var path := ZOM_LIB if which == "zom" else LOCO_LIB
	var lib: AnimationLibrary = null
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is AnimationLibrary:
			lib = res
		elif res is PackedScene:
			var inst := (res as PackedScene).instantiate()
			var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if ap != null and ap.get_animation_library_list().size() > 0:
				lib = ap.get_animation_library(ap.get_animation_library_list()[0])
			inst.free()
	_libs[which] = lib
	return lib


## Builds the model for (kind, variant). Called when the pool assigns this view to a zombie of another kind.
func setup(p_kind: int, p_variant: int) -> void:
	if model != null and kind == p_kind and variant == p_variant:
		return
	kind = p_kind
	variant = p_variant
	_clear()
	var name_glb := ZombieKinds.model_name(kind, variant)
	var first := ZombieKinds.model_name(kind, 0)
	if kind == ZombieKinds.Kind.FROZEN:
		# the frozen batch has its own bodies (walker palette + ice shards); walkers are the fallback
		var fz := "zombies/zombie_frozen_%02d" % (posmod(variant, 4) + 1)
		if Assets.has_model(fz):
			name_glb = fz
			first = "zombies/zombie_frozen_01"
	if Assets.has_model(name_glb) and not Assets.force_placeholders:
		model = Assets.spawn_model(name_glb)
		is_placeholder_model = false
	elif Assets.has_model(first) and not Assets.force_placeholders:
		model = Assets.spawn_model(first)
		is_placeholder_model = false
	else:
		var sv := SURVIVOR % SURVIVOR_VARIANTS[posmod(variant, 4)]
		if Assets.has_model(sv) and not Assets.force_placeholders:
			model = Assets.spawn_model(sv)
		else:
			model = Assets.spawn_model("player")
		is_placeholder_model = true
		_tint(model, TINTS[clampi(kind, 0, TINTS.size() - 1)])
		# silhouettes (GDD §6.1): runner thin, bloater wide, crawler prone
		match kind:
			ZombieKinds.Kind.RUNNER:
				model.scale = Vector3(0.88, 1.0, 0.88)
			ZombieKinds.Kind.BLOATER:
				model.scale = Vector3(1.4, 1.02, 1.35)
	_model_root.add_child(model)
	skeleton = model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	is_skeletal = skeleton != null
	_ice = model.find_child("Ice", true, false) as Node3D
	if _ice != null:
		_ice.visible = false
	_head_bone = skeleton.find_bone("Head") if is_skeletal else -1
	_head_popped = false
	if is_skeletal:
		_setup_tree()
	_ensure_pick()


func _clear() -> void:
	tree.active = false
	if model != null and is_instance_valid(model):
		_model_root.remove_child(model)
		model.queue_free()
	model = null
	skeleton = null
	is_skeletal = false
	_ice = null
	_head_bone = -1
	_head_popped = false
	_loco = &""
	_fall = 0.0
	_fall_target = 0.0
	_model_root.rotation = Vector3.ZERO
	_model_root.position = Vector3.ZERO
	frozen_look = false


static func _tint(root: Node, c: Color) -> void:
	var key := c.to_html()
	var m: StandardMaterial3D = _tint_mats.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_color = c
		m.roughness = 1.0
		m.metallic_specular = 0.1
		_tint_mats[key] = m
	for mi in Assets._mesh_instances(root):
		mi.material_override = m


## Frozen look. The `zombie_frozen_NN` bodies carry their own `Ice` shards (ASSET_SPEC v2 M4.1): shown while
## frozen / waking, hidden once it walks. Any other model (a walker frozen by the cold) gets a translucent overlay.
func set_frozen_look(on: bool) -> void:
	if on == frozen_look or model == null:
		return
	frozen_look = on
	if _ice != null:
		_ice.visible = on
		return
	if _ice_overlay == null:
		_ice_overlay = StandardMaterial3D.new()
		_ice_overlay.albedo_color = Color(0.78, 0.9, 1.0, 0.45)
		_ice_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ice_overlay.roughness = 0.3
		_ice_overlay.metallic_specular = 0.8
		_ice_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	for mi in Assets._mesh_instances(model):
		mi.material_overlay = _ice_overlay if on else null


func _ensure_pick() -> void:
	# cursor picking on the client (the interactor ray also meets zombies: layer 8 "zombies")
	if _pick != null:
		return
	_pick = Area3D.new()
	_pick.name = "Pick"
	_pick.collision_layer = 128
	_pick.collision_mask = 0
	_pick.monitoring = false
	_pick.monitorable = true
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	_pick.add_child(cs)
	_pick.set_meta("zombie_view", self)
	add_child(_pick)


# ------------------------------------------------------------------ animation graph
func _setup_tree() -> void:
	anim_player.root_node = anim_player.get_path_to(model)
	tree.root_node = tree.get_path_to(model)
	for l in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(l)
	var zom := _lib("zom")
	has_zom_clips = zom != null and zom.has_animation("Zom_Shamble_A")
	var own := AnimationLibrary.new()
	var loco := _lib("loco")
	if loco != null:
		for n in ["Loco_Idle", "Loco_Walk", "Loco_Run"]:
			if loco.has_animation(n):
				own.add_animation(n, loco.get_animation(n))
	if zom != null:
		for n in zom.get_animation_list():
			own.add_animation(n, zom.get_animation(n))
	var idle: Animation = loco.get_animation("Loco_Idle") if loco != null and loco.has_animation("Loco_Idle") else null
	# generated stand-ins (the upper layer and the one-shots the delivered library may lack), once per model file;
	# skipped when zombie_anims.glb has every clip the graph uses (42 model files × 5 PoseAnim builds otherwise)
	var complete := zom != null
	for n in NEEDED_CLIPS:
		if zom == null or not zom.has_animation(n):
			complete = false
	var mkey := str(model.scene_file_path) + ":" + str(model.name)
	var gen: Dictionary = _gen_cache.get(mkey, {})
	if gen.is_empty() and not complete:
		gen = {
			"Gen_Arms": _gen_arms(idle),
			"Gen_Attack_A": _gen_attack(idle, 1.0),
			"Gen_Attack_B": _gen_attack(idle, -1.0),
			"Gen_Hit": PoseAnim.build(skeleton, idle, 0.3, false, [[0.0, PoseAnim.pitch({"Spine": 18.0, "Chest": 6.0})],
				[0.08, PoseAnim.pitch({"Spine": -8.0, "Chest": -10.0})], [0.3, PoseAnim.pitch({"Spine": 18.0, "Chest": 6.0})]]),
			"Gen_Wake": _gen_wake(idle),
		}
		_gen_cache[mkey] = gen
	for n in gen:
		own.add_animation(n, gen[n])
	anim_player.add_animation_library("z", own)
	tree.tree_root = _build_tree()
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	_set_loco(&"Idle", true)


func _clip(zom_name: String, fallback: String) -> String:
	if anim_player.has_animation("z/" + zom_name):
		return "z/" + zom_name
	return "z/" + fallback


func _gen_arms(idle: Animation) -> Animation:
	var arms_fwd := {"Spine": [Vector3.RIGHT, 16.0], "Chest": [Vector3.RIGHT, 8.0], "Neck": [Vector3.RIGHT, -12.0],
		"Head": [Vector3.FORWARD, 10.0], "LeftUpperArm": [Vector3.RIGHT, -72.0], "RightUpperArm": [Vector3.RIGHT, -64.0],
		"LeftLowerArm": [Vector3.RIGHT, -12.0], "RightLowerArm": [Vector3.RIGHT, -20.0]}
	var sway := arms_fwd.duplicate()
	sway["LeftUpperArm"] = [Vector3.RIGHT, -64.0]
	sway["RightUpperArm"] = [Vector3.RIGHT, -74.0]
	sway["Head"] = [Vector3.FORWARD, -6.0]
	return PoseAnim.build(skeleton, idle, 2.0, true, [[0.0, arms_fwd], [1.0, sway], [2.0, arms_fwd]])


func _gen_attack(idle: Animation, side: float) -> Animation:
	var a0 := {"Spine": [Vector3.RIGHT, 16.0], "LeftUpperArm": [Vector3.RIGHT, -72.0], "RightUpperArm": [Vector3.RIGHT, -64.0], "Chest": [Vector3.UP, 0.0]}
	var up := {"Spine": [Vector3.RIGHT, 4.0], "LeftUpperArm": [Vector3.RIGHT, -125.0], "RightUpperArm": [Vector3.RIGHT, -120.0], "Chest": [Vector3.UP, 18.0 * side]}
	var hit := {"Spine": [Vector3.RIGHT, 34.0], "LeftUpperArm": [Vector3.RIGHT, -38.0], "RightUpperArm": [Vector3.RIGHT, -30.0], "Chest": [Vector3.UP, -22.0 * side]}
	return PoseAnim.build(skeleton, idle, 1.0, false, [[0.0, a0], [0.35, up], [0.5, hit], [1.0, a0]])


func _gen_wake(idle: Animation) -> Animation:
	var keys := []
	for k in 7:
		var s := 1.0 if k % 2 == 0 else -1.0
		keys.append([k * 0.25, {"Spine": [Vector3.RIGHT, 12.0 + 6.0 * s], "Chest": [Vector3.UP, 10.0 * s], "Head": [Vector3.FORWARD, 14.0 * s],
			"LeftUpperArm": [Vector3.RIGHT, -60.0 - 20.0 * s], "RightUpperArm": [Vector3.RIGHT, -60.0 + 20.0 * s]}])
	return PoseAnim.build(skeleton, idle, 1.5, false, keys)


func _build_tree() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var shamble := "z/Zom_Shamble_%s" % ["A", "B", "C", "D"][variant % 4]
	if not anim_player.has_animation(shamble):
		shamble = _clip("Zom_Shamble_A", "Loco_Walk")
	var death := "Zom_Crawl_Death" if kind == ZombieKinds.Kind.CRAWLER else ("Zom_Death_A" if variant % 2 == 0 else "Zom_Death_B")
	var clips := {
		"Idle": _clip("Zom_Idle_%s" % ("A" if variant % 2 == 0 else "B"), "Loco_Idle") if anim_player.has_animation("z/Zom_Idle_A") else "z/Loco_Idle",
		"Walk": shamble,
		"Investigate": _clip("Zom_Investigate", shamble.trim_prefix("z/")),
		"Run": _clip("Zom_Run", "Loco_Run"),
		"Tired": _clip("Zom_Run_Tired", "Loco_Walk"),
		"Crawl": _clip("Zom_Crawl", "Loco_Walk"),
		"Heavy": _clip("Zom_Walk_Heavy", shamble.trim_prefix("z/")),
		"Frozen": _clip("Zom_Frozen_Idle", "Gen_Arms"),
		"Dead": _clip(death, "Zom_Death_A") if anim_player.has_animation("z/Zom_Death_A") else "z/Gen_Arms",
		"Knocked": _clip("Zom_Knockdown", "Gen_Arms"),
	}
	var names := clips.keys()
	for n in names:
		var a := AnimationNodeAnimation.new()
		a.animation = clips[n]
		bt.add_node("%s_anim" % n, a)
		bt.add_node("%s_scale" % n, AnimationNodeTimeScale.new())
		if n == "Dead":
			# a view that picks up a zombie already dead jumps to the end of the clip (the body on the ground)
			bt.add_node("Dead_seek", AnimationNodeTimeSeek.new())
			bt.connect_node("Dead_seek", 0, "Dead_anim")
			bt.connect_node("Dead_scale", 0, "Dead_seek")
		else:
			bt.connect_node("%s_scale" % n, 0, "%s_anim" % n)
	var loco := AnimationNodeTransition.new()
	loco.input_count = names.size()
	loco.xfade_time = 0.18
	for i in names.size():
		loco.set_input_name(i, names[i])
		loco.set_input_reset(i, names[i] in ["Dead", "Knocked"])
	bt.add_node("loco", loco)
	for i in names.size():
		bt.connect_node("loco", i, "%s_scale" % names[i])
	# upper layer: arms forward over the borrowed survivor cycles (off once the Zom_* clips exist)
	var arms := AnimationNodeAnimation.new()
	arms.animation = "z/Gen_Arms" if anim_player.has_animation("z/Gen_Arms") else clips["Idle"]
	bt.add_node("arms", arms)
	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	for b in UPPER_BONES:
		upper.set_filter_path(NodePath("%%GeneralSkeleton:%s" % b), true)
	bt.add_node("upper", upper)
	bt.connect_node("upper", 0, "loco")
	bt.connect_node("upper", 1, "arms")
	# torso one-shot (alert while it starts running; the generated stand-ins)
	var act := AnimationNodeAnimation.new()
	act.animation = _clip("Zom_Alert", "Gen_Attack_A")
	bt.add_node("action_anim", act)
	var action := AnimationNodeOneShot.new()
	action.fadein_time = 0.06
	action.fadeout_time = 0.18
	action.filter_enabled = true
	for b in UPPER_BONES:
		action.set_filter_path(NodePath("%%GeneralSkeleton:%s" % b), true)
	bt.add_node("action", action)
	bt.connect_node("action", 0, "upper")
	bt.connect_node("action", 1, "action_anim")
	# full-body one-shot: attacks (the zombie stops to strike), wake, stagger, get up, the bloater's pop
	var full := AnimationNodeAnimation.new()
	full.animation = _clip("Zom_Attack_A", "Gen_Attack_A")
	bt.add_node("full_anim", full)
	var action_full := AnimationNodeOneShot.new()
	action_full.fadein_time = 0.08
	action_full.fadeout_time = 0.2
	bt.add_node("action_full", action_full)
	bt.connect_node("action_full", 0, "action")
	bt.connect_node("action_full", 1, "full_anim")
	# Zom_Hit is additive (ASSET_SPEC v2 M4.2: delta from the rest pose) → Add2 at amount 1, restarted by a seek
	var hit := AnimationNodeAnimation.new()
	hit.animation = _clip("Zom_Hit", "Gen_Arms")
	bt.add_node("hit_anim", hit)
	bt.add_node("hit_seek", AnimationNodeTimeSeek.new())
	bt.connect_node("hit_seek", 0, "hit_anim")
	bt.add_node("hit_add", AnimationNodeAdd2.new())
	bt.connect_node("hit_add", 0, "action_full")
	bt.connect_node("hit_add", 1, "hit_seek")
	bt.connect_node("output", 0, "hit_add")
	return bt


func _set_loco(n: StringName, force: bool = false) -> void:
	if n == _loco and not force:
		return
	_loco = n
	if is_skeletal:
		tree.set("parameters/loco/transition_request", String(n))
		var borrowed := not has_zom_clips and n in [&"Idle", &"Walk", &"Investigate", &"Run", &"Tired", &"Heavy", &"Crawl"]
		tree.set("parameters/upper/blend_amount", 1.0 if borrowed or n == &"Frozen" and not anim_player.has_animation("z/Zom_Frozen_Idle") else 0.0)


## One-shot action: &"attack_a" / &"attack_b" (the crawler's Zom_Crawl_Grab), &"hit" (additive flinch),
## &"wake", &"stagger", &"getup", &"pop" (full body) and &"alert" (torso: it keeps running).
func play_action(what: StringName) -> void:
	if not is_skeletal or dead and what != &"pop":
		return
	var clip := ""
	var full := true
	match what:
		&"attack_a", &"attack_b":
			if kind == ZombieKinds.Kind.CRAWLER:
				clip = _clip("Zom_Crawl_Grab", "Gen_Attack_A")
			else:
				clip = _clip("Zom_Attack_A", "Gen_Attack_A") if what == &"attack_a" else _clip("Zom_Attack_B", "Gen_Attack_B")
			full = has_zom_clips
		&"hit":
			if anim_player.has_animation("z/Zom_Hit"):
				tree.set("parameters/hit_add/add_amount", 1.0)
				tree.set("parameters/hit_seek/seek_request", 0.0)
				return
			clip = "z/Gen_Hit"
			full = false
		&"wake":
			clip = _clip("Zom_Wake", "Gen_Wake")
			full = has_zom_clips
		&"stagger":
			clip = _clip("Zom_Stagger", "Gen_Hit")
			full = has_zom_clips
		&"getup":
			if not anim_player.has_animation("z/Zom_GetUp"):
				return
			clip = "z/Zom_GetUp"
		&"pop":
			if not anim_player.has_animation("z/Zom_Bloat_Pop"):
				return
			clip = "z/Zom_Bloat_Pop"
		&"alert":
			if not anim_player.has_animation("z/Zom_Alert"):
				return
			clip = "z/Zom_Alert"
			full = false
	if clip == "":
		return
	var node := "full" if full else "action"
	(tree.tree_root as AnimationNodeBlendTree).get_node("%s_anim" % node).set("animation", clip)
	tree.set("parameters/%s/request" % ("action_full" if full else "action"), AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Gore-lite (ASSET_SPEC v2 M4.1): the Head bone scaled to ~0 shows the capped neck stump. Returns the HeadSocket
## transform before the burst (where gore/head_fragments goes), or an identity-basis transform at head height.
func pop_head() -> Transform3D:
	var at := Transform3D(Basis.IDENTITY, global_position + Vector3(0, 1.6, 0))
	if not is_skeletal or _head_bone < 0 or _head_popped:
		return at
	var sock := skeleton.find_bone("HeadSocket")
	if sock >= 0:
		at = skeleton.global_transform * skeleton.get_bone_global_pose(sock)
		at.basis = at.basis.orthonormalized()
	skeleton.set_bone_pose_scale(_head_bone, Vector3.ONE * 0.001)
	_head_popped = true
	return at


## Death: the clip when it exists, else a fall (placeholder) away from the blow.
func die(dir: float, instant: bool = false) -> void:
	if dead:
		return
	dead = true
	set_frozen_look(false)
	_fall_dir = 1.0 if cos(dir - rotation.y) > 0.0 else -1.0
	if is_skeletal and anim_player.has_animation("z/Zom_Death_A"):
		_set_loco(&"Dead")
		tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		tree.set("parameters/action_full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		if instant:
			tree.set("parameters/Dead_seek/seek_request", 10.0)   # clamps to the last key
		elif kind == ZombieKinds.Kind.BLOATER:
			play_action(&"pop")   # swells and bursts (0.34 s), then the fall underneath
	else:
		_fall_target = 1.0
		if instant:
			_fall = 1.0
	if _pick != null:
		_pick.collision_layer = 0


func knock(on: bool, dir: float = 0.0) -> void:
	if dead:
		return
	if on:
		_fall_dir = 1.0 if cos(dir - rotation.y) > 0.0 else -1.0
	if is_skeletal and anim_player.has_animation("z/Zom_Knockdown"):
		if on:
			_set_loco(&"Knocked")
		elif _loco == &"Knocked":
			play_action(&"getup")   # Zom_GetUp starts where Zom_Knockdown ends (lying on its back)
	else:
		_fall_target = 0.92 if on else 0.0


## Per replicated state + interpolated speed (called by ZombieClient before `advance`).
func set_motion(st: int, spd: float, tired: bool) -> void:
	state = st
	if dead:
		return
	var n: StringName = &"Idle"
	match st:
		ZombieKinds.State.FROZEN:
			n = &"Frozen"
		ZombieKinds.State.KNOCKED:
			n = &"Knocked" if (is_skeletal and anim_player.has_animation("z/Zom_Knockdown")) else &"Idle"
		_:
			if spd > 0.25:
				match kind:
					ZombieKinds.Kind.RUNNER:
						n = &"Tired" if tired else (&"Run" if spd > 3.5 else &"Walk")
					ZombieKinds.Kind.CRAWLER:
						n = &"Crawl"
					ZombieKinds.Kind.BLOATER:
						n = &"Heavy"
					_:
						n = &"Investigate" if st == ZombieKinds.State.INVESTIGATE else &"Walk"
	set_frozen_look(st == ZombieKinds.State.FROZEN or kind == ZombieKinds.Kind.FROZEN and st == ZombieKinds.State.WAKING)
	if st != ZombieKinds.State.KNOCKED and _fall_target > 0.0 and not dead:
		_fall_target = 0.0
	_set_loco(n)
	if is_skeletal:
		var authored := 1.0
		var clip_n := String(n)
		var borrowed := not has_zom_clips
		match n:
			&"Walk", &"Heavy", &"Investigate":
				authored = 2.2 if borrowed else float(ZombieKinds.row(kind)["authored"])
			&"Run":
				authored = 6.0 if borrowed else 5.5
			&"Tired":
				authored = 2.2 if borrowed else 3.0
			&"Crawl":
				authored = 2.2 if borrowed else 1.0
		var sc := 1.0
		if n in [&"Walk", &"Investigate", &"Run", &"Tired", &"Crawl", &"Heavy"]:
			sc = clampf(spd / authored, 0.3, 2.0)
		elif n == &"Frozen":
			sc = 0.0
		tree.set("parameters/%s_scale/scale" % clip_n, sc)


## Advances the tree with the animation LOD (`period` s between advances; < 0 = not at all) and the fall pose.
func advance(delta: float) -> void:
	if hitstop > 0.0:
		hitstop -= delta
		return
	# placeholder fall (death / knockdown): tilt the whole model to the ground
	if _fall != _fall_target:
		_fall = move_toward(_fall, _fall_target, delta * (2.2 if _fall_target > _fall else 1.2))
		var crawl := 1.0 if kind == ZombieKinds.Kind.CRAWLER and is_placeholder_model else 0.0
		_model_root.rotation.x = (_fall * _fall_dir * -1.45) + crawl * 1.35 * (1.0 - _fall)
		_model_root.position.y = _fall * 0.18 + crawl * 0.32 * (1.0 - _fall)
	elif kind == ZombieKinds.Kind.CRAWLER and is_placeholder_model and _fall == 0.0:
		_model_root.rotation.x = 1.35
		_model_root.position.y = 0.32
	if not is_skeletal or not tree.active or anim_period < 0.0:
		return
	_acc += delta
	if _acc < anim_period:
		return
	tree.advance(_acc)
	_acc = 0.0


func reset_for_reuse() -> void:
	dead = false
	_fall = 0.0
	_fall_target = 0.0
	_model_root.rotation = Vector3.ZERO
	_model_root.position = Vector3.ZERO
	hitstop = 0.0
	set_frozen_look(false)
	if _pick != null:
		_pick.collision_layer = 128
	if is_skeletal:
		tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		tree.set("parameters/action_full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		_set_loco(&"Idle", true)
		if _head_popped and _head_bone >= 0:
			skeleton.set_bone_pose_scale(_head_bone, Vector3.ONE)
		_head_popped = false
