extends SceneTree
# AnimationTree PoC: BlendSpace1D(Idle/Walk/Run, cyclic sync) + OneShot(Attack) filtered to the upper body.
const UPPER = ["Spine", "Chest", "Neck", "Head", "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]

func find_first(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r = find_first(c, cls)
		if r:
			return r
	return null

func make_tree(inst: Node3D) -> AnimationTree:
	var ap: AnimationPlayer = find_first(inst, "AnimationPlayer")
	var sk: Skeleton3D = find_first(inst, "Skeleton3D")
	var skel_path := String(ap.get_node(ap.root_node).get_path_to(sk))
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	for p in [["Idle", 0.0], ["Walk", 1.6], ["Run", 4.0]]:
		var a := AnimationNodeAnimation.new()
		a.animation = p[0]
		loco.add_blend_point(a, p[1])
	loco.min_space = 0.0
	loco.max_space = 6.0
	loco.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_MUTABLE
	var scale := AnimationNodeTimeScale.new()
	var atk := AnimationNodeAnimation.new()
	atk.animation = "Attack"
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.08
	shot.fadeout_time = 0.2
	shot.filter_enabled = true
	for b in UPPER:
		shot.set_filter_path(NodePath(skel_path + ":" + b), true)
	bt.add_node("loco", loco, Vector2(0, 0))
	bt.add_node("speed", scale, Vector2(200, 0))
	bt.add_node("attack", atk, Vector2(200, 200))
	bt.add_node("upper", shot, Vector2(400, 0))
	bt.connect_node("speed", 0, "loco")
	bt.connect_node("upper", 0, "speed")
	bt.connect_node("upper", 1, "attack")
	bt.connect_node("output", 0, "upper")
	var tree := AnimationTree.new()
	tree.tree_root = bt
	inst.add_child(tree)
	tree.anim_player = tree.get_path_to(ap)
	tree.root_node = tree.get_path_to(ap.get_node(ap.root_node))
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	return tree

func _init():
	await process_frame
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#dfe7f0")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#b9cbe3")
	e.ambient_light_energy = 0.4
	we.environment = e
	get_root().add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 60, 0)
	sun.light_energy = 0.9
	get_root().add_child(sun)
	var times := [0.0, 0.15, 0.30, 0.42, 0.55, 0.75]
	var trees := []
	for i in times.size():
		var inst: Node3D = load("res://models/survivor.glb").instantiate()
		inst.position = Vector3(i * 1.5, 0, 0)
		inst.rotation_degrees.y = 60
		get_root().add_child(inst)
		var sk: Skeleton3D = find_first(inst, "Skeleton3D")
		var ba := BoneAttachment3D.new()
		ba.bone_name = "RightHandSocket"
		sk.add_child(ba)
		ba.add_child(load("res://models/stone_axe.glb").instantiate())
		var tree := make_tree(inst)
		tree.set("parameters/loco/blend_position", 1.6)   # walking
		tree.set("parameters/speed/scale", 1.0)
		tree.advance(0.0)
		tree.set("parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		# advance in small steps to the sample time
		var t := 0.0
		while t < times[i] - 1e-6:
			var dt: float = min(1.0 / 30.0, times[i] - t)
			tree.advance(dt)
			t += dt
		trees.append(tree)
		print("tree %d: t=%.2f oneshot_active=%s loco_blend=%s" % [i, times[i], tree.get("parameters/upper/active"), tree.get("parameters/loco/blend_position")])
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.2
	cam.position = Vector3(3.75, 1.0, 10)
	cam.look_at(Vector3(3.75, 1.0, 0))
	cam.current = true
	get_root().size = Vector2i(1500, 480)
	for k in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://shots/tree_walk_plus_attack_upperbody.png")
	print("saved tree shot")
	quit()
