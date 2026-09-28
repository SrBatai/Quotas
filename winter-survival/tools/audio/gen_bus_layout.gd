extends SceneTree
## S1: writes res://default_bus_layout.tres from AudioManager.ensure_buses() (the same layout the manager builds at
## run time when the file is missing), then probes the reverb send: an AudioStreamPlayer3D inside the listener's
## ReverbSend area must find it through a physics point query on layer 20 (Jolt).
## Run: godot --headless --path . -s tools/audio/gen_bus_layout.gd [++ --check]


func _initialize() -> void:
	await process_frame
	var check := OS.get_cmdline_user_args().has("--check")
	var am: Node = root.get_node("AudioManager")
	if not check:
		# rebuild from scratch so the saved file is exactly the code's layout
		while AudioServer.bus_count > 1:
			AudioServer.remove_bus(AudioServer.bus_count - 1)
		for k in AudioServer.get_bus_effect_count(0):
			AudioServer.remove_bus_effect(0, 0)
		AudioServer.set_bus_name(0, "Master")
		am.call("ensure_buses")
		var err := ResourceSaver.save(AudioServer.generate_bus_layout(), "res://default_bus_layout.tres")
		print("bus layout saved: %s (%d buses)" % [error_string(err), AudioServer.bus_count])
	var names := []
	for i in AudioServer.bus_count:
		names.append("%s→%s[%d fx]" % [AudioServer.get_bus_name(i), AudioServer.get_bus_send(i), AudioServer.get_bus_effect_count(i)])
	print("buses: ", ", ".join(names))
	# reverb send probe
	var space := (root.get_node("AudioManager/ReverbSend") as Area3D).get_world_3d().direct_space_state
	await physics_frame
	await physics_frame
	var q := PhysicsPointQueryParameters3D.new()
	q.position = (root.get_node("AudioManager/ReverbSend") as Area3D).global_position + Vector3(10, 0, 5)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = 1 << 19
	var hits := space.intersect_point(q, 4)
	print("reverb send point query: %d hit(s)%s" % [hits.size(), (" → " + str(hits[0]["collider"])) if not hits.is_empty() else ""])
	quit(0 if not hits.is_empty() else 1)
