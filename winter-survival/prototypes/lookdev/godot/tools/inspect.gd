extends SceneTree
## Prints node tree, AABBs and surface material names of every glb (headless).
func _init() -> void:
	var dir := DirAccess.open("res://assets/models")
	var files: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".glb"):
			files.append("res://assets/models/" + f)
	var cd := DirAccess.open("res://assets/models/chars")
	for f in cd.get_files():
		if f.ends_with(".glb"):
			files.append("res://assets/models/chars/" + f)
	for path in files:
		var ps: PackedScene = load(path)
		if ps == null:
			print("FAILED ", path)
			continue
		var inst := ps.instantiate()
		get_root().add_child(inst)
		print("=== ", path)
		_walk(inst, 0)
		inst.queue_free()
	quit()

func _walk(n: Node, depth: int) -> void:
	var line := "  ".repeat(depth) + n.name + " (" + n.get_class() + ")"
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var aabb := mi.get_aabb()
		line += " aabb=%s size=%s" % [aabb.position, aabb.size]
		var mats := []
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			mats.append(m.resource_name if m != null else "null")
		line += " mats=" + str(mats) + " tris~" + str(_tris(mi.mesh))
	elif n is Node3D and not (n is MeshInstance3D):
		line += " pos=%s" % (n as Node3D).position
	print(line)
	for c in n.get_children():
		_walk(c, depth + 1)

func _tris(m: Mesh) -> int:
	var t := 0
	for i in m.get_surface_count():
		var arr := m.surface_get_arrays(i)
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and idx.size() > 0:
			t += idx.size() / 3
		else:
			t += arr[Mesh.ARRAY_VERTEX].size() / 3
	return t
