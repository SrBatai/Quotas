extends SceneTree
## Prints the node tree (types, AABBs, material names, anchor positions) of every res://assets/models/*.glb.
## Run: godot --headless --path . -s tests/inspect_models.gd


func _initialize() -> void:
	var dir := DirAccess.open("res://assets/models")
	if dir == null:
		print("no models dir")
		quit(1)
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".glb"):
			files.append(f)
		f = dir.get_next()
	files.sort()
	for name in files:
		var path := "res://assets/models/" + name
		if not ResourceLoader.exists(path, "PackedScene"):
			print("== ", name, "  (not imported yet)")
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			print("== ", name, "  ERROR cannot load")
			continue
		var inst := scene.instantiate()
		print("== ", name)
		_dump(inst, 1)
		inst.free()
	quit(0)


func _dump(n: Node, depth: int) -> void:
	var info := n.name + " (" + n.get_class() + ")"
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		var names := []
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			names.append(m.resource_name if m != null else "null")
		info += " aabb=" + str(mi.get_aabb()) + " mats=" + str(names)
	elif n is Node3D:
		info += " pos=" + str((n as Node3D).position)
		if (n as Node3D).rotation_degrees != Vector3.ZERO:
			info += " rot=" + str((n as Node3D).rotation_degrees)
	print("  ".repeat(depth), info)
	for c in n.get_children():
		_dump(c, depth + 1)
