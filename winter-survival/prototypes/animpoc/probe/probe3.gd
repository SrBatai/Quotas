extends SceneTree
func _init():
	var p = SkeletonProfileHumanoid.new()
	var req = []
	var opt = []
	for i in p.bone_size:
		if p.has_method("is_required") and p.is_required(i):
			req.append(p.get_bone_name(i))
		else:
			opt.append(p.get_bone_name(i))
	print("required(", req.size(), "): ", req)
	print("optional(", opt.size(), "): ", opt)
	for n in ["Root","Hips","Spine","Chest","UpperChest","Neck","Head","LeftUpperArm","LeftLowerArm","LeftHand","LeftUpperLeg","LeftLowerLeg","LeftFoot","LeftToes","LeftShoulder"]:
		var i = p.find_bone(n)
		print(n, " ref_pose=", p.get_reference_pose(i), " tail_dir=", p.get_tail_direction(i), " tail=", p.get_bone_tail(i))
	quit()
