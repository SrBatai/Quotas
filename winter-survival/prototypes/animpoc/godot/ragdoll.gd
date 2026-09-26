extends SceneTree
# Ragdoll PoC: PhysicalBoneSimulator3D + PhysicalBone3D per bone (same recipe as the editor's
# "Create Physical Skeleton"), start simulation from the Walk pose, let it fall 2 s, measure + render.
const CHAINS = [["Hips", "Spine"], ["Spine", "Chest"], ["Chest", "Neck"], ["Head", ""],
	["LeftUpperArm", "LeftLowerArm"], ["LeftLowerArm", "LeftHand"], ["RightUpperArm", "RightLowerArm"],
	["RightLowerArm", "RightHand"], ["LeftUpperLeg", "LeftLowerLeg"], ["LeftLowerLeg", "LeftFoot"],
	["RightUpperLeg", "RightLowerLeg"], ["RightLowerLeg", "RightFoot"]]

func find_first(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r = find_first(c, cls)
		if r:
			return r
	return null

func make_bone(sk: Skeleton3D, bone: String, child: String) -> PhysicalBone3D:
	var bi := sk.find_bone(bone)
	var child_origin := Vector3(0, 0.22, 0)
	if child != "":
		child_origin = sk.get_bone_rest(sk.find_bone(child)).origin
	var half := child_origin.length() * 0.5
	var cap := CapsuleShape3D.new()
	cap.height = max(half * 2.0, 0.2)
	cap.radius = clamp(half * 0.45, 0.06, 0.16)
	var cs := CollisionShape3D.new()
	cs.shape = cap
	var ct := Transform3D()
	ct.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	cs.transform = ct
	var up := Vector3.UP
	if up.cross(child_origin).is_zero_approx():
		up = Vector3(0, 0, 1)
	var body_t := Transform3D()
	body_t.basis = Basis.looking_at(child_origin, up)
	body_t.origin = body_t.basis * Vector3(0, 0, -half)
	var jt := Transform3D()
	jt.origin = Vector3(0, 0, half)
	var pb := PhysicalBone3D.new()
	pb.name = "PB_" + bone
	pb.add_child(cs)
	pb.body_offset = body_t
	pb.joint_offset = jt
	pb.bone_name = bone
	pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE if bone.ends_with("UpperArm") or bone.ends_with("UpperLeg") or bone in ["Head", "Spine", "Chest"] else PhysicalBone3D.JOINT_TYPE_HINGE
	pb.mass = 4.0
	return pb

func _init():
	await process_frame
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	gs.shape = WorldBoundaryShape3D.new()
	ground.add_child(gs)
	get_root().add_child(ground)
	var inst: Node3D = load("res://models/survivor.glb").instantiate()
	get_root().add_child(inst)
	var ap: AnimationPlayer = find_first(inst, "AnimationPlayer")
	ap.play("Walk")
	ap.seek(0.2, true)
	ap.pause()
	var sk: Skeleton3D = find_first(inst, "Skeleton3D")
	var sim := PhysicalBoneSimulator3D.new()
	sk.add_child(sim)
	for c in CHAINS:
		sim.add_child(make_bone(sk, c[0], c[1]))
	await physics_frame
	var hips := sk.find_bone("Hips")
	var head := sk.find_bone("Head")
	var y0 := sk.get_bone_global_pose(hips).origin.y
	sim.physical_bones_start_simulation()
	ap.active = false
	for i in 150:
		await physics_frame
		if i % 50 == 0:
			var p: PhysicalBone3D = sim.get_node("PB_Hips")
			print("frame %d PB_Hips y=%.3f" % [i, p.global_position.y])
	var pbh: PhysicalBone3D = sim.get_node("PB_Hips")
	print("PB_Hips global y=%.2f  linear_velocity=%s  sleeping? can_sleep=%s" % [pbh.global_position.y, pbh.linear_velocity, pbh.can_sleep])
	var y1 := sk.get_bone_global_pose(hips).origin.y
	var yh := sk.get_bone_global_pose(head).origin.y
	print("RAGDOLL: bones=%d simulating=%s PB_Hips y %.2f -> %.2f (skeleton get_bone_global_pose still %.2f: modifier output is not visible through that getter outside the modifier stage)" % [sim.get_child_count(), sim.is_simulating_physics(), y0, pbh.global_position.y, y1])
	if DisplayServer.get_name() != "headless":
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color("#dfe7f0")
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color("#b9cbe3")
		e.ambient_light_energy = 0.4
		var we := WorldEnvironment.new()
		we.environment = e
		get_root().add_child(we)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-45, 60, 0)
		sun.light_energy = 0.8
		sun.shadow_enabled = true
		get_root().add_child(sun)
		var gm := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(10, 10)
		gm.mesh = pm
		get_root().add_child(gm)
		var cam := Camera3D.new()
		get_root().add_child(cam)
		cam.position = pbh.global_position + Vector3(2.2, 2.4, 2.6)
		cam.look_at(pbh.global_position)
		cam.current = true
		get_root().size = Vector2i(900, 600)
		for k in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("res://shots/ragdoll_after_2_5s.png")
		print("saved ragdoll shot")
	quit()
