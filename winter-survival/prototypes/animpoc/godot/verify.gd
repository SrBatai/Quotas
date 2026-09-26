extends SceneTree
# usage: godot --headless --path . -s verify.gd -- res://models/x.glb [res://anim_library.glb]
func dump_tree(n: Node, depth := 0):
	var extra := ""
	if n is Skeleton3D:
		extra = " bones=%d motion_scale=%.3f" % [n.get_bone_count(), n.motion_scale]
	elif n is MeshInstance3D:
		extra = " surfaces=%d skin=%s skeleton=%s" % [n.mesh.get_surface_count(), n.skin != null, n.skeleton]
	elif n is AnimationPlayer:
		extra = " libs=%s" % [n.get_animation_library_list()]
	print("  ".repeat(depth), "- ", n.name, " <", n.get_class(), ">", extra)
	for c in n.get_children():
		dump_tree(c, depth + 1)

func find_first(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r = find_first(c, cls)
		if r:
			return r
	return null

func _init():
	var args = OS.get_cmdline_user_args()
	var path = args[0]
	var res = load(path)
	if res == null:
		print("LOAD FAILED ", path)
		quit(1)
		return
	var scene: Node = res.instantiate()
	get_root().add_child(scene)
	print("== ", path)
	dump_tree(scene)
	var sk: Skeleton3D = find_first(scene, "Skeleton3D")
	var names = []
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
	print("bones(", sk.get_bone_count(), "): ", names)
	var ap: AnimationPlayer = find_first(scene, "AnimationPlayer")
	var LOOP = ["NONE", "LINEAR", "PINGPONG"]
	if ap:
		for lib_name in ap.get_animation_library_list():
			var lib = ap.get_animation_library(lib_name)
			for an in lib.get_animation_list():
				var a: Animation = lib.get_animation(an)
				var kinds = {}
				for t in a.get_track_count():
					var k = a.track_get_type(t)
					kinds[k] = kinds.get(k, 0) + 1
				print("  anim '%s' length=%.3f loop=%s tracks=%d types=%s first_path=%s" % [an, a.length, LOOP[a.loop_mode], a.get_track_count(), kinds, a.track_get_path(0)])
	var profile = SkeletonProfileHumanoid.new()
	var missing_req = []
	var mapped = 0
	for i in profile.bone_size:
		var bn = profile.get_bone_name(i)
		if sk.find_bone(bn) >= 0:
			mapped += 1
		elif profile.is_required(i):
			missing_req.append(bn)
	print("SkeletonProfileHumanoid: %d/%d profile bones present by exact name; missing required: %s" % [mapped, profile.bone_size, missing_req])
	if args.size() > 1:
		var lib = load(args[1])
		print("library ", args[1], " -> ", lib.get_class(), " anims=", lib.get_animation_list() if lib is AnimationLibrary else "n/a")
	quit()
