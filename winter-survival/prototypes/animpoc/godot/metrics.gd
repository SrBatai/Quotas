extends SceneTree
# Foot-contact metrics: min ankle height and stance-foot backward speed (m/s) per model/library/anim.
func find_first(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r = find_first(c, cls)
		if r:
			return r
	return null

func measure(model: String, lib_path: String, anim: String):
	var inst: Node3D = load(model).instantiate()
	get_root().add_child(inst)
	var ap: AnimationPlayer = find_first(inst, "AnimationPlayer")
	if ap == null:
		ap = AnimationPlayer.new()
		inst.add_child(ap)
		ap.root_node = NodePath("..")
	if lib_path != "":
		var lib = load(lib_path)
		if lib is PackedScene:
			lib = find_first(lib.instantiate(), "AnimationPlayer").get_animation_library("")
		if ap.has_animation_library(""):
			ap.remove_animation_library("")
		ap.add_animation_library("", lib)
	var sk: Skeleton3D = find_first(inst, "Skeleton3D")
	var a: Animation = ap.get_animation(anim)
	ap.play(anim)
	var n := 60
	var lf := sk.find_bone("LeftFoot")
	var rf := sk.find_bone("RightFoot")
	var ys := []
	var zs := []
	for i in n + 1:
		ap.seek(a.length * i / n, true)
		var gl: Vector3 = (sk.global_transform * sk.get_bone_global_pose(lf)).origin
		var gr: Vector3 = (sk.global_transform * sk.get_bone_global_pose(rf)).origin
		ys.append([gl.y, gr.y])
		zs.append([gl.z, gr.z])
	var min_y := 99.0
	var max_y := -99.0
	for p in ys:
		min_y = min(min_y, p[0], p[1])
		max_y = max(max_y, p[0], p[1])
	# stance speed: frames where the left ankle is within 5 mm of its minimum height
	var dt := a.length / n
	var sp := []
	for i in n:
		if ys[i][0] < min_y + 0.005 and ys[i + 1][0] < min_y + 0.005:
			sp.append(-(zs[i + 1][0] - zs[i][0]) / dt)
	var avg := 0.0
	for s in sp:
		avg += s
	avg = avg / max(1, sp.size())
	print("%-28s lib=%-26s %-14s motion_scale=%.3f ankle_y min=%.3f max=%.3f  stance_speed=%.2f m/s (%d samples)" % [model.get_file(), lib_path.get_file(), anim, sk.motion_scale, min_y, max_y, avg, sp.size()])
	inst.queue_free()

func _init():
	await process_frame
	measure("res://models/survivor.glb", "", "Walk")
	measure("res://models/survivor.glb", "", "Run")
	measure("res://models/survivor_rt.glb", "", "Walk")
	measure("res://models/zombie.glb", "res://models/survivor.glb", "Walk")
	measure("res://models/zombie_rt.glb", "res://models/survivor_lib.glb", "Walk")
	measure("res://models/zombie_rt.glb", "res://models/survivor_lib.glb", "ZombieShamble")
	measure("res://models/zombie.glb", "res://models/survivor.glb", "ZombieShamble")
	quit()
