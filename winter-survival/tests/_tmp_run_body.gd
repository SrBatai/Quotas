extends RefCounted
var tree: SceneTree
func run(p_tree: SceneTree) -> void:
	tree = p_tree
	await tree.process_frame
	var ready := false
	Events.world_ready.connect(func() -> void: ready = true)
	GameFlow.play_offline()
	var waited := 0
	while not ready and waited < 900:
		await tree.process_frame
		waited += 1
	print("world ready after %d frames" % waited)
	waited = 0
	while GameFlow.local_player() == null and waited < 600:
		await tree.process_frame
		waited += 1
	for i in 10:
		await tree.process_frame
	var player: Player = GameFlow.local_player()
	var world: World = tree.current_scene.get_node("World")
	var visual: CharacterVisual = player.view.visual
	print("player at %s skeletal=%s" % [player.global_position, visual.is_skeletal])
	player.global_position = world.get_spawn_point() + Vector3(-1.0, 0.3, 3.0)
	for i in 10:
		await tree.physics_frame
	player.input.scripted_move = Vector2(-1, 0)
	player.input.scripted_run = true
	for i in 45:
		await tree.physics_frame
	var prev_pos := Vector3.INF
	var prev_feet := {}
	for i in 50:
		await tree.physics_frame
		var pos := player.global_position
		var feet := visual.foot_positions()
		var inv := visual.global_transform.affine_inverse()
		if prev_pos != Vector3.INF:
			var bd := pos - prev_pos
			var lowest := ""
			var ly := INF
			for k in feet:
				var y: float = (inv * (feet[k] as Vector3)).y
				if y < ly:
					ly = y
					lowest = k
			var fd: Vector3 = (feet[lowest] as Vector3) - (prev_feet[lowest] as Vector3)
			var rel: Vector3 = (inv * (feet[lowest] as Vector3)) - (inv * (prev_feet[lowest] as Vector3))
			print("tick %2d body d=(%+.4f %+.4f %+.4f) |h|=%.4f  %-10s y=%.3f world d=(%+.4f %+.4f) rel d=(%+.4f %+.4f) scale=%.3f state=%s vis_yaw=%.4f floor=%s" % [
				i, bd.x, bd.y, bd.z, Vector2(bd.x, bd.z).length(), lowest, ly, fd.x, fd.z, rel.x, rel.z, visual.time_scale, visual.state, visual.global_rotation.y, player.is_on_floor()])
		prev_pos = pos
		prev_feet = feet
	tree.quit(0)
