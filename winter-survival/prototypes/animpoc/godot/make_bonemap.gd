extends SceneTree
# Generates res://humanoid_bonemap.tres: identity mapping SkeletonProfileHumanoid -> our bone names.
func _init():
	var ours = ["Root","Hips","Spine","Chest","Neck","Head","LeftShoulder","LeftUpperArm","LeftLowerArm","LeftHand",
		"RightShoulder","RightUpperArm","RightLowerArm","RightHand","LeftUpperLeg","LeftLowerLeg","LeftFoot","LeftToes",
		"RightUpperLeg","RightLowerLeg","RightFoot","RightToes"]
	var bm := BoneMap.new()
	bm.profile = SkeletonProfileHumanoid.new()
	for n in ours:
		bm.set_skeleton_bone_name(n, n)
	var err = ResourceSaver.save(bm, "res://humanoid_bonemap.tres")
	print("saved bonemap err=", err, " mapped=", ours.size())
	quit()
