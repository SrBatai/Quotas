extends SceneTree
func props(c):
	var out = []
	for p in ClassDB.class_get_property_list(c, true):
		if p.usage & PROPERTY_USAGE_EDITOR or p.usage & PROPERTY_USAGE_STORAGE:
			out.append(p.name)
	var m = []
	for f in ClassDB.class_get_method_list(c, true):
		m.append(f.name)
	print("== ", c, " <", ClassDB.get_parent_class(c), ">\n  props: ", out, "\n  methods: ", m)
func _init():
	for c in ["SkeletonModifier3D","IKModifier3D","ChainIK3D","IterateIK3D","TwoBoneIK3D","CCDIK3D","FABRIK3D","SplineIK3D","JacobianIK3D","LookAtModifier3D","AimModifier3D","BoneConstraint3D","CopyTransformModifier3D","ConvertTransformModifier3D","ModifierBoneTarget3D","LimitAngularVelocityModifier3D","BoneTwistDisperser3D","RetargetModifier3D","PhysicalBoneSimulator3D","SpringBoneSimulator3D","BoneAttachment3D","SkeletonIK3D","AnimationNodeBlend2","AnimationNodeOneShot","AnimationNodeBlendSpace2D","AnimationNodeStateMachine","AnimationMixer","AnimationTree","BoneMap","Skeleton3D"]:
		props(c)
	quit()
