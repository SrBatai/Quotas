extends SceneTree
func _init():
	var mods = []
	for c in ClassDB.get_class_list():
		if ClassDB.is_parent_class(c, "SkeletonModifier3D"):
			mods.append(c)
	mods.sort()
	print("SkeletonModifier3D family: ", mods)
	var others = []
	for c in ClassDB.get_class_list():
		if c.begins_with("AnimationNode") or c.begins_with("Physical") or c.begins_with("Bone") or c.begins_with("Skeleton") or c.contains("Retarget") or c.contains("IK"):
			others.append(c)
	others.sort()
	print("Related classes: ", others)
	var p = SkeletonProfileHumanoid.new()
	var names = []
	for i in p.bone_size:
		names.append("%s(parent=%s,group=%s)" % [p.get_bone_name(i), p.get_bone_parent(i), p.get_group(i)])
	print("Humanoid bones (", p.bone_size, "): ", names)
	print("root_bone=", p.root_bone, " scale_base_bone=", p.scale_base_bone)
	quit()
