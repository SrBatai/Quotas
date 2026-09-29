extends SceneTree
func _init():
	for c in ["AnimationNodeBlendSpace1D", "AnimationNodeBlendSpace2D", "AnimationNodeOneShot", "AnimationNodeAnimation", "AnimationMixer"]:
		print(c, " consts: ", ClassDB.class_get_integer_constant_list(c, true))
	print("BS1D props: ", ClassDB.class_get_property_list("AnimationNodeBlendSpace1D", true).map(func(p): return p.name))
	print("NodeAnimation props: ", ClassDB.class_get_property_list("AnimationNodeAnimation", true).map(func(p): return p.name))
	quit()
