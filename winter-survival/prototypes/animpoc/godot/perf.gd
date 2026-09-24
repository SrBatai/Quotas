extends SceneTree
# Draw calls for N instances of multi-material vs vertex-colour single-material skinned characters,
# and auto-LOD levels generated at import for flat-shaded meshes.
func count_frame(model: String, n: int) -> Array:
	for c in get_root().get_children():
		c.queue_free()
	await process_frame
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.position = Vector3(0, 30, 30)
	cam.look_at(Vector3.ZERO)
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, 35, 0)
	get_root().add_child(sun)
	for i in n:
		var inst: Node3D = load(model).instantiate()
		inst.position = Vector3((i % 8) * 2.0 - 7, 0, (i / 8) * 2.0 - 5)
		get_root().add_child(inst)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var dc = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var obj = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var prim = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	return [dc, obj, prim]

func lods(model: String):
	var inst: Node = load(model).instantiate()
	var out = []
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = mi.mesh
		for s in m.get_surface_count():
			var d = RenderingServer.mesh_get_surface(m.get_rid(), s)
			var idx_count = d.get("index_count", 0)
			var lod_list = []
			for l in d.get("lods", []):
				lod_list.append(l["index_data"].size() / (2 if d.get("vertex_count", 0) <= 65535 else 4) / 3)
			out.append("%s[%d]: tris=%d lods=%s" % [mi.name, s, idx_count / 3, lod_list])
	print("LOD ", model.get_file(), " -> ", out)

func _init():
	await process_frame
	get_root().size = Vector2i(800, 600)
	for n in [1, 40]:
		var a = await count_frame("res://models/survivor.glb", n)
		var b = await count_frame("res://models/survivor_vcol.glb", n)
		print("N=%d  multi-material(8 surf): draw_calls=%d objects=%d prims=%d | vcol(1 surf): draw_calls=%d objects=%d prims=%d" % [n, a[0], a[1], a[2], b[0], b[1], b[2]])
	for m in ["res://models/survivor.glb", "res://models/cabin.glb", "res://models/pine_a.glb", "res://models/pickup_truck.glb"]:
		lods(m)
	quit()
